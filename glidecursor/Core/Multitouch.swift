import Foundation
import IOKit

// MultitouchSupport（非公開フレームワーク）を dlopen で読み、
// トラックパッド / Magic Mouse に指が「触れた」「離れた」瞬間を受け取る。
// 構造体レイアウトは GlideProbe で検証済み（stride 96）。OS 更新で変わる可能性があるので、
// 起動時に stride を確認し、合わなければ MT を使わない（アプリは落とさない）。

// MARK: - Private API bindings

struct MTPoint { var x: Float; var y: Float }
struct MTReadout { var pos: MTPoint; var vel: MTPoint }
struct MTFinger {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32          // 0 notTouching, 1 starting, 2 hovering, 3 making, 4 touching, 5 breaking, 6 lingering, 7 leaving
    var fingerID: Int32
    var handID: Int32
    var normalized: MTReadout
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var mm: MTReadout
    var zero2: (Int32, Int32)
    var unk2: Float
}

private typealias MTContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
private typealias FnCreateList = @convention(c) () -> Unmanaged<CFArray>?
private typealias FnRegister = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
private typealias FnStart = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
private typealias FnStop = @convention(c) (UnsafeMutableRawPointer) -> Int32
private typealias FnIsBuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
private typealias FnGetFamily = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>) -> Int32
private typealias FnGetDevID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
private typealias FnGetService = @convention(c) (UnsafeMutableRawPointer) -> io_service_t

private struct MTAPI {
    let createList: FnCreateList
    let register: FnRegister
    let unregister: FnRegister?
    let start: FnStart
    let stop: FnStop?
    let isBuiltIn: FnIsBuiltIn?
    let getFamily: FnGetFamily?
    let getDevID: FnGetDevID?
    let getService: FnGetService?

    static let shared: MTAPI? = {
        guard MemoryLayout<MTFinger>.stride == 96,
              let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        else { return nil }
        func sym<T>(_ n: String, _ t: T.Type) -> T? { dlsym(h, n).map { unsafeBitCast($0, to: t) } }
        guard let c = sym("MTDeviceCreateList", FnCreateList.self),
              let r = sym("MTRegisterContactFrameCallback", FnRegister.self),
              let s = sym("MTDeviceStart", FnStart.self) else { return nil }
        return MTAPI(createList: c, register: r,
                     unregister: sym("MTUnregisterContactFrameCallback", FnRegister.self),
                     start: s, stop: sym("MTDeviceStop", FnStop.self),
                     isBuiltIn: sym("MTDeviceIsBuiltIn", FnIsBuiltIn.self),
                     getFamily: sym("MTDeviceGetFamilyID", FnGetFamily.self),
                     getDevID: sym("MTDeviceGetDeviceID", FnGetDevID.self),
                     getService: sym("MTDeviceGetService", FnGetService.self))
    }()
}

// MARK: - Device description

/// MT デバイス 1 台。key は再接続しても変わらない（Multitouch ID 由来）。
/// regID（IORegistry entry ID）は再接続のたびに変わるので、CGEvent の送信元との照合だけに使う。
struct MTDeviceInfo {
    let key: String
    let regID: UInt64
    let family: Int32
    let isBuiltIn: Bool
    let name: String
    var isMagicMouse: Bool { family == 112 || family == 113 }
}

/// 指 1 回分の接触（触れてから離れるまで）。
struct TouchSession {
    var downTime: TimeInterval = 0
    var liftTime: TimeInterval = 0
    var fingers = 0
    var maxFingers = 0
    /// この接触がグライドを止めた
    var stoppedGlide = false
}

protocol MultitouchDelegate: AnyObject {
    /// MT スレッドから呼ばれる。グライドを即止めるためのもので、軽い処理だけをすること。
    func touchDown(device: MTDeviceInfo)
    /// MT スレッドから呼ばれる。session は離れた時点の状態。
    func touchLift(device: MTDeviceInfo, session: TouchSession)
}

// MARK: - Manager

final class MultitouchManager {
    static let shared = MultitouchManager()

    weak var delegate: MultitouchDelegate?
    private(set) var isAvailable = MTAPI.shared != nil

    private let lock = NSLock()
    private var devices: [UnsafeMutableRawPointer: MTDeviceInfo] = [:]
    private var sessions: [UnsafeMutableRawPointer: TouchSession] = [:]
    private var deviceList: CFArray?
    private var running = false

    private var notifyPort: IONotificationPortRef?
    private var addedIter: io_iterator_t = 0
    private var removedIter: io_iterator_t = 0
    private var restartWork: DispatchWorkItem?

    /// 変化（接続・切断）を UI 側へ知らせる。メインスレッドで呼ぶ。
    var onDevicesChanged: (([MTDeviceInfo]) -> Void)?

