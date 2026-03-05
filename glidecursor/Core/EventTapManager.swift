import Foundation
import CoreGraphics
import AppKit
import Combine

extension CGEventField {
    static let mouseEventSourceDeviceID = CGEventField(rawValue: 101)!
}

struct DeviceInfo: Codable, Hashable {
    let id: Int
    let subtype: Int
}

class EventTapManager: ObservableObject {
    static let shared = EventTapManager()
    
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdogTimer: Timer?
    
    // Device Detection
    @Published var isDetectingDevice = false
    @Published var lastSeenDevice: DeviceInfo?
    @Published var knownDevices: Set<DeviceInfo> = []
    
    // Flick Detection
    private var lastEventTime: TimeInterval = 0
    private var lastLocation: CGPoint = .zero
    private var currentVelocity: CGPoint = .zero
    
    // Velocity History for Smoothing (Averaging)
    private var velocityHistory: [CGPoint] = []
    private let historySize = 5

    // [Experimental] グライド停止タップのクリック抑止
    private var stopTapPending = false
    private var stopTapTime: TimeInterval = 0
    
    func start() {
        guard machPort == nil else { return }
        
        let eventMask = (1 << CGEventType.mouseMoved.rawValue) |
                        (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.leftMouseUp.rawValue) |   // クリック抑止のペア確保
                        (1 << CGEventType.rightMouseDown.rawValue) |
                        (1 << CGEventType.scrollWheel.rawValue) |
                        (1 << CGEventType.leftMouseDragged.rawValue) |
                        (1 << CGEventType.rightMouseDragged.rawValue) |
                        (1 << CGEventType.otherMouseDragged.rawValue) |
                        (1 << CGEventType.tabletProximity.rawValue)
        
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: CGEventMask(eventMask),
                                           callback: eventTapCallback,
                                           userInfo: nil) else {
            print("Failed to create event tap")
            return
        }
        
