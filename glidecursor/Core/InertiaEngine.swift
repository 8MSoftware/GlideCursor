import Foundation
import CoreGraphics

/// 慣性でカーソルを動かす。速度は px/秒、減衰は時定数（秒）。
/// stop() は任意のスレッドから呼べ、戻った時点で以後のカーソル移動は 1 つも出ない（移動の投稿もロック内で行う）。
final class InertiaEngine {
    static let shared = InertiaEngine()

    /// 自分が投稿したイベントの印
    static let eventTag: Int64 = 0x474C4944   // 'GLID'

    struct Params {
        var timeConstant: Double   // 速度が 1/e になるまでの秒数
        var stopSpeed: Double = 20 // これ以下で止める（px/秒）
    }

    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "glidecursor.inertia", qos: .userInteractive)
    private var running = false
    private var velocity = CGVector.zero
    private var position = CGPoint.zero
    private var lastTick: TimeInterval = 0
    private var params = Params(timeConstant: 0.4)
    private let source = CGEventSource(stateID: .hidSystemState)

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    func start(velocity v: CGVector, params p: Params) {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
        guard let here = CGEvent(source: nil)?.location else { return }
        velocity = v
        position = here
        params = p
        lastTick = ProcessInfo.processInfo.systemUptime
        running = true

        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / 120), leeway: .microseconds(500))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    /// 慣性の起点を外から届いた移動の分だけずらす
    func nudge(dx: Double, dy: Double) {
        lock.lock(); defer { lock.unlock() }
        guard running else { return }
        position.x += dx
        position.y += dy
    }

    /// 止めたら true（もともと止まっていたら false）
    @discardableResult
    func stop() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopLocked()
    }

    @discardableResult
    private func stopLocked() -> Bool {
        let was = running
        running = false
        velocity = .zero
        timer?.cancel()
        timer = nil
        return was
    }

    private func tick() {
        lock.lock(); defer { lock.unlock() }
        guard running else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(max(now - lastTick, 0), 0.05)
        lastTick = now

        // 指数減衰。区間内で積分した移動量を使うので、フレーム間隔が揺れても軌跡が変わらない。
        let tau = params.timeConstant
        let decay = exp(-dt / tau)
        let travel = tau * (1 - decay)
        var next = CGPoint(x: position.x + velocity.dx * travel, y: position.y + velocity.dy * travel)
        velocity.dx *= decay
        velocity.dy *= decay

        // 画面端：はみ出した成分だけ止めて、壁に沿って滑らせる
        if !Self.onAnyDisplay(next) {
            guard let screen = Self.display(containing: position) else { stopLocked(); return }
            if next.x < screen.minX { next.x = screen.minX; velocity.dx = 0 }
            if next.x > screen.maxX - 1 { next.x = screen.maxX - 1; velocity.dx = 0 }
            if next.y < screen.minY { next.y = screen.minY; velocity.dy = 0 }
            if next.y > screen.maxY - 1 { next.y = screen.maxY - 1; velocity.dy = 0 }
        }

        let dx = next.x.rounded() - position.x.rounded()
        let dy = next.y.rounded() - position.y.rounded()
        position = next
        if dx != 0 || dy != 0 {
            post(to: next, dx: dx, dy: dy)
        }

        if hypot(velocity.dx, velocity.dy) < params.stopSpeed { stopLocked() }
    }

    private func post(to p: CGPoint, dx: CGFloat, dy: CGFloat) {
        guard let e = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                              mouseCursorPosition: CGPoint(x: p.x.rounded(), y: p.y.rounded()),
                              mouseButton: .left) else { return }
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        e.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        e.post(tap: .cghidEventTap)
    }

    private static func displays() -> [CGRect] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &ids, &count)
        return (0..<Int(count)).map { CGDisplayBounds(ids[$0]) }
    }

    private static func onAnyDisplay(_ p: CGPoint) -> Bool { displays().contains { $0.contains(p) } }
    private static func display(containing p: CGPoint) -> CGRect? {
        let r = displays()
        return r.first { $0.contains(p) } ?? r.min { dist($0, p) < dist($1, p) }
    }
    private static func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }
}