    // MARK: Lifecycle

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let api = MTAPI.shared, !running else { return }
        running = true
        guard let list = api.createList()?.takeRetainedValue() else { publish(); return }
        deviceList = list
        var found: [UnsafeMutableRawPointer: MTDeviceInfo] = [:]
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            found[dev] = describe(dev, api: api)
        }
        lock.lock()
        devices = found
        sessions = [:]
        lock.unlock()
        for dev in found.keys {
            api.register(dev, mtCallback)
            _ = api.start(dev, 0)
        }
        watchHotplug()
        publish()
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let api = MTAPI.shared, running else { return }
        running = false
        lock.lock()
        let devs = Array(devices.keys)
        devices = [:]
        sessions = [:]
        lock.unlock()
        for dev in devs {
            api.unregister?(dev, mtCallback)
            _ = api.stop?(dev)
        }
        deviceList = nil
    }

    /// 接続・切断・スリープ復帰のあとに、デバイス一覧を取り直す。
    func scheduleRestart(after delay: TimeInterval = 0.5) {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            self.stop()
            self.start()
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Queries (any thread)

    func info(forRegID regID: UInt64) -> MTDeviceInfo? {
        lock.lock(); defer { lock.unlock() }
        return devices.values.first { $0.regID == regID }
    }

    /// 送信元デバイスの現在の接触本数（MT デバイスでなければ nil）
    func fingers(forRegID regID: UInt64) -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard let dev = devices.first(where: { $0.value.regID == regID })?.key else { return nil }
        return sessions[dev]?.fingers ?? 0
    }

    func session(forRegID regID: UInt64) -> TouchSession? {
        lock.lock(); defer { lock.unlock() }
        guard let dev = devices.first(where: { $0.value.regID == regID })?.key else { return nil }
        return sessions[dev]
    }

    /// 触れている最中の接触に「グライドを止めた」印を付ける（クリック抑止に使う）
    func markStoppedGlide(regID: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard let dev = devices.first(where: { $0.value.regID == regID })?.key else { return }
        sessions[dev]?.stoppedGlide = true
    }

    /// グライドを止めた接触が、ちょうど離れたところか。
    /// tap to click のクリックは指が離れて数 ms 後に届くので、それを捨てるために使う。1 回だけ true を返す。
    /// 送信元が分からないクリック（sender 0）は、すべての MT デバイスを見る。
    func consumeStopTap(regID: UInt64, within window: TimeInterval) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        let candidates: [UnsafeMutableRawPointer]
        if let dev = devices.first(where: { $0.value.regID == regID })?.key {
            candidates = [dev]
        } else if regID == 0 {
            candidates = Array(devices.keys)
        } else {
            return false   // MT ではないマウスのクリック
        }
        for dev in candidates {
            guard var s = sessions[dev], s.stoppedGlide, s.fingers == 0,
                  s.liftTime > 0, now - s.liftTime <= window else { continue }
            s.stoppedGlide = false
            sessions[dev] = s
            return true
        }
        return false
    }

    var currentDevices: [MTDeviceInfo] {
        lock.lock(); defer { lock.unlock() }
        return Array(devices.values)
    }

    // MARK: Frame callback (MT thread)

    fileprivate func handleFrame(_ dev: UnsafeMutableRawPointer, _ fingers: UnsafeMutableRawPointer?, _ count: Int32) {
        var n = 0
        if let raw = fingers, count > 0 {
            let f = raw.assumingMemoryBound(to: MTFinger.self)
            for i in 0..<Int(count) where f[i].state == 3 || f[i].state == 4 { n += 1 }   // making / touching
        }
        let now = ProcessInfo.processInfo.systemUptime

        lock.lock()
        guard let info = devices[dev] else { lock.unlock(); return }
        var s = sessions[dev] ?? TouchSession()
        let prev = s.fingers
        var down = false, lifted = false
        if prev == 0 && n > 0 {
            s = TouchSession(downTime: now, liftTime: 0, fingers: n, maxFingers: n, stoppedGlide: false)
            down = true
        } else {
            s.fingers = n
            s.maxFingers = max(s.maxFingers, n)
            if prev > 0 && n == 0 { s.liftTime = now; lifted = true }
        }
        sessions[dev] = s
        lock.unlock()

        if down { delegate?.touchDown(device: info) }
        if lifted { delegate?.touchLift(device: info, session: s) }
    }

    // MARK: Helpers

    private func describe(_ dev: UnsafeMutableRawPointer, api: MTAPI) -> MTDeviceInfo {
        var fam: Int32 = -1; _ = api.getFamily?(dev, &fam)
        var did: UInt64 = 0; _ = api.getDevID?(dev, &did)
        let builtIn = api.isBuiltIn?(dev) ?? false
        var regID: UInt64 = 0
        var name = ""
        if let gs = api.getService {
            let svc = gs(dev)
            if svc != 0 {
                IORegistryEntryGetRegistryEntryID(svc, &regID)
                name = registryString(svc, "Product") ?? ""
            }
        }
        if name.isEmpty {
            name = builtIn ? "Built-in Trackpad" : (fam == 112 ? "Magic Mouse" : "Trackpad")
        }
        return MTDeviceInfo(key: "mt:" + String(did, radix: 16), regID: regID, family: fam, isBuiltIn: builtIn, name: name)
    }

    private func publish() {
        let list = currentDevices
        onDevicesChanged?(list)
    }

    private func watchHotplug() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
        let cb: IOServiceMatchingCallback = { _, iter in
            while case let o = IOIteratorNext(iter), o != 0 { IOObjectRelease(o) }
            MultitouchManager.shared.scheduleRestart()
        }
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("AppleMultitouchDevice"), cb, nil, &addedIter)
        while case let o = IOIteratorNext(addedIter), o != 0 { IOObjectRelease(o) }   // 既存分を読み捨てて通知を有効にする
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("AppleMultitouchDevice"), cb, nil, &removedIter)
        while case let o = IOIteratorNext(removedIter), o != 0 { IOObjectRelease(o) }
    }
}

private let mtCallback: MTContactCallback = { dev, fingers, count, _, _ in
    if let dev { MultitouchManager.shared.handleFrame(dev, fingers, count) }
    return 0
}

func registryString(_ entry: io_registry_entry_t, _ key: String) -> String? {
    let v = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}
