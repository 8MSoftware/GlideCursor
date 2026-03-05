import Foundation
import CoreGraphics
import AppKit

class InertiaEngine {
    static let shared = InertiaEngine()
    
    private var displayLink: CVDisplayLink?
    private var velocity: CGPoint = .zero
    private var isRunningInternal = false
    
    var isRunning: Bool { isRunningInternal }
    
    init() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        if let link = displayLink {
            CVDisplayLinkSetOutputCallback(link, { (displayLink, _, _, _, _, _) -> CVReturn in
                InertiaEngine.shared.update()
                return kCVReturnSuccess
            }, nil)
        }
    }
    
    func start(initialVelocity: CGPoint) {
        stop()
        
        let settings = SettingsManager.shared
        guard settings.isEnabled else { return }
        
        // Apply speed multiplier
        var v = CGPoint(x: initialVelocity.x * settings.speedMultiplier,
                        y: initialVelocity.y * settings.speedMultiplier)
        
        // Cap at max velocity
        let maxV = settings.maxVelocity
        let currentSpeed = sqrt(v.x * v.x + v.y * v.y)
        if currentSpeed > maxV {
            let scale = maxV / currentSpeed
            v.x *= scale
            v.y *= scale
        }
        
        // Minimum start speed check
        if currentSpeed < 2.0 { return }
        
        self.velocity = v
        self.isRunningInternal = true
        
        if let link = displayLink {
            CVDisplayLinkStart(link)
        }
    }
    
    func stop() {
        isRunningInternal = false  // 先にフラグOFF → 進行中フレームの guard で即リターン
        velocity = .zero
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
    }
    
    private func update() {
        guard isRunningInternal else { return }
        
        let settings = SettingsManager.shared
        
        // Apply friction
        velocity.x *= settings.friction
        velocity.y *= settings.friction
        
        // Stop if too slow
        if abs(velocity.x) < 0.5 && abs(velocity.y) < 0.5 {
            stop()
            return
        }
        
        // Move cursor
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        var newPos = CGPoint(x: currentPos.x + velocity.x, y: currentPos.y + velocity.y)
        
        // Multi-monitor Bounds Check
        var displayCount: UInt32 = 0
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &activeDisplays, &displayCount)
        
        let screens = (0..<Int(displayCount)).map { CGDisplayBounds(activeDisplays[$0]) }
        
        // Check if newPos is valid in ANY screen
        let isValid = screens.contains { $0.contains(newPos) }
        
        if !isValid {
            // If not valid, we need to clamp to the screen we are currently on (or closest)
            // Find the screen containing currentPos
            if let currentScreen = screens.first(where: { $0.contains(currentPos) }) {
                
                // Trackball-like behavior: Slide along edges
                var stoppedX = false
                var stoppedY = false
                
                if newPos.x <= currentScreen.minX {
                    newPos.x = currentScreen.minX
                    stoppedX = true
                } else if newPos.x >= currentScreen.maxX {
                    newPos.x = currentScreen.maxX
                    stoppedX = true
                }
                
                if newPos.y <= currentScreen.minY {
                    newPos.y = currentScreen.minY
                    stoppedY = true
                } else if newPos.y >= currentScreen.maxY {
                    newPos.y = currentScreen.maxY
                    stoppedY = true
                }
                
                // If hit wall, zero out that velocity component
                if stoppedX { velocity.x = 0 }
                if stoppedY { velocity.y = 0 }
                
                if stoppedX && stoppedY {
                    stop()
                }
            } else {
                // Fallback if current pos is somehow invalid (rare)
                stop()
            }
        }
        
        if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newPos, mouseButton: .left) {
            // Tag the event so EventTapManager knows it's ours
            moveEvent.setIntegerValueField(.eventSourceUserData, value: 555)
            moveEvent.post(tap: .cghidEventTap)
        }
    }
}
