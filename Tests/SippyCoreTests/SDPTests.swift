import Testing
@testable import SippyCore

@Suite struct SDPTests {
    // Trimmed from a real Kalliope 200 OK.
    private let answer = """
        v=0
        o=- 1755 1755 IN IP4 127.0.0.1
        s=Kalliope
        c=IN IP4 127.0.0.1
        t=0 0
        m=audio 10024 RTP/AVP 8 18 101
        a=rtpmap:8 PCMA/8000
        a=rtpmap:18 G729/8000
        a=fmtp:18 annexb=no
        a=rtpmap:101 telephone-event/8000
        a=fmtp:101 0-16
        a=ptime:20
        a=sendrecv
        """

    @Test func parsesAnswer() throws {
        let sdp = try #require(SDPAudioDescription.parse(answer))
        #expect(sdp.codecs.map(\.payloadNumber) == [8, 18, 101])
        #expect(sdp.codecs[0].name == "PCMA/8000")
        #expect(sdp.codecs[1].name == "G729/8000")
        #expect(sdp.codecs[1].fmtp == "annexb=no")
    }

    @Test func staticPayloadsNeedNoRtpmap() throws {
        let sdp = try #require(SDPAudioDescription.parse("m=audio 7078 RTP/AVP 0 8 9 18"))
        #expect(sdp.codecs.map(\.name) == ["PCMU/8000", "PCMA/8000", "G722/8000", "G729/8000"])
    }

    @Test func unknownDynamicPayloadIsLabelled() throws {
        let sdp = try #require(SDPAudioDescription.parse("m=audio 7078 RTP/AVP 96"))
        #expect(sdp.codecs[0].name == "dynamic(96)")
    }

    @Test func stopsAtNextMediaSection() throws {
        let multi = """
            m=audio 7078 RTP/AVP 0
            a=rtpmap:0 PCMU/8000
            m=video 9078 RTP/AVP 97
            a=rtpmap:97 H264/90000
            """
        let sdp = try #require(SDPAudioDescription.parse(multi))
        #expect(sdp.codecs.count == 1)
        #expect(sdp.codecs[0].name == "PCMU/8000")
    }

    @Test func noAudioSectionReturnsNil() {
        #expect(SDPAudioDescription.parse("m=video 9078 RTP/AVP 97") == nil)
        #expect(SDPAudioDescription.parse("just some log text") == nil)
    }
}

@Suite struct SIPTraceParserTests {
    private let sentLog = """
        channel [0x7fd]: message sent to [UDP://127.0.0.1:5060], size: [431] bytes
        INVITE sip:0600@127.0.0.1 SIP/2.0
        Via: SIP/2.0/UDP 127.0.0.1:5060
        Content-Type: application/sdp

        v=0
        m=audio 7078 RTP/AVP 18
        a=rtpmap:18 G729/8000
        """

    @Test func parsesSentRequestWithSDP() throws {
        let entry = try #require(SIPTraceParser.parse(logMessage: sentLog))
        #expect(entry.direction == .sent)
        #expect(entry.isRequest)
        #expect(entry.label == "INVITE")
        #expect(entry.firstLine == "INVITE sip:0600@127.0.0.1 SIP/2.0")
        #expect(entry.sdp?.codecs.first?.name == "G729/8000")
    }

    @Test func parsesReceivedResponse() throws {
        let log = """
            channel [0x7fd]: message received from [UDP://127.0.0.1:5060], size: [312] bytes
            SIP/2.0 401 Unauthorized
            Via: SIP/2.0/UDP 127.0.0.1:5060
            """
        let entry = try #require(SIPTraceParser.parse(logMessage: log))
        #expect(entry.direction == .received)
        #expect(!entry.isRequest)
        #expect(entry.label == "401 Unauthorized")
        #expect(entry.sdp == nil)
    }

    @Test func ignoresNonSIPLogLines() {
        #expect(SIPTraceParser.parse(logMessage: "Garbage collector freed 3 objects") == nil)
        // Mentions a method but is not a start-line.
        #expect(SIPTraceParser.parse(logMessage: "channel: about to send INVITE later") == nil)
    }

    @Test func startLineDetection() {
        #expect(SIPTraceParser.isStartLine("SIP/2.0 200 OK"))
        #expect(SIPTraceParser.isStartLine("REGISTER sip:pbx SIP/2.0"))
        #expect(!SIPTraceParser.isStartLine("Via: SIP/2.0/UDP host"))
        #expect(!SIPTraceParser.isStartLine("INVITE somebody to the party"))
    }
}
