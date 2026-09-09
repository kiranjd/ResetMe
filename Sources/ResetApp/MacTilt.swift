import AppKit
import Combine
import IOKit
import IOKit.hid

struct TiltVector {
    let x: Double, y: Double, z: Double
    static func decode(_ bytes: UnsafeBufferPointer<UInt8>) -> TiltVector? {
        guard bytes.count == 22 else { return nil }
        func value(_ offset: Int) -> Double {
            var raw: UInt32 = 0
            for byte in 0..<4 { raw |= UInt32(bytes[offset+byte]) << (byte*8) }
            return Double(Int32(bitPattern: raw))/65536
        }
        let result = TiltVector(x: value(6), y: value(10), z: value(14))
        let magnitude = sqrt(result.x*result.x+result.y*result.y+result.z*result.z)
        guard magnitude > 0.25 && magnitude < 8 else { return nil }
        return result
    }
    var roll: Double { atan2(x, -z) }
    var pitch: Double { atan2(y, sqrt(x*x+z*z)) }
}

/// Opens only Apple's onboard accelerometer. Samples remain in memory, never recorded.
/// The report layout is undocumented; unavailable/stale data never becomes simulated tilt.
final class MacTilt: ObservableObject {
    static let shared = MacTilt()
    @Published private(set) var status = "Sensor paused"
    @Published private(set) var rollDegrees = 0.0
    @Published private(set) var pitchDegrees = 0.0
    @Published private(set) var shakeG = 0.0
    private var sceneActive = false
    func setSceneActive(_ active: Bool) { sceneActive = active; updateEnabled() }
    func updateEnabled() {
        if sceneActive && SceneSettings.shared["macTilt"] > 0.5 { start() }
        else { stop() }
    }
    private var device: IOHIDDevice?
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    private var drivers: [(io_service_t, [String: CFTypeRef])] = []
    private var gravity: TiltVector?
    private var neutral: (Double, Double)?
    private var lastSample = 0.0
    private var lastPublished = 0.0
    private var measuredShock = 0.0
    private var linear = TiltVector(x: 0,y: 0,z: 0)
    var shock: Double { isLive ? measuredShock : 0 }
    var sceneShake: CGPoint? { guard isLive else { return nil }; return CGPoint(x: linear.x,y: -linear.y) }
    var sceneGravity: CGPoint? {
        guard let roll, let pitch else { return nil }
        return CGPoint(x: sin(roll),y: cos(roll)*cos(pitch))
    }
    private var timeout: Timer?
    var isLive: Bool { gravity != nil && ProcessInfo.processInfo.systemUptime-lastSample < 0.5 }
    var roll: Double? { guard isLive, let gravity, let neutral else { return nil }; return atan2(sin(gravity.roll-neutral.0), cos(gravity.roll-neutral.0)) }
    var pitch: Double? { guard isLive, let gravity, let neutral else { return nil }; return gravity.pitch-neutral.1 }
    private static let callback: IOHIDReportCallback = { context, result, _, _, _, bytes, length in
        guard result == kIOReturnSuccess, let context else { return }
        Unmanaged<MacTilt>.fromOpaque(context).takeUnretainedValue().receive(UnsafeBufferPointer(start: bytes, count: length))
    }
    func start() {
        guard device == nil else { return }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDevice"), &iterator) == KERN_SUCCESS else { status = "Tilt sensor unavailable"; return }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            guard matches(service), let candidate = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { continue }
            let opened = IOHIDDeviceOpen(candidate, 0)
            guard opened == kIOReturnSuccess else { status = "Tilt sensor access unavailable"; continue }
            device = candidate
            IOHIDDeviceRegisterInputReportCallback(candidate, buffer, 4096, Self.callback, Unmanaged.passUnretained(self).toOpaque())
            IOHIDDeviceScheduleWithRunLoop(candidate, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            enableReporting()
            status = "Waiting for real tilt readings"
            timeout = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, self.device != nil, !self.isLive else { return }
                self.status = "No fresh tilt readings"
            }
            return
        }
        status = "Tilt sensor unavailable"
    }
    private func matches(_ service: io_service_t) -> Bool {
        let page = IORegistryEntryCreateCFProperty(service, "PrimaryUsagePage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        let usage = IORegistryEntryCreateCFProperty(service, "PrimaryUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        return page == 0xff00 && usage == 3
    }
    private func enableReporting() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            guard matches(service) else { IOObjectRelease(service); continue }
            var old: [String: CFTypeRef] = [:]
            for key in ["SensorPropertyReportingState", "SensorPropertyPowerState", "ReportInterval"] {
                old[key] = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() ?? (0 as CFNumber)
            }
            let enabled = IORegistryEntrySetCFProperty(service, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
            guard enabled == kIOReturnSuccess else { IOObjectRelease(service); continue }
            IORegistryEntrySetCFProperty(service, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(service, "ReportInterval" as CFString, 20000 as CFNumber)
            drivers.append((service, old))
        }
    }
    private func receive(_ bytes: UnsafeBufferPointer<UInt8>) {
        guard let value = TiltVector.decode(bytes) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = lastSample == 0 ? 0.02 : min(0.2, max(0.001, now-lastSample))
        let alpha = 1-exp(-dt/0.12)
        if let old = gravity {
            linear = TiltVector(x: value.x-old.x,y: value.y-old.y,z: value.z-old.z)
            measuredShock = max(sqrt(linear.x*linear.x+linear.y*linear.y+linear.z*linear.z),measuredShock*exp(-dt/0.10))
            let magnitude = sqrt(value.x*value.x+value.y*value.y+value.z*value.z)
            if magnitude > 0.7 && magnitude < 1.3 {
                gravity = TiltVector(x: old.x+(value.x-old.x)*alpha, y: old.y+(value.y-old.y)*alpha, z: old.z+(value.z-old.z)*alpha)
            }
        }
        else { gravity = value }
        lastSample = now
        if neutral == nil { neutral = (gravity!.roll, gravity!.pitch) }
        if now-lastPublished >= 0.1 {
            shakeG = measuredShock
            rollDegrees = (roll ?? 0)*180 / .pi
            pitchDegrees = (pitch ?? 0)*180 / .pi
            if status != "Live Mac tilt" { status = "Live Mac tilt" }
            lastPublished = now
        }
    }
    func calibrate() {
        guard isLive, let gravity else { return }
        neutral = (gravity.roll, gravity.pitch)
        rollDegrees = 0; pitchDegrees = 0
    }
    func stop() {
        timeout?.invalidate(); timeout = nil
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(device, 0)
        }
        device = nil
        for (driver, old) in drivers {
            for (key,value) in old { IORegistryEntrySetCFProperty(driver, key as CFString, value) }
            IOObjectRelease(driver)
        }
        drivers.removeAll()
        gravity = nil; lastSample = 0; measuredShock = 0; linear = TiltVector(x: 0,y: 0,z: 0)
        status = "Sensor paused"; shakeG = 0
    }
    deinit { stop(); buffer.deallocate() }
}
