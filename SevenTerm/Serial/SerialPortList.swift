import Foundation
import IOKit
import IOKit.serial
import Observation
import SevenTermCore

/// A serial port macOS can see right now.
struct SerialPortInfo: Identifiable, Hashable, Sendable {
    var id: String { path }
    /// The /dev/cu.* path. Never /dev/tty.*, which waits for a carrier
    /// signal that console cables don't send.
    let path: String
    let vendor: String?
    let product: String?
    let serialNumber: String?
    let vendorID: Int?
    let productID: Int?

    /// "cu.usbserial-A10K3B7" without the "cu." prefix.
    var shortName: String {
        let name = (path as NSString).lastPathComponent
        return name.hasPrefix("cu.") ? String(name.dropFirst(3)) : name
    }

    /// "FTDI FT232R USB UART (A10K3B7)", or the short name when the adapter
    /// doesn't describe itself.
    var displayName: String {
        let parts = [vendor, product].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return shortName }
        // Some adapters repeat the vendor in the product name.
        var label = parts.count == 2 && parts[1].localizedCaseInsensitiveContains(parts[0]) ? parts[1] : parts.joined(separator: " ")
        if let serialNumber, !serialNumber.isEmpty { label += " (\(serialNumber))" }
        return label
    }
}

/// The serial ports macOS sees, kept current as adapters are plugged in
/// and out. Uses IOKit's registry and its match notifications.
@MainActor
@Observable
final class SerialPortList {
    private(set) var ports: [SerialPortInfo] = []

    @ObservationIgnored private var notificationPort: IONotificationPortRef?
    @ObservationIgnored private var iterators: [io_iterator_t] = []
    @ObservationIgnored private var pendingRefresh = false

    /// Built into every Mac; never a console.
    nonisolated private static let hidden = ["Bluetooth-Incoming-Port", "debug-console", "wlan-debug"]

    init() {
        refresh()
        watch()
    }

    func refresh() {
        ports = Self.scan()
    }

    /// Several notifications arrive per plug or unplug, and the /dev node
    /// can trail the registry slightly, so refresh once, shortly after.
    fileprivate func scheduleRefresh() {
        guard !pendingRefresh else { return }
        pendingRefresh = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingRefresh = false
                self?.refresh()
            }
        }
    }

    /// Where a saved serial entry's adapter is now. The saved path if it's
    /// connected; otherwise the adapter with the same USB serial number;
    /// otherwise the only connected adapter of the same make and model
    /// (adapters without serial numbers are named after their USB socket).
    /// Falls back to the saved path, which then fails with "isn't connected".
    nonisolated static func resolve(savedPath: String, details: SerialHostDetails) -> String {
        let ports = scan()
        if ports.contains(where: { $0.path == savedPath }) { return savedPath }
        if let serial = details.usbSerialNumber, !serial.isEmpty,
           let match = ports.first(where: { $0.serialNumber == serial }) {
            return match.path
        }
        if let vendor = details.vendorID, let product = details.productID {
            let same = ports.filter { $0.vendorID == vendor && $0.productID == product }
            if same.count == 1 { return same[0].path }
        }
        return savedPath
    }

    // MARK: IOKit

    nonisolated static func scan() -> [SerialPortInfo] {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var ports: [SerialPortInfo] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path = property(service, kIOCalloutDeviceKey) as? String,
                  !hidden.contains(where: { path.contains($0) })
            else { continue }
            ports.append(SerialPortInfo(
                path: path,
                vendor: usbProperty(service, ["USB Vendor Name", "kUSBVendorString"]) as? String,
                product: usbProperty(service, ["USB Product Name", "kUSBProductString"]) as? String,
                serialNumber: usbProperty(service, ["USB Serial Number", "kUSBSerialNumberString"]) as? String,
                vendorID: (usbProperty(service, ["idVendor"]) as? NSNumber)?.intValue,
                productID: (usbProperty(service, ["idProduct"]) as? NSNumber)?.intValue
            ))
        }
        return ports.sorted { $0.path < $1.path }
    }

    nonisolated private static func property(_ service: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// USB details live on the USB device above the serial port in the
    /// registry, so search upward.
    nonisolated private static func usbProperty(_ service: io_object_t, _ keys: [String]) -> Any? {
        for key in keys {
            if let value = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            ) {
                return value
            }
        }
        return nil
    }

    /// Asks IOKit to tell us when a serial port appears or goes away.
    private func watch() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            // Drain the iterator; IOKit only re-arms it once it's empty.
            while case let service = IOIteratorNext(iterator), service != 0 {
                IOObjectRelease(service)
            }
            guard let context else { return }
            let list = Unmanaged<SerialPortList>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { list.scheduleRefresh() }
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { continue }
            var iterator: io_iterator_t = 0
            if IOServiceAddMatchingNotification(port, type, matching, callback, context, &iterator) == KERN_SUCCESS {
                while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
                iterators.append(iterator)
            }
        }
    }
}
