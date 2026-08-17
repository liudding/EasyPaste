import Foundation
import Testing
@testable import EasyPaste

/// Clip 模型与自动化规则的单元测试。
/// blob 用例通过 `Clip.init(blobStore:)` 注入临时目录实例，不触碰全局 `BlobStore.shared`，
/// 因此无需 `.serialized`，可与其他 suite 并行。
@Suite
struct ClipModelTests {
    @Test func clipHasReadableTitle() {
        // displayTitle 返回自定义 title（若已设置），否则返回本地化的类型名。
        // 这里测试设置了自定义 title 的情况。
        let clip = Clip(kind: .text, text: "Hello clipboard")
        clip.title = "My Title"
        #expect(clip.displayTitle == "My Title")
    }

    @Test func automationRuleMatchesKeywordAndSourceApp() {
        let clip = Clip(kind: .text, text: "Deploy build to production")
        clip.sourceApplication = "Xcode"
        let rule = AutomationRule(name: "Build notes", keyword: "deploy", sourceApplication: "Xcode")
        #expect(rule.matches(clip))
    }

    /// 构造注入临时 BlobStore 的 Clip：blob 读写落在临时目录，
    /// 不污染真实 Application Support，也不依赖全局 shared 的换入换出。
    private func makeClip(kind: ClipKind, text: String? = nil, allPasteboardData: [UTIEntry]? = nil) throws -> Clip {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "easypaste_test_blobs/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return Clip(kind: kind, text: text, allPasteboardData: allPasteboardData,
                    blobStore: BlobStore(directory: dir))
    }

    /// attributedText 对同一 clip 多次访问应返回同一实例（惰性缓存）。
    /// 卡片 body 每次重渲染都会访问它；若无缓存，含 public.html 的条目每次渲染
    /// 都会全量解析 HTML → 输入检索时可见卡片集体重渲染 → 卡顿。
    @Test func attributedTextIsCachedPerClip() throws {
        let html = "<html><body><p>hello <b>world</b></p></body></html>"
        let clip = try makeClip(kind: .text, text: "hello world",
                                allPasteboardData: [UTIEntry(uti: "public.html", data: Data(html.utf8))])
        let first = clip.attributedText
        let second = clip.attributedText
        #expect(first != nil)
        #expect(first === second)
    }

    /// previewPlainText 多次访问应返回相同结果（惰性缓存，避免重复解析 HTML）。
    @Test func previewPlainTextIsStableAcrossAccesses() throws {
        let html = "<html><body><p>visible tail token</p></body></html>"
        let clip = try makeClip(kind: .text, text: nil,
                                allPasteboardData: [UTIEntry(uti: "public.html", data: Data(html.utf8))])
        let a = clip.previewPlainText
        let b = clip.previewPlainText
        #expect(a == b)
        #expect(a?.contains("visible tail token") == true)
    }
}
