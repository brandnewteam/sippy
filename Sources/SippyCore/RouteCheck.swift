import Darwin
import Foundation

/// Answers "does a usable network route to this host exist right now?" —
/// the question behind registering only while the PBX is reachable (VPN up).
///
/// A plain reachability check is not enough: while a default route exists,
/// *every* destination technically "has a route". For a private address
/// that's a lie — with the VPN down, packets to 192.168.x.y just leave
/// through the default gateway and die. So the rule is:
///
/// - private/link-local/CGNAT destination → needs a *specific* route (a host
///   or subnet route, e.g. one pushed by the VPN, or the local LAN);
/// - public destination → any route, the default one included;
/// - name that doesn't resolve (VPN-only DNS) → unreachable.
///
/// The routing-table query is an RTM_GET on a PF_ROUTE socket — the same
/// mechanism `route -n get` uses. IPv4 only: VPN-fronted PBXes are, in
/// practice, IPv4.
public enum RouteCheck {
    /// Blocking (getaddrinfo): call off the main thread.
    public static func routeAvailable(toHost host: String) -> Bool {
        guard let address = resolveIPv4(host) else { return false }
        switch matchedRoute(to: address) {
        case .none:
            return false
        case .specific:
            return true
        case .defaultOnly:
            return !isPrivateIPv4(address)
        }
    }

    enum RouteMatch {
        case none
        /// A host or subnet route (VPN-pushed, or a directly connected LAN).
        case specific
        /// Only the catch-all default route matches.
        case defaultOnly
    }

    /// RFC1918, link-local, loopback, and CGNAT (100.64/10, e.g. Tailscale):
    /// ranges the public default route cannot actually deliver to.
    static func isPrivateIPv4(_ addr: in_addr) -> Bool {
        let ip = UInt32(bigEndian: addr.s_addr)
        let ranges: [(base: UInt32, prefix: UInt32)] = [
            (0x0A00_0000, 8),  // 10/8
            (0xAC10_0000, 12),  // 172.16/12
            (0xC0A8_0000, 16),  // 192.168/16
            (0xA9FE_0000, 16),  // 169.254/16 link-local
            (0x7F00_0000, 8),  // 127/8 loopback
            (0x6440_0000, 10),  // 100.64/10 CGNAT
        ]
        return ranges.contains { ip & ~(0xFFFF_FFFF >> $0.prefix) == $0.base }
    }

    static func resolveIPv4(_ host: String) -> in_addr? {
        var literal = in_addr()
        if inet_pton(AF_INET, host, &literal) == 1 { return literal }
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let info = result else { return nil }
        defer { freeaddrinfo(result) }
        var node: UnsafeMutablePointer<addrinfo>? = info
        while let current = node {
            if current.pointee.ai_family == AF_INET, let sa = current.pointee.ai_addr {
                return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            }
            node = current.pointee.ai_next
        }
        return nil
    }

    /// One RTM_GET round-trip: which route would the kernel use for `addr`?
    static func matchedRoute(to addr: in_addr) -> RouteMatch {
        let routeSocket = socket(PF_ROUTE, SOCK_RAW, 0)
        guard routeSocket >= 0 else { return .none }
        defer { close(routeSocket) }

        let headerSize = MemoryLayout<rt_msghdr>.size
        let requestSize = headerSize + MemoryLayout<sockaddr_in>.size
        var request = [UInt8](repeating: 0, count: requestSize)
        let sent = request.withUnsafeMutableBytes { raw -> Bool in
            let header = raw.baseAddress!.assumingMemoryBound(to: rt_msghdr.self)
            header.pointee.rtm_msglen = UInt16(requestSize)
            header.pointee.rtm_version = UInt8(RTM_VERSION)
            header.pointee.rtm_type = UInt8(RTM_GET)
            header.pointee.rtm_addrs = Int32(RTA_DST)
            header.pointee.rtm_pid = getpid()
            header.pointee.rtm_seq = 1
            let dst = (raw.baseAddress! + headerSize).assumingMemoryBound(to: sockaddr_in.self)
            dst.pointee.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            dst.pointee.sin_family = sa_family_t(AF_INET)
            dst.pointee.sin_addr = addr
            return write(routeSocket, raw.baseAddress, requestSize) == requestSize
        }
        // ESRCH from write = no route at all (no default route either).
        guard sent else { return .none }

        var reply = [UInt8](repeating: 0, count: 2048)
        let pid = getpid()
        for _ in 0..<32 {  // skip unrelated routing messages
            let length = read(routeSocket, &reply, reply.count)
            guard length >= headerSize else { return .none }
            let match: RouteMatch? = reply.withUnsafeBytes { raw in
                let header = raw.baseAddress!.assumingMemoryBound(to: rt_msghdr.self)
                guard header.pointee.rtm_type == UInt8(RTM_GET),
                      header.pointee.rtm_pid == pid, header.pointee.rtm_seq == 1
                else { return nil }
                if header.pointee.rtm_flags & RTF_HOST != 0 { return .specific }
                // Walk the sockaddrs (DST, GATEWAY, NETMASK, … in rtm_addrs
                // bit order, each padded to 4 bytes) to find the netmask:
                // any nonzero mask byte means a subnet route; an all-zero or
                // absent mask is the default route.
                var offset = headerSize
                for bit in 0..<8 where header.pointee.rtm_addrs & (1 << bit) != 0 {
                    let saLen = Int(raw[offset])
                    if bit == 2 {  // RTA_NETMASK
                        let maskBytes = raw[(offset + 4)..<(offset + max(saLen, 4))]
                        return maskBytes.contains { $0 != 0 } ? .specific : .defaultOnly
                    }
                    offset += max((saLen + 3) & ~3, 4)
                    if offset >= length { break }
                }
                return .defaultOnly  // no netmask in reply, not a host route
            }
            if let match { return match }
        }
        return .none
    }
}
