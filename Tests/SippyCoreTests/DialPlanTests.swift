import Testing
@testable import SippyCore

@Suite struct DialPlanTests {
    let plan = DialPlan(outsideLinePrefix: "0")

    @Test func dialpadIsVerbatim() {
        #expect(plan.apply(to: "124", origin: .dialpad) == "124")
        #expect(plan.apply(to: "0612345678", origin: .dialpad) == "0612345678")
    }

    @Test func internalContactIsVerbatim() {
        #expect(plan.apply(to: "124", origin: .internalContact) == "124")
    }

    @Test func systemContactGetsPrefix() {
        #expect(plan.apply(to: "0612345678", origin: .systemContact) == "00612345678")
    }

    @Test func externalNumberGetsPrefix() {
        #expect(plan.apply(to: "0612345678", origin: .external) == "00612345678")
    }

    @Test func multiCharacterPrefix() {
        let plan = DialPlan(outsideLinePrefix: "0*4")
        #expect(plan.apply(to: "0612345678", origin: .external) == "0*40612345678")
    }

    @Test func emptyPrefixDisablesPrefixing() {
        let plan = DialPlan()
        #expect(plan.apply(to: "0612345678", origin: .external) == "0612345678")
    }

    @Test func formattingNoiseIsStripped() {
        #expect(plan.apply(to: "+39 06 1234-5678", origin: .external) == "0+390612345678")
        #expect(plan.apply(to: "(06) 12.34.56.78", origin: .external) == "00612345678")
    }

    @Test func starAndPoundSurviveNormalization() {
        #expect(plan.apply(to: "*43#", origin: .dialpad) == "*43#")
    }

    @Test func internationalRewrite() {
        let plan = DialPlan(outsideLinePrefix: "0", internationalPrefix: "00")
        #expect(plan.apply(to: "+39 06 12345678", origin: .external) == "000390612345678")
    }

    @Test func internationalRewriteOnlyAppliesToLeadingPlus() {
        let plan = DialPlan(outsideLinePrefix: "", internationalPrefix: "00")
        #expect(plan.apply(to: "061234+5678", origin: .external) == "061234+5678")
    }

    @Test func noRewriteKeepsPlus() {
        #expect(plan.apply(to: "+390612345678", origin: .dialpad) == "+390612345678")
    }
}
