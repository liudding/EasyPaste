import Testing
@testable import EasyPaste

@Test func clipHasReadableTitle() {
    // displayTitle 返回自定义 title（若已设置），否则返回本地化的类型名。
    // 这里测试设置了自定义 title 的情况。
    var clip = Clip(kind: .text, text: "Hello clipboard")
    clip.title = "My Title"
    #expect(clip.displayTitle == "My Title")
}

@Test func automationRuleMatchesKeywordAndSourceApp() {
    var clip = Clip(kind: .text, text: "Deploy build to production")
    clip.sourceApplication = "Xcode"
    let rule = AutomationRule(name: "Build notes", keyword: "deploy", sourceApplication: "Xcode")
    #expect(rule.matches(clip))
}
