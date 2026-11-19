import Foundation
import CoreGraphics
import AppKit
import os

private let log = Logger(subsystem: "jp.yaoyorozu.glidecursor", category: "glide")

/// 全体の司令塔。
/// - 指が離れた瞬間（MT の lift）に、直前のカーソル移動の速度で慣性を始める
/// - 指が触れた瞬間（MT の touch down）に慣性を止める
/// - 慣性を止めるためのタップ（tap to click）が生んだクリックは捨てる
/// - 慣性を出すかどうかはデバイスごとの設定に従う
final class GlideController: MultitouchDelegate {
    static let shared = GlideController()

    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isActive = false

    // 送信元ごとの直近のカーソル移動（メインスレッド専用）
    private struct Sample { let t: TimeInterval; let dx: Double; let dy: Double; let drag: Bool }
    private var samples: [UInt64: [Sample]] = [:]

    // いま走っている慣性を始めたデバイスと時刻（離した直後に届く残りの移動を見分ける）
    private var glideSource: UInt64 = 0
    private var glideStart: TimeInterval = 0

    // 抑止した mouseDown に対応する mouseUp を捨てるための記録
    private var suppressedUps: [CGEventType: TimeInterval] = [:]

    /// MT が使えないとき（OS 更新で非公開 API が変わったなど）は false
    var multitouchAvailable: Bool { MultitouchManager.shared.isAvailable }

