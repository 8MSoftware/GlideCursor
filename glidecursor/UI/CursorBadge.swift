import AppKit

/// 精密モードに入った・出たことを、カーソルのまわりに短く知らせる。
/// 入るときは、輪がカーソルに向かって縮み、小さな照準の印が少しのあいだ残る。出るときは、輪が広がって消える。
/// クリックを通す、透明なウィンドウに描く(操作のじゃまをしない)。
final class CursorBadge {
    static let shared = CursorBadge()
    private var window: NSWindow?
    private var ring: CAShapeLayer?

    func show(entering: Bool) {
        DispatchQueue.main.async { self.animate(entering: entering) }
    }

    private func animate(entering: Bool) {
        let size: CGFloat = 96
        let p = NSEvent.mouseLocation   // 画面座標(左下が原点)
        let frame = NSRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
        let w = window ?? makeWindow()
        w.setFrame(frame, display: false)
        w.orderFrontRegardless()
        window = w

        let layer = ring ?? CAShapeLayer()
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.path = CGPath(ellipseIn: CGRect(x: size / 2 - 14, y: size / 2 - 14, width: 28, height: 28), transform: nil)
        layer.fillColor = nil
        layer.strokeColor = NSColor.controlAccentColor.cgColor
        layer.lineWidth = 1.5
        if ring == nil { w.contentView?.layer?.addSublayer(layer); ring = layer }

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.window?.orderOut(nil) }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = entering ? 2.2 : 1.0
        scale.toValue = entering ? 1.0 : 2.4
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = entering ? [0, 1, 1, 0] : [1, 0.8, 0]
        fade.keyTimes = entering ? [0, 0.25, 0.75, 1] : [0, 0.4, 1]
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = entering ? 0.7 : 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = 0
        layer.add(group, forKey: "badge")
        CATransaction.commit()
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let v = NSView()
        v.wantsLayer = true
        w.contentView = v
        return w
    }
}
