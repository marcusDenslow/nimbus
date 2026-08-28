import IOKit
import IOKit.hid
import os

/// Direct rumble for the DualSense's classic motors over raw HID output reports.
///
/// macOS exposes DualSense haptics only through CoreHaptics, which drives the pad's audio-haptic
/// path — present over USB audio, absent over Bluetooth — so in practice the grips stay dead. The
/// old ERM-style rumble motors are still reachable by writing HID output reports directly (report
/// `0x02` on USB, `0x31` + CRC-32 on Bluetooth), which is what this does. It opens the device
/// non-exclusively, so the GameController framework keeps receiving input at the same time
/// (verified: SetReport succeeds while GCController holds the pad).
@MainActor
final class DualSenseRumble {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private var transport = ""
    private var reportLen = 48
    private var lastLeft: UInt8 = 0
    private var lastRight: UInt8 = 0
    private let log = Logger(subsystem: "com.nimbus", category: "rumble")

    private static let vendorSony = 0x054C
    private static let products = [0x0CE6, 0x0DF2]   // DualSense, DualSense Edge

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches = Self.products.map {
            [kIOHIDVendorIDKey: Self.vendorSony, kIOHIDProductIDKey: $0] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Grab the first matching pad the manager knows about, if we don't already hold one. Cheap to
    /// call every frame — it no-ops once a device is held, and re-resolves after a disconnect.
    private func resolve() {
        guard device == nil else { return }
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let dev = set.first else { return }
        IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        device = dev
        transport = IOHIDDeviceGetProperty(dev, kIOHIDTransportKey as CFString) as? String ?? ""
        reportLen = IOHIDDeviceGetProperty(dev, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 48
        log.notice("rumble ready transport=\(self.transport, privacy: .public) len=\(self.reportLen)")
    }

    /// Set both motors, 0…1. `left` is the strong low-frequency motor, `right` the weak high one.
    /// Redundant writes (same bytes as last time) are dropped so a steady level doesn't spam SetReport.
    func set(left: Float, right: Float) {
        resolve()
        let l = UInt8(max(0, min(1, left)) * 255)
        let r = UInt8(max(0, min(1, right)) * 255)
        guard l != lastLeft || r != lastRight else { return }
        lastLeft = l
        lastRight = r
        send(left: l, right: r)
    }

    func stop() { set(left: 0, right: 0) }

    private func send(left: UInt8, right: UInt8) {
        guard let device else { return }
        var report = [UInt8](repeating: 0, count: reportLen)
        let reportID: CFIndex

        if transport == "Bluetooth" {
            // 0x31 report. macOS strips the leading report id from the buffer, so the on-wire tag
            // byte lands at [0]; flags + motors follow; the trailing 4 bytes are a CRC-32 taken over
            // the 0xA2 seed, the report id, and everything up to the checksum.
            reportID = 0x31
            report[0] = 0x02              // feature tag
            report[1] = 0x03              // valid_flag0: COMPATIBLE_VIBRATION | HAPTICS_SELECT
            report[2] = 0x00              // valid_flag1
            report[3] = right
            report[4] = left
            var crcInput: [UInt8] = [0xA2, 0x31]
            crcInput.append(contentsOf: report[0..<(reportLen - 4)])
            let crc = Self.crc32(crcInput)
            report[reportLen - 4] = UInt8(crc & 0xFF)
            report[reportLen - 3] = UInt8((crc >> 8) & 0xFF)
            report[reportLen - 2] = UInt8((crc >> 16) & 0xFF)
            report[reportLen - 1] = UInt8((crc >> 24) & 0xFF)
        } else {
            // USB 0x02 report: valid flags then the two motor amplitudes. No checksum.
            reportID = 0x02
            report[0] = 0x03              // valid_flag0: COMPATIBLE_VIBRATION | HAPTICS_SELECT
            report[1] = 0x00              // valid_flag1
            report[2] = right
            report[3] = left
        }

        let res = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID, report, report.count)
        if res != kIOReturnSuccess {
            log.error("SetReport failed 0x\(String(res, radix: 16, uppercase: true), privacy: .public) — dropping device")
            self.device = nil             // re-resolve on the next call (likely unplugged)
        }
    }

    /// Standard zlib CRC-32 (reflected, poly 0xEDB88320), for the Bluetooth report checksum.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in bytes {
            crc ^= UInt32(b)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
        }
        return ~crc
    }
}
