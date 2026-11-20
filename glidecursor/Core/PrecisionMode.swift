import Foundation
import CoreGraphics
import Combine

/// 精密モード:カーソルの動きを一時的に遅くする(×0.1〜0.9)。
/// 入り方は2つ。
/// - ショートカットで切り替え(もう一度押すと出る)
/// - ダブルタップして指を置いたまま待つ(指を離すと出る。設定で選んだときだけ)
/// 精密モードのあいだは、慣性を出さない。
final class PrecisionMode: ObservableObject {
    static let shared = PrecisionMode()

    enum Source { case shortcut, hold }

    /// メインスレッドで読む(メニューバーのアイコン)
    @Published private(set) var isOn = false
    private(set) var source: Source?

    // カーソルの位置は小数で持つ(遅くした移動の端数をためる)
    private var position: CGPoint?
    private var remainder = CGVector.zero

    // ダブルタップホールドの判定(MT スレッドから触るのでロック)
    private let lock = NSLock()
    private var lastTapLift: [UInt64: TimeInterval] = [:]
    private var holdWork: DispatchWorkItem?

    // MARK: 入る・出る(メインスレッド)

    func toggle() {
        if isOn { exit() } else { enter(.shortcut) }
    }

    func enter(_ src: Source) {
        dispatchPrecondition(condition: .onQueue(.main))
        InertiaEngine.shared.stop()
        position = CGEvent(source: nil)?.location
        remainder = .zero
        source = src
        isOn = true
    }

    func exit() {
        dispatchPrecondition(condition: .onQueue(.main))
        isOn = false
        source = nil
        position = nil
    }

    // MARK: ダブルタップホールド(MT スレッド)

    func touchDown(regID: UInt64, isTrackpad: Bool) {
        guard isTrackpad else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let last = lastTapLift[regID]
        lock.unlock()
        // 直前に短いタップがあって、すぐにまた触れた = ダブルタップの2回目
        guard let last, now - last < 0.35 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let s = SettingsManager.shared
            guard s.precisionDoubleTapHold, !self.isOn else { return }
            let work = DispatchWorkItem { [weak self] in
                // 待っているあいだに指が離れていなければ入る
                guard let self, MultitouchManager.shared.fingers(forRegID: regID) ?? 0 > 0 else { return }
                self.enter(.hold)
            }
            self.holdWork?.cancel()
            self.holdWork = work
            // 0 秒なら、2回目に触れた時点ですぐに入る
            DispatchQueue.main.asyncAfter(deadline: .now() + max(s.precisionHoldDelay, 0.01), execute: work)
        }
    }

    func touchLift(regID: UInt64, session: TouchSession) {
        let duration = session.liftTime - session.downTime
        lock.lock()
        // 短く1本指で触れて離した = タップ
        if session.maxFingers == 1 && duration < 0.2 { lastTapLift[regID] = session.liftTime } else { lastTapLift[regID] = nil }
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.holdWork?.cancel()
            self.holdWork = nil
            if self.isOn && self.source == .hold { self.exit() }
        }
    }

    // MARK: 移動を遅くする(タップのコールバック、メインスレッド)

    /// 精密モードのときは、移動の量を縮めて、イベントの位置を書き換える
    func adjust(_ event: CGEvent) {
        guard isOn else { return }
        let k = SettingsManager.shared.precisionFactor
        let dx = Double(event.getIntegerValueField(.mouseEventDeltaX))
        let dy = Double(event.getIntegerValueField(.mouseEventDeltaY))
        let start = position ?? CGPoint(x: event.location.x - dx, y: event.location.y - dy)
        var next = CGPoint(x: start.x + dx * k, y: start.y + dy * k)
        next = Self.clamp(next, near: start)
        position = next

        // アプリに渡す移動量も縮める(整数なので端数はためる)
        remainder.dx += dx * k
        remainder.dy += dy * k
        let ix = remainder.dx.rounded(.towardZero), iy = remainder.dy.rounded(.towardZero)
        remainder.dx -= ix
        remainder.dy -= iy
        event.location = next
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(ix))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(iy))
        // イベントの位置を書き換えるだけでは、カーソルそのものは動きを縮めない(試して確かめた)。
        // カーソルを縮めた位置へ直接移す。移したあとは、しばらく入力が止まる仕様なので、
        // 直後に「マウスとカーソルを結び直す」ことで、その待ちをなくす。
        CGWarpMouseCursorPosition(next)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private static func clamp(_ p: CGPoint, near prev: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &ids, &count)
        let rects = (0..<Int(count)).map { CGDisplayBounds(ids[$0]) }
        if rects.contains(where: { $0.contains(p) }) { return p }
        guard let r = rects.first(where: { $0.contains(prev) }) ?? rects.first else { return p }
        return CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
    }
}
