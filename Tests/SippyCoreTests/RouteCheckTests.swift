import Foundation
import Testing
@testable import SippyCore

@Suite struct RouteCheckTests {
    private func addr(_ s: String) -> in_addr {
        var a = in_addr()
        #expect(inet_pton(AF_INET, s, &a) == 1)
        return a
    }

    @Test func classifiesPrivateRanges() {
        #expect(RouteCheck.isPrivateIPv4(addr("10.8.0.1")))
        #expect(RouteCheck.isPrivateIPv4(addr("172.16.0.1")))
        #expect(RouteCheck.isPrivateIPv4(addr("172.31.255.255")))
        #expect(RouteCheck.isPrivateIPv4(addr("192.168.1.1")))
        #expect(RouteCheck.isPrivateIPv4(addr("169.254.9.9")))
        #expect(RouteCheck.isPrivateIPv4(addr("127.0.0.1")))
        #expect(RouteCheck.isPrivateIPv4(addr("100.64.0.1")))
        #expect(!RouteCheck.isPrivateIPv4(addr("172.32.0.1")))
        #expect(!RouteCheck.isPrivateIPv4(addr("8.8.8.8")))
        #expect(!RouteCheck.isPrivateIPv4(addr("193.0.0.1")))
    }

    @Test func resolvesLiteralsWithoutDNS() {
        let resolved = RouteCheck.resolveIPv4("192.0.2.7")
        #expect(resolved?.s_addr == addr("192.0.2.7").s_addr)
        #expect(RouteCheck.resolveIPv4("definitely-not-a-real-host.invalid") == nil)
    }

    /// Loopback always has a specific (127/8) route, on every machine.
    @Test func loopbackIsSpecificallyRouted() {
        #expect(RouteCheck.matchedRoute(to: addr("127.0.0.1")) == .specific)
        #expect(RouteCheck.routeAvailable(toHost: "127.0.0.1"))
    }
}
