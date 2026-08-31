import Testing
@testable import SippyCore

@Suite struct CallFailureTests {
    @Test func sipStatusLine() {
        #expect(CallFailureFormatter.describe(
            stackMessage: "Temporarily unavailable",
            proto: "SIP", code: 480, phrase: "Temporarily Unavailable")
            == "SIP 480 Temporarily Unavailable")
    }

    @Test func fallsBackToStackMessageWithoutCode() {
        #expect(CallFailureFormatter.describe(
            stackMessage: "Transport error", proto: nil, code: 0, phrase: nil)
            == "Transport error")
        #expect(CallFailureFormatter.describe(
            stackMessage: "", proto: nil, code: 0, phrase: nil)
            == "Call failed.")
    }

    @Test func missingPhraseUsesStackMessage() {
        #expect(CallFailureFormatter.describe(
            stackMessage: "Busy here", proto: nil, code: 486, phrase: nil)
            == "SIP 486 Busy here")
    }

    @Test func reasonHeaderIsAppended() {
        #expect(CallFailureFormatter.describe(
            stackMessage: "Temporarily unavailable",
            proto: "SIP", code: 480, phrase: "Temporarily Unavailable",
            reasonProtocol: "Q.850", reasonCode: 21, reasonPhrase: "Call rejected")
            == "SIP 480 Temporarily Unavailable — Reason: Q.850 cause 21 Call rejected")
    }

    @Test func mirroredReasonHeaderIsDropped() {
        // Kalliope-style "Reason: SIP;cause=480" adds nothing over the status line.
        #expect(CallFailureFormatter.describe(
            stackMessage: "",
            proto: "SIP", code: 480, phrase: "Temporarily Unavailable",
            reasonProtocol: "SIP", reasonCode: 480, reasonPhrase: "Temporarily Unavailable")
            == "SIP 480 Temporarily Unavailable")
        #expect(CallFailureFormatter.describe(
            stackMessage: "",
            proto: "SIP", code: 480, phrase: "Temporarily Unavailable",
            reasonProtocol: nil, reasonCode: 480, reasonPhrase: nil)
            == "SIP 480 Temporarily Unavailable")
    }

    @Test func reasonWithDifferentPhraseIsKept() {
        #expect(CallFailureFormatter.describe(
            stackMessage: "",
            proto: "SIP", code: 480, phrase: "Temporarily Unavailable",
            reasonProtocol: "SIP", reasonCode: 480, reasonPhrase: "Do Not Disturb")
            == "SIP 480 Temporarily Unavailable — Reason: SIP cause 480 Do Not Disturb")
    }
}
