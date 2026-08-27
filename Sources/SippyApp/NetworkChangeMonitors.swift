import Darwin
import Dispatch
import Foundation
import SystemConfiguration

/// Fires on every routing-table mutation: the kernel broadcasts each
/// RTM_ADD / RTM_DELETE / RTM_CHANGE to PF_ROUTE listeners. This is what
/// makes route gating react instantly when a VPN pushes or withdraws routes
/// on an *existing* tunnel interface — a case NWPathMonitor, which watches
/// interfaces rather than routes, can sleep through.
final class RouteTableMonitor: @unchecked Sendable {
    private let source: DispatchSourceRead

    init?(onChange: @escaping @Sendable () -> Void) {
        let fd = socket(PF_ROUTE, SOCK_RAW, 0)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeReadSource(
            fileDescriptor: fd, queue: DispatchQueue(label: "sippy.routetable"))
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let length = read(fd, &buffer, buffer.count)
            guard length >= MemoryLayout<rt_msghdr>.size else { return }
            let type = buffer.withUnsafeBytes {
                Int32($0.baseAddress!.assumingMemoryBound(to: rt_msghdr.self).pointee.rtm_type)
            }
            if type == RTM_ADD || type == RTM_DELETE || type == RTM_CHANGE {
                onChange()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit { source.cancel() }
}

/// Fires when the system's DNS resolver configuration changes
/// (State:/Network/Global/DNS in the SystemConfiguration dynamic store).
/// Needed when the SIP domain is a hostname only the VPN's DNS can resolve:
/// on VPN-up the route can exist before the resolvers do, so a probe that
/// failed on DNS gets re-run once the resolvers land.
final class DNSConfigMonitor {
    private var store: SCDynamicStore?
    private let onChange: @Sendable () -> Void

    init?(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        var context = SCDynamicStoreContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            Unmanaged<DNSConfigMonitor>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let store = SCDynamicStoreCreate(nil, "Sippy" as CFString, callback, &context),
              SCDynamicStoreSetNotificationKeys(
                  store, ["State:/Network/Global/DNS" as CFString] as CFArray, nil),
              SCDynamicStoreSetDispatchQueue(store, DispatchQueue(label: "sippy.dnsconfig"))
        else { return nil }
        self.store = store
    }

    deinit {
        if let store { SCDynamicStoreSetDispatchQueue(store, nil) }
    }
}
