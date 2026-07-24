import Testing
@testable import EasyPaste

@Test func clipHasReadableTitle() {
    let clip = Clip(kind: .text, text: "Hello clipboard")
    #expect(clip.displayTitle == "Hello clipboard")
}

@Test func automationRuleMatchesKeywordAndSourceApp() {
    var clip = Clip(kind: .text, text: "Deploy build to production")
    clip.sourceApplication = "Xcode"
    let rule = AutomationRule(name: "Build notes", keyword: "deploy", sourceApplication: "Xcode")
    #expect(rule.matches(clip))
}