    // MARK: Lifecycle

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isActive else { return }
        isActive = true
        MultitouchManager.shared.delegate = self
        MultitouchManager.shared.start()
        startTap()
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isActive else { return }
        isActive = false
        InertiaEngine.shared.stop()
        stopTap()
        MultitouchManager.shared.stop()
        samples = [:]
        suppressedUps = [:]
    }

    /// スリープ復帰後などに MT デバイスを取り直す
    func refreshDevices() {
        guard isActive else { return }
        MultitouchManager.shared.scheduleRestart(after: 1.0)
    }

    // MARK: MultitouchDelegate (MT thread)

    func touchDown(device: MTDeviceInfo) {
        if InertiaEngine.shared.stop() {
            MultitouchManager.shared.markStoppedGlide(regID: device.regID)
            log.debug("touch \(device.name, privacy: .public): glide stopped")
        }
    }

    func touchLift(device: MTDeviceInfo, session: TouchSession) {
        // 指が離れた直後に届くカーソル移動も拾ってから判定する
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) { [weak self] in
            self?.evaluateFlick(device: device, session: session)
        }
    }

    // MARK: Flick (main thread)

    private func evaluateFlick(device: MTDeviceInfo, session: TouchSession) {
        let settings = SettingsManager.shared
        func skip(_ why: String) { log.debug("lift \(device.name, privacy: .public): no glide (\(why, privacy: .public))") }
        guard isActive, settings.isEnabled else { return }
        // トラックパッドは 1 本指の操作だけ（2 本指以上はスクロールやジェスチャー）
        guard device.isMagicMouse || session.maxFingers == 1 else { return skip("\(session.maxFingers) fingers") }
        guard let dev = DeviceRegistry.shared.device(forSender: device.regID),
              settings.isDeviceEnabled(dev) else { return skip("device off") }
        guard MultitouchManager.shared.fingers(forRegID: device.regID) == 0 else { return skip("touched again") }
        guard let list = samples[device.regID], let last = list.last else { return skip("no moves") }

        // 指を止めてから離した場合は慣性を出さない（トラックボールと同じ）
        guard last.t >= session.liftTime - 0.04, last.t >= session.downTime else {
            return skip(String(format: "still for %.0f ms before lift", (session.liftTime - last.t) * 1000))
        }

        let window = list.filter { $0.t >= last.t - 0.06 && $0.t >= session.downTime }
        guard !window.contains(where: \.drag) else { return skip("drag") }
        guard window.count >= 3 else { return skip("\(window.count) samples") }
        let span = window.last!.t - window.first!.t
        guard span > 0.004 else { return skip("span too short") }
        // 最初のサンプルの移動量はそれ以前の区間に属するので除く
        let sx = window.dropFirst().reduce(0) { $0 + $1.dx }
        let sy = window.dropFirst().reduce(0) { $0 + $1.dy }
        var v = CGVector(dx: sx / span, dy: sy / span)

        let speed = hypot(v.dx, v.dy)
        guard speed >= settings.flickThreshold else { return skip("speed \(Int(speed)) px/s") }
        let scaled = min(speed * settings.speedMultiplier, settings.maxSpeed)
        v.dx *= scaled / speed
        v.dy *= scaled / speed

        samples[device.regID] = nil
        glideSource = device.regID
        glideStart = ProcessInfo.processInfo.systemUptime
        log.debug("lift \(device.name, privacy: .public): glide at \(Int(scaled)) px/s (measured \(Int(speed)), \(window.count) samples)")
        InertiaEngine.shared.start(velocity: v, params: .init(timeConstant: settings.glideLength))
    }

    // MARK: Event tap (main thread)

    private func startTap() {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                    .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                    .otherMouseDown, .otherMouseUp, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: tapCallback, userInfo: nil) else {
            NSLog("GlideCursor: event tap を作れない（アクセシビリティ権限が必要）")
            return
        }
        machPort = port
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func stopTap() {
        if let port = machPort { CGEvent.tapEnable(tap: port, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        machPort = nil
        runLoopSource = nil
    }

    /// タップが動いているか（アクセシビリティ権限がなければ false）
    var isTapRunning: Bool { machPort != nil }

    /// 権限が後から与えられたときに作り直す
    func retryTapIfNeeded() {
        if isActive && machPort == nil { startTap() }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = machPort { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == InertiaEngine.eventTag {
            return Unmanaged.passUnretained(event)
        }
        let now = Self.eventTime(event)
        let sender = Self.senderID(of: event)

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            guard sender != 0 else { break }   // システムが作った移動は無視
            record(sender: sender, event: event, drag: type != .mouseMoved, now: now)
            if InertiaEngine.shared.isRunning {
                let straggler = sender == glideSource
                    && ProcessInfo.processInfo.systemUptime - glideStart < 0.15
                    && MultitouchManager.shared.fingers(forRegID: sender) == 0
                if straggler {
                    // 離した直後に遅れて届いた移動。止めずに、慣性の起点をずらして飛びを防ぐ
                    InertiaEngine.shared.nudge(dx: Double(event.getIntegerValueField(.mouseEventDeltaX)),
                                               dy: Double(event.getIntegerValueField(.mouseEventDeltaY)))
                } else {
                    InertiaEngine.shared.stop()
                }
            }

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if SettingsManager.shared.suppressClickOnStop,
               MultitouchManager.shared.consumeStopTap(regID: sender, within: 0.15) {
                suppressedUps[Self.upType(for: type)] = now
                log.debug("click after stop-tap ignored")
                return nil
            }
            InertiaEngine.shared.stop()

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if let t = suppressedUps.removeValue(forKey: type), now - t < 5.0 {
                return nil
            }

        case .scrollWheel:
            InertiaEngine.shared.stop()

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func record(sender: UInt64, event: CGEvent, drag: Bool, now: TimeInterval) {
        let dx = Double(event.getIntegerValueField(.mouseEventDeltaX))
        let dy = Double(event.getIntegerValueField(.mouseEventDeltaY))
        var list = samples[sender] ?? []
        list.append(Sample(t: now, dx: dx, dy: dy, drag: drag))
        if list.count > 32 { list.removeFirst(list.count - 32) }
        samples[sender] = list
        _ = DeviceRegistry.shared.device(forSender: sender)   // 設定画面の一覧に載せる
    }

    /// イベントの発生時刻を systemUptime と同じ物差し（秒）で返す。
    /// CGEvent の timestamp は環境によって ns か mach 時間なので、起動時に一度見分ける。
    private static let timestampScale: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom) / 1e9
    }()
    private static var timestampIsMach: Bool?

    static func eventTime(_ event: CGEvent) -> TimeInterval {
        let ts = Double(event.timestamp)
        let now = ProcessInfo.processInfo.systemUptime
        if timestampIsMach == nil && ts > 0 {
            if abs(ts * timestampScale - now) < 1.0 { timestampIsMach = true }
            else if abs(ts / 1e9 - now) < 1.0 { timestampIsMach = false }
        }
        switch timestampIsMach {
        case true?: return ts * timestampScale
        case false?: return ts / 1e9
        case nil: return now
        }
    }

    private static func upType(for down: CGEventType) -> CGEventType {
        switch down {
        case .leftMouseDown: return .leftMouseUp
        case .rightMouseDown: return .rightMouseUp
        default: return .otherMouseUp
        }
    }

    // MARK: Sender ID (CGEvent → IOHIDEvent → sender)

    private typealias FnCopyHID = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    private typealias FnSenderID = @convention(c) (UnsafeMutableRawPointer) -> UInt64
    private static let copyHID: FnCopyHID? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventCopyIOHIDEvent")
        .map { unsafeBitCast($0, to: FnCopyHID.self) }
    private static let getSender: FnSenderID? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOHIDEventGetSenderID")
        .map { unsafeBitCast($0, to: FnSenderID.self) }

    static func senderID(of event: CGEvent) -> UInt64 {
        guard let copy = copyHID, let get = getSender,
              let hid = copy(Unmanaged.passUnretained(event).toOpaque()) else { return 0 }
        let id = get(hid)
        Unmanaged<AnyObject>.fromOpaque(hid).release()
        return id
    }
}

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    GlideController.shared.handle(type: type, event: event)
}
