import Foundation
import IOKit.hid

/// A decoded HID event from the roBa.
enum HIDEvent {
    /// Keyboard (page 0x07, incl. modifiers 0xE0–0xE7 and LANG1/2) or
    /// consumer (page 0x0C) usage transition.
    case key(page: UInt32, usage: UInt32, down: Bool)
    /// Mouse button (page 0x09), number 1-based.
    case button(number: Int, down: Bool)
    /// Trackball movement (coalesced; deltas not needed, only the fact).
    case pointerMotion
    /// Wheel / AC Pan scrolling (coalesced).
    case scroll
    /// roBa appeared / disappeared.
    case connection(Bool)
}

/// Passively listens to the roBa's raw HID reports via IOHIDManager on a
/// dedicated CFRunLoop thread. Requires the Input Monitoring TCC grant —
/// which sticks to the code-signing identity, hence the self-signed cert.
final class HIDMonitor {
    enum Access {
        case granted, denied, undetermined

        static func current() -> Access {
            switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
            case kIOHIDAccessTypeGranted: .granted
            case kIOHIDAccessTypeDenied: .denied
            default: .undetermined
            }
        }
    }

    /// Called on the HID thread; the receiver hops to the main actor.
    var onEvent: ((HIDEvent) -> Void)?
    /// Called on the HID thread if IOHIDManagerOpen fails (TCC denied etc.).
    var onOpenFailure: ((IOReturn) -> Void)?

    /// Product string that identifies the keyboard among ZMK devices
    /// (VID/PID are ZMK defaults shared by every stock ZMK board).
    private let productName = "roBa"

    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var manager: IOHIDManager?

    // All mutable state below is confined to the HID thread.
    private var acceptedDevices = Set<IOHIDDevice>()
    private var lastMotionForward: CFAbsoluteTime = 0
    private var lastScrollForward: CFAbsoluteTime = 0
    private var lastConsumerArrayUsage: UInt32 = 0

    /// Coalescing window for high-rate relative events (motion floods at
    /// sensor rate; inference only needs "still moving" ticks).
    private let coalesceInterval: CFAbsoluteTime = 0.05

    @discardableResult
    static func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    func start() {
        guard thread == nil else { return }
        let thread = Thread { [weak self] in self?.threadMain() }
        thread.name = "HIDMonitor"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    func stop() {
        if let runLoop { CFRunLoopStop(runLoop) }
        thread = nil
    }

    private func threadMain() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        self.runLoop = CFRunLoopGetCurrent()

        // Cast wide (any ZMK-default VID/PID, or anything named right) and
        // filter precisely by product string in the matching callback.
        let matching: [[String: Any]] = [
            [kIOHIDProductKey as String: productName],
            [kIOHIDVendorIDKey as String: 0x1D50, kIOHIDProductIDKey as String: 0x615E],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context!).takeUnretainedValue()
            monitor.deviceMatched(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context!).takeUnretainedValue()
            monitor.deviceRemoved(device)
        }, context)

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context!).takeUnretainedValue()
            monitor.handle(value: value)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            onOpenFailure?(result)
        }

        CFRunLoopRun()

        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        self.runLoop = nil
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        guard product == productName else { return }
        let wasEmpty = acceptedDevices.isEmpty
        acceptedDevices.insert(device)
        if wasEmpty { onEvent?(.connection(true)) }
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        guard acceptedDevices.remove(device) != nil else { return }
        if acceptedDevices.isEmpty { onEvent?(.connection(false)) }
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard acceptedDevices.contains(device) else { return }

        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        switch page {
        case 0x07:
            // NKRO bitmap: one element per usage, value 1/0. Skip
            // ErrorRollOver etc. (usages 0–3) and out-of-range noise.
            guard usage >= 0x04, usage <= 0xE7 else { return }
            onEvent?(.key(page: page, usage: usage, down: intValue != 0))
        case 0x09:
            guard usage >= 1, usage <= 5 else { return }
            onEvent?(.button(number: Int(usage), down: intValue != 0))
        case 0x01:
            switch usage {
            case 0x30, 0x31:    // X / Y relative deltas
                guard intValue != 0 else { return }
                forwardCoalesced(&lastMotionForward, .pointerMotion)
            case 0x38:          // vertical wheel
                guard intValue != 0 else { return }
                forwardCoalesced(&lastScrollForward, .scroll)
            default:
                return
            }
        case 0x0C:
            if usage == 0x238 { // AC Pan: relative horizontal scroll (mouse report)
                guard intValue != 0 else { return }
                forwardCoalesced(&lastScrollForward, .scroll)
                return
            }
            // Consumer keys: ZMK may expose them per-usage (variable) or as
            // an array slot whose *value* is the usage. Handle both.
            if usage > 1 {
                onEvent?(.key(page: page, usage: usage, down: intValue != 0))
            } else {
                let pressed = UInt32(truncatingIfNeeded: intValue)
                if pressed != 0 {
                    lastConsumerArrayUsage = pressed
                    onEvent?(.key(page: page, usage: pressed, down: true))
                } else if lastConsumerArrayUsage != 0 {
                    onEvent?(.key(page: page, usage: lastConsumerArrayUsage, down: false))
                    lastConsumerArrayUsage = 0
                }
            }
        default:
            return
        }
    }

    private func forwardCoalesced(_ last: inout CFAbsoluteTime, _ event: HIDEvent) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - last >= coalesceInterval else { return }
        last = now
        onEvent?(event)
    }
}

/// CLI: print decoded roBa HID events until Ctrl-C.
///   packaged app: /Applications/RoBaHUD.app/Contents/MacOS/RoBaHUD --hid-dump
///   (via swift run, the TCC grant belongs to the terminal app instead)
enum HIDDump {
    static func run() -> Int32 {
        print("access: \(HIDMonitor.Access.current())")
        if HIDMonitor.Access.current() != .granted {
            print("requesting Input Monitoring access…")
            HIDMonitor.requestAccess()
        }
        let monitor = HIDMonitor()
        let start = Date()
        monitor.onEvent = { event in
            let t = String(format: "%8.3f", Date().timeIntervalSince(start))
            switch event {
            case .key(let page, let usage, let down):
                print("\(t)  key   page=0x\(String(page, radix: 16)) usage=0x\(String(usage, radix: 16)) \(down ? "DOWN" : "up")")
            case .button(let n, let down):
                print("\(t)  btn   MB\(n) \(down ? "DOWN" : "up")")
            case .pointerMotion:
                print("\(t)  move")
            case .scroll:
                print("\(t)  scroll")
            case .connection(let up):
                print("\(t)  \(up ? "CONNECTED" : "DISCONNECTED")")
            }
        }
        monitor.onOpenFailure = { code in
            print("IOHIDManagerOpen failed: 0x\(String(UInt32(bitPattern: code), radix: 16)) — Input Monitoring 権限を確認してください")
        }
        monitor.start()
        CFRunLoopRun()
        return 0
    }
}
