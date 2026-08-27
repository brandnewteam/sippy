import Testing
@testable import SippyCore

@Suite struct PhoneNumberMatcherTests {
    @Test func normalizeStripsFormatting() {
        #expect(PhoneNumberMatcher.normalize("+39 06 1234-5678") == "+390612345678")
        #expect(PhoneNumberMatcher.normalize("(06) 12.34.56.78") == "0612345678")
    }

    @Test func exactMatch() {
        #expect(PhoneNumberMatcher.matches("124", "124"))
        #expect(PhoneNumberMatcher.matches("06 123 456 78", "0612345678"))
    }

    @Test func internationalVsNationalMatches() {
        #expect(PhoneNumberMatcher.matches("+39 06 1234 5678", "0612345678"))
        #expect(PhoneNumberMatcher.matches("00390612345678", "0612345678"))
    }

    @Test func shortExtensionsRequireExactMatch() {
        // "124" must not match "5124" or a long number ending in 124.
        #expect(!PhoneNumberMatcher.matches("124", "5124"))
        #expect(!PhoneNumberMatcher.matches("124", "0612345124"))
        #expect(PhoneNumberMatcher.matches("124", "124"))
    }

    @Test func differentNumbersDoNotMatch() {
        #expect(!PhoneNumberMatcher.matches("0612345678", "0612345679"))
        #expect(!PhoneNumberMatcher.matches("", "124"))
    }
}
