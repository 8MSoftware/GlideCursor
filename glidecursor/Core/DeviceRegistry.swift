import Foundation
import IOKit
import Combine

/// 設定画面に出すポインティングデバイス 1 台。
struct GlideDevice: Identifiable, Hashable {
    enum Kind: String { case trackpad, magicMouse, mouse }
    let id: String          // 永続キー。MT デバイスは "mt:<Multitouch ID>"、それ以外は "hid:<vendor>:<product>"
    let name: String
    let kind: Kind
    var connected: Bool
}

/// CGEvent の送信元（IOHIDEvent の sender ID ＝ IORegistry entry ID）を、
/// 再接続しても変わらないデバイスキーへ対応付ける。
final class DeviceRegistry: ObservableObject {
    static let shared = DeviceRegistry()

    @Published private(set) var devices: [GlideDevice] = []

    /// sender ID → デバイス。タップ（メインスレッド）からだけ触る。
    private var senderCache: [UInt64: GlideDevice] = [:]

    init() {
        MultitouchManager.shared.onDevicesChanged = { [weak self] list in
            self?.mergeMultitouch(list)
        }
    }

    func device(forSender sender: UInt64) -> GlideDevice? {
        dispatchPrecondition(condition: .onQueue(.main))
        if sender == 0 { return nil }
        if let d = senderCache[sender] { return d }
        let d = resolve(sender)
        if let d {
            senderCache[sender] = d
            // タッチセンサーのないマウスは指を離した瞬間が分からないので、慣性の対象にしない
            if d.kind != .mouse && !devices.contains(where: { $0.id == d.id }) { devices.append(d); sortDevices() }
        }
        return d
    }

    // MARK: -

    private func mergeMultitouch(_ list: [MTDeviceInfo]) {
        senderCache = [:]   // regID は再接続で変わるので作り直す
        let mtKeys = Set(list.map(\.key))
        var result = devices.map { d -> GlideDevice in
            var d = d
            if d.id.hasPrefix("mt:") { d.connected = mtKeys.contains(d.id) }
            return d
        }
        for info in list where !result.contains(where: { $0.id == info.key }) {
            result.append(GlideDevice(id: info.key, name: info.name,
                                      kind: info.isMagicMouse ? .magicMouse : .trackpad, connected: true))
        }
        devices = result
        sortDevices()
    }

    private func sortDevices() {
        let order: [GlideDevice.Kind: Int] = [.trackpad: 0, .magicMouse: 1, .mouse: 2]
        devices.sort { (order[$0.kind]!, $0.name) < (order[$1.kind]!, $1.name) }
    }

    private func resolve(_ sender: UInt64) -> GlideDevice? {
        if let info = MultitouchManager.shared.info(forRegID: sender) {
            return GlideDevice(id: info.key, name: info.name,
                               kind: info.isMagicMouse ? .magicMouse : .trackpad, connected: true)
        }
        guard let match = IORegistryEntryIDMatching(sender) else { return nil }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, match)
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }

        // MT の一覧更新が追いついていない場合
        if IOObjectConformsTo(svc, "AppleMultitouchDevice") != 0,
           let mtID = registryNumber(svc, "Multitouch ID") {
            let family = registryNumber(svc, "Family ID") ?? 0
            let name = registryString(svc, "Product") ?? "Trackpad"
            return GlideDevice(id: "mt:" + String(mtID, radix: 16), name: name,
                               kind: (family == 112 || family == 113) ? .magicMouse : .trackpad, connected: true)
        }
        let vendor = registryNumber(svc, "VendorID") ?? 0
        let product = registryNumber(svc, "ProductID") ?? 0
        let name = registryString(svc, "Product") ?? "Mouse"
        return GlideDevice(id: "hid:\(vendor):\(product)", name: name, kind: .mouse, connected: true)
    }

    private func registryNumber(_ entry: io_registry_entry_t, _ key: String) -> UInt64? {
        let v = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
        return (v as? NSNumber)?.uint64Value
    }
}
