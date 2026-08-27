import Foundation
import Testing
@testable import SippyCore

@Suite struct DialRequestTests {
    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test func telURL() {
        #expect(DialRequest.parse(url("tel:0612345678")) == .number("0612345678"))
        #expect(DialRequest.parse(url("tel:+39-06-1234-5678")) == .number("+390612345678"))
        #expect(DialRequest.parse(url("tel://0612345678")) == .number("0612345678"))
        #expect(DialRequest.parse(url("tel:%2B390612345678")) == .number("+390612345678"))
    }

    @Test func telParametersAreDropped() {
        #expect(DialRequest.parse(url("tel:0612;phone-context=example.com")) == .number("0612"))
    }

    @Test func calltoURL() {
        #expect(DialRequest.parse(url("callto:0612345678")) == .number("0612345678"))
    }

    @Test func sipURIWithHost() {
        #expect(DialRequest.parse(url("sip:124@pbx.example.com")) == .uri("sip:124@pbx.example.com"))
        #expect(DialRequest.parse(url("sips:bob@example.com;transport=tls"))
            == .uri("sips:bob@example.com;transport=tls"))
    }

    @Test func hostlessSipURIIsANumber() {
        #expect(DialRequest.parse(url("sip:124")) == .number("124"))
    }

    @Test func rejectsGarbage() {
        #expect(DialRequest.parse(url("https://example.com")) == nil)
        #expect(DialRequest.parse(url("tel:abc")) == nil)
    }

    @Test func freeText() {
        #expect(DialRequest.parse(text: " 06 1234 5678 ") == .number("0612345678"))
        #expect(DialRequest.parse(text: "tel:+3906123") == .number("+3906123"))
        #expect(DialRequest.parse(text: "sip:99@pbx.local") == .uri("sip:99@pbx.local"))
        #expect(DialRequest.parse(text: "call me maybe") == nil)
    }
}