        self.machPort = port
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        
        // Start Watchdog for Flick detection (finger lift)
        DispatchQueue.main.async {
            self.watchdogTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
                self?.checkFlick()
            }
        }
    }
    
    func stop() {
        guard let port = machPort, let source = runLoopSource else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        self.machPort = nil
        self.runLoopSource = nil
        
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }
    
    func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let settings = SettingsManager.shared
        
        // Device Detection Mode
        if isDetectingDevice {
            if type == .mouseMoved {
                let deviceID = event.getIntegerValueField(.mouseEventSourceDeviceID)
                let subtype = event.getIntegerValueField(.mouseEventSubtype)
                if deviceID != 0 {
                    let info = DeviceInfo(id: Int(deviceID), subtype: Int(subtype))
                    DispatchQueue.main.async {
                        settings.toggleDevice(info)
                        self.isDetectingDevice = false
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        
        // [Experimental] グライド停止タップのクリック抑止
        // leftMouseDown: グライド中なら stop して mouseDown を抑止、対応 mouseUp も抑止予約
        if type == .leftMouseDown && InertiaEngine.shared.isRunning && settings.suppressClickOnStop {
            InertiaEngine.shared.stop()
            stopTapPending = true
            stopTapTime = Date().timeIntervalSince1970
            return nil
        }
        // leftMouseUp: stopTapPending が true なら mouseDown と対を揃えて抑止
        // タイムアウト保険: 300ms 以上経過していたら mouseUp は通す（孤立を最小化）
        if type == .leftMouseUp && stopTapPending {
            stopTapPending = false
            let elapsed = Date().timeIntervalSince1970 - stopTapTime
            if elapsed < 0.3 {
                return nil
            }
            // 300ms 超過 = 異常ケース。mouseUp は通してUIの整合を保つ
        }

        // Trackpad タッチ即停止:
        // scrollWheel の mayBegin (32) は「指がパッドに触れた瞬間」に発火する。
        // これにより、スクロールデルタが発生する前にグライドを停止できる。
        // began (1) も同様に確実に拾う（念のため）。
        if type == .scrollWheel && InertiaEngine.shared.isRunning {
            // rawValue 132 = kCGScrollWheelEventScrollPhase (SDK 定数と名前が衝突するため直接指定)
            // 32 = NSEvent.Phase.mayBegin, 1 = NSEvent.Phase.began
            let phase: Int64 = event.getIntegerValueField(CGEventField(rawValue: 132)!)
            if phase == 32 || phase == 1 {
                InertiaEngine.shared.stop()
                return Unmanaged.passUnretained(event)
            }
        }

        // Stop Inertia on interaction
        if type == .leftMouseDown || type == .rightMouseDown || type == .scrollWheel ||
           type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged ||
           type == .tabletProximity {
            InertiaEngine.shared.stop()
            return Unmanaged.passUnretained(event)
        }
        
        if type == .mouseMoved {
            // Check Device ID & Subtype
            let deviceID = event.getIntegerValueField(.mouseEventSourceDeviceID)
            let subtype = event.getIntegerValueField(.mouseEventSubtype)
            
            // Update Last Seen Device for UI
            if deviceID != 0 {
                let info = DeviceInfo(id: Int(deviceID), subtype: Int(subtype))
                if info != lastSeenDevice {
                    DispatchQueue.main.async {
                        self.lastSeenDevice = info
                        if !self.knownDevices.contains(info) {
                            self.knownDevices.insert(info)
                        }
                    }
                }
            }
            
            // Check for Injected Event (Magic Number) to prevent self-stopping
            let userData = event.getIntegerValueField(.eventSourceUserData)
            if userData == 555 { // Magic number from InertiaEngine
                return Unmanaged.passUnretained(event)
            }
            
            // Stop inertia if user moves mouse (ANY device)
            if InertiaEngine.shared.isRunning {
                InertiaEngine.shared.stop()
            }
            
            // DISABLE FILTERING FOR STABILITY
            // let currentInfo = DeviceInfo(id: Int(deviceID), subtype: Int(subtype))
            // if !settings.enabledDevices.contains(currentInfo) {
            //    return Unmanaged.passUnretained(event)
            // }
            
            // Calculate Velocity
            let location = event.location
            let time = Date().timeIntervalSince1970
            
            if lastEventTime > 0 {
                let dt = time - lastEventTime
                if dt > 0 && dt < 0.1 {
                    let dx = location.x - lastLocation.x
                    let dy = location.y - lastLocation.y
                    let v = CGPoint(x: dx, y: dy)
                    
                    // Add to history
                    velocityHistory.append(v)
                    if velocityHistory.count > historySize {
                        velocityHistory.removeFirst()
                    }
                    
                    currentVelocity = v // Keep current for immediate check, but use average for start
                } else {
                    currentVelocity = .zero
                    velocityHistory.removeAll()
                }
            }
            
            lastEventTime = time
            lastLocation = location
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func checkFlick() {
        let now = Date().timeIntervalSince1970
        let timeSinceLastEvent = now - lastEventTime
        
        // Thresholds
        let timeThreshold = 0.05 // Stricter time threshold
        let velocityThreshold: CGFloat = CGFloat(SettingsManager.shared.flickSensitivity)
        
        if timeSinceLastEvent < timeThreshold && timeSinceLastEvent > 0.005 {
            if !InertiaEngine.shared.isRunning {
                // Calculate Average Velocity
                if !velocityHistory.isEmpty {
                    let avgX = velocityHistory.map { $0.x }.reduce(0, +) / CGFloat(velocityHistory.count)
                    let avgY = velocityHistory.map { $0.y }.reduce(0, +) / CGFloat(velocityHistory.count)
                    let avgVelocity = CGPoint(x: avgX, y: avgY)
                    
                    if abs(avgVelocity.x) > velocityThreshold || abs(avgVelocity.y) > velocityThreshold {
                        InertiaEngine.shared.start(initialVelocity: avgVelocity)
                        currentVelocity = .zero
                        velocityHistory.removeAll()
                    }
                }
            }
        } else if timeSinceLastEvent > timeThreshold {
            currentVelocity = .zero
            velocityHistory.removeAll()
        }
    }
}

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    return EventTapManager.shared.handleEvent(type: type, event: event)
}
