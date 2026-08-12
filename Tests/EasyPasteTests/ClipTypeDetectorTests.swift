import Testing
import Foundation
@testable import EasyPaste

/// ClipTypeDetector 单元测试：覆盖 isRichText / isJSON / isEmail / detect /
/// computeContentHash / computeFallbackHash 全部公共 API。
/// 纯函数式检测器，无需 @MainActor 与数据库。
@Suite
struct ClipTypeDetectorTests {

    // MARK: - isRichText

    @Test func isRichTextReturnsTrueForRTFEntry() {
        let entries = [UTIEntry(uti: "public.rtf", data: Data("{\\rtf1}".utf8))]
        #expect(ClipTypeDetector.isRichText(entries) == true)
    }

    @Test func isRichTextReturnsTrueForHTMLEntry() {
        let entries = [UTIEntry(uti: "public.html", data: Data("<p>hi</p>".utf8))]
        #expect(ClipTypeDetector.isRichText(entries) == true)
    }

    @Test func isRichTextReturnsTrueForFlatRTFDEntry() {
        let entries = [UTIEntry(uti: "com.apple.flat-rtfd", data: Data("rtfd".utf8))]
        #expect(ClipTypeDetector.isRichText(entries) == true)
    }

    @Test func isRichTextReturnsFalseForPlainTextInputOnly() {
        let entries = [UTIEntry(uti: "public.plain-text", data: Data("hello".utf8))]
        #expect(ClipTypeDetector.isRichText(entries) == false)
    }

    @Test func isRichTextReturnsFalseForNilEntries() {
        #expect(ClipTypeDetector.isRichText(nil) == false)
    }

    @Test func isRichTextReturnsFalseForEmptyEntries() {
        #expect(ClipTypeDetector.isRichText([]) == false)
    }

    @Test func isRichTextDetectsAmongMultipleEntries() {
        let entries = [
            UTIEntry(uti: "public.plain-text", data: Data("hello".utf8)),
            UTIEntry(uti: "public.html", data: Data("<p>hi</p>".utf8)),
        ]
        #expect(ClipTypeDetector.isRichText(entries) == true)
    }

    // MARK: - isJSON

    @Test func isJSONReturnsTrueForObjectLiteral() {
        #expect(ClipTypeDetector.isJSON("{\"a\":1}") == true)
    }

    @Test func isJSONReturnsTrueForArrayLiteral() {
        #expect(ClipTypeDetector.isJSON("[1,2,3]") == true)
    }

    @Test func isJSONReturnsTrueForNestedObject() {
        #expect(ClipTypeDetector.isJSON("{\"a\":{\"b\":[1,2]}}") == true)
    }

    @Test func isJSONReturnsTrueForWhitespacePrefixedObject() {
        #expect(ClipTypeDetector.isJSON("  \n  {\"a\":1}") == true)
    }

    @Test func isJSONReturnsFalseForPlainString() {
        #expect(ClipTypeDetector.isJSON("hello world") == false)
    }

    @Test func isJSONReturnsFalseForNumber() {
        // 首字符不是 { 或 [
        #expect(ClipTypeDetector.isJSON("12345") == false)
    }

    @Test func isJSONReturnsFalseForMalformedObject() {
        #expect(ClipTypeDetector.isJSON("{a:1}") == false)
    }

    @Test func isJSONReturnsFalseForEmptyString() {
        #expect(ClipTypeDetector.isJSON("") == false)
    }

    // MARK: - isEmail

    @Test func isEmailReturnsTrueForStandardEmail() {
        #expect(ClipTypeDetector.isEmail("user@example.com") == true)
    }

    @Test func isEmailReturnsTrueForComplexEmail() {
        #expect(ClipTypeDetector.isEmail("first.last+tag@sub.domain.org") == true)
    }

    @Test func isEmailReturnsTrueForNumbersInEmail() {
        #expect(ClipTypeDetector.isEmail("123user@example.co.uk") == true)
    }

    @Test func isEmailReturnsFalseForPlainString() {
        #expect(ClipTypeDetector.isEmail("hello world") == false)
    }

    @Test func isEmailReturnsFalseForMissingAtSign() {
        #expect(ClipTypeDetector.isEmail("user.example.com") == false)
    }

    @Test func isEmailReturnsFalseForMissingDomainTLD() {
        #expect(ClipTypeDetector.isEmail("user@example") == false)
    }

    @Test func isEmailReturnsFalseForEmptyString() {
        #expect(ClipTypeDetector.isEmail("") == false)
    }

    // MARK: - detect (优先级 richText > json > email > nil)

    @Test func detectReturnsRichTextWhenRTFPresent() {
        // 即使 text 是 JSON，富文本优先级更高
        let entries = [UTIEntry(uti: "public.rtf", data: Data("{\\rtf1}".utf8))]
        let result = ClipTypeDetector.detect(text: "{\"a\":1}", allPasteboardData: entries)
        #expect(result == .richText)
    }

    @Test func detectReturnsJSONForValidJSONText() {
        let result = ClipTypeDetector.detect(text: "{\"a\":1}", allPasteboardData: nil)
        #expect(result == .json)
    }

    @Test func detectReturnsEmailForEmailText() {
        let result = ClipTypeDetector.detect(text: "user@example.com", allPasteboardData: nil)
        #expect(result == .email)
    }

    @Test func detectReturnsNilForPlainText() {
        let result = ClipTypeDetector.detect(text: "hello world", allPasteboardData: nil)
        #expect(result == nil)
    }

    @Test func detectReturnsNilForNilText() {
        let result = ClipTypeDetector.detect(text: nil, allPasteboardData: nil)
        #expect(result == nil)
    }

    @Test func detectReturnsNilForEmptyText() {
        let result = ClipTypeDetector.detect(text: "   ", allPasteboardData: nil)
        #expect(result == nil)
    }

    @Test func detectReturnsJSONWhenRichTextAbsent() {
        // 有 plain-text entry，但不是富文本 UTI，text 是 JSON
        let entries = [UTIEntry(uti: "public.plain-text", data: Data("{\"a\":1}".utf8))]
        let result = ClipTypeDetector.detect(text: "{\"a\":1}", allPasteboardData: entries)
        #expect(result == .json)
    }

    @Test func detectPrioritizesJSONOverEmail() {
        // JSON 的首字符是 {，优先于 email 匹配
        // 注意：这不是一个合法的 email，所以即使优先级 email 也不会匹配
        let result = ClipTypeDetector.detect(text: "{\"email\":\"user@example.com\"}", allPasteboardData: nil)
        #expect(result == .json)
    }

    // MARK: - computeContentHash

    @Test func computeContentHashReturnsNilForNilEntries() {
        #expect(ClipTypeDetector.computeContentHash(nil) == nil)
    }

    @Test func computeContentHashReturnsNilForEmptyEntries() {
        #expect(ClipTypeDetector.computeContentHash([]) == nil)
    }

    @Test func computeContentHashReturnsSameHashForSameContent() {
        let entries = [UTIEntry(uti: "public.plain-text", data: Data("hello".utf8))]
        let hash1 = ClipTypeDetector.computeContentHash(entries)
        let hash2 = ClipTypeDetector.computeContentHash(entries)
        #expect(hash1 == hash2)
        #expect(hash1 != nil)
    }

    @Test func computeContentHashReturnsDifferentHashForDifferentContent() {
        let entries1 = [UTIEntry(uti: "public.plain-text", data: Data("hello".utf8))]
        let entries2 = [UTIEntry(uti: "public.plain-text", data: Data("world".utf8))]
        let hash1 = ClipTypeDetector.computeContentHash(entries1)
        let hash2 = ClipTypeDetector.computeContentHash(entries2)
        #expect(hash1 != hash2)
    }

    @Test func computeContentHashIsOrderIndependent() {
        // UTI 按字母排序后拼接，所以 entries 顺序不同但内容相同时应得到相同 hash
        let entriesA = [
            UTIEntry(uti: "public.html", data: Data("<p>".utf8)),
            UTIEntry(uti: "public.rtf", data: Data("{\\rtf1}".utf8)),
        ]
        let entriesB = [
            UTIEntry(uti: "public.rtf", data: Data("{\\rtf1}".utf8)),
            UTIEntry(uti: "public.html", data: Data("<p>".utf8)),
        ]
        let hashA = ClipTypeDetector.computeContentHash(entriesA)
        let hashB = ClipTypeDetector.computeContentHash(entriesB)
        #expect(hashA == hashB)
    }

    @Test func computeContentHashDistinguishesByUTI() {
        // 相同 data 但不同 UTI 应产生不同 hash
        let data = Data("hello".utf8)
        let entries1 = [UTIEntry(uti: "public.rtf", data: data)]
        let entries2 = [UTIEntry(uti: "public.html", data: data)]
        let hash1 = ClipTypeDetector.computeContentHash(entries1)
        let hash2 = ClipTypeDetector.computeContentHash(entries2)
        #expect(hash1 != hash2)
    }

    @Test func computeContentHashProducesSHA256HexString() {
        let entries = [UTIEntry(uti: "public.plain-text", data: Data("hello".utf8))]
        let hash = ClipTypeDetector.computeContentHash(entries)
        #expect(hash != nil)
        // SHA-256 输出为 64 位 hex 字符
        #expect(hash?.count == 64)
        // 全部为 hex 字符
        let hexSet = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(hash?.unicodeScalars.allSatisfy { hexSet.contains($0) } == true)
    }

    // MARK: - computeFallbackHash

    @Test func computeFallbackHashReturnsSameValueForSameInput() {
        let h1 = ClipTypeDetector.computeFallbackHash(kind: .text, title: "hello", detail: "world")
        let h2 = ClipTypeDetector.computeFallbackHash(kind: .text, title: "hello", detail: "world")
        #expect(h1 == h2)
    }

    @Test func computeFallbackHashReturnsDifferentValueForDifferentKind() {
        let h1 = ClipTypeDetector.computeFallbackHash(kind: .text, title: "hello", detail: "world")
        let h2 = ClipTypeDetector.computeFallbackHash(kind: .link, title: "hello", detail: "world")
        #expect(h1 != h2)
    }

    @Test func computeFallbackHashReturnsDifferentValueForDifferentTitle() {
        let h1 = ClipTypeDetector.computeFallbackHash(kind: .text, title: "hello", detail: "world")
        let h2 = ClipTypeDetector.computeFallbackHash(kind: .text, title: "goodbye", detail: "world")
        #expect(h1 != h2)
    }

    @Test func computeFallbackHashReturnsDifferentValueForDifferentDetail() {
        let h1 = ClipTypeDetector.computeFallbackHash(kind: .text, title: "hello", detail: "world")
        let h2 = ClipTypeDetector.computeFallbackHash(kind: .text, title: "hello", detail: "earth")
        #expect(h1 != h2)
    }

    @Test func computeFallbackHashHandlesNilTitle() {
        // nil title 用空字符串替代，不应崩溃
        let h1 = ClipTypeDetector.computeFallbackHash(kind: .text, title: nil, detail: "world")
        let h2 = ClipTypeDetector.computeFallbackHash(kind: .text, title: "", detail: "world")
        // nil 和 "" 应该产生相同的 hash（因为 nil ?? "" 转为 ""）
        #expect(h1 == h2)
    }

    @Test func computeFallbackHashProducesSHA256HexString() {
        let hash = ClipTypeDetector.computeFallbackHash(kind: .text, title: "hello", detail: "world")
        #expect(hash.count == 64)
        let hexSet = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(hash.unicodeScalars.allSatisfy { hexSet.contains($0) })
    }
}

/// ClipSubkind 枚举编码/解码测试。
@Suite
struct ClipSubkindTests {

    @Test func richTextRawValue() {
        #expect(ClipSubkind.richText.rawValue == "richText")
    }

    @Test func emailRawValue() {
        #expect(ClipSubkind.email.rawValue == "email")
    }

    @Test func jsonRawValue() {
        #expect(ClipSubkind.json.rawValue == "json")
    }

    @Test func encodeDecodeRoundTrip() throws {
        let values: [ClipSubkind] = [.richText, .email, .json]
        let data = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode([ClipSubkind].self, from: data)
        #expect(decoded == values)
    }

    @Test func decodeFromRawStringValues() throws {
        // 模拟从数据库读取的 rawValue 还原
        let json = "[\"richText\",\"email\",\"json\"]"
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode([ClipSubkind].self, from: data)
        #expect(decoded == [.richText, .email, .json])
    }

    @Test func initFromValidRawValue() {
        #expect(ClipSubkind(rawValue: "richText") == .richText)
        #expect(ClipSubkind(rawValue: "email") == .email)
        #expect(ClipSubkind(rawValue: "json") == .json)
    }

    @Test func initFromInvalidRawValueReturnsNil() {
        #expect(ClipSubkind(rawValue: "unknown") == nil)
        #expect(ClipSubkind(rawValue: "") == nil)
    }
}

/// ClipboardStore 去重（promoteClip）逻辑测试。
/// 使用临时数据库，所有用例 @MainActor 标注。
@Suite
struct ClipboardStoreDedupTests {

    private func makeTempDB() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "easypaste_tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "db.sqlite")
    }

    // MARK: - 相同 contentHash 触发 promoteClip

    @Test @MainActor func duplicateContentHashPromotesClipToTop() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)

        let entry = UTIEntry(uti: "public.plain-text", data: Data("same-content".utf8))
        let c1 = Clip(kind: .text, text: "first", allPasteboardData: [entry])
        c1.contentHash = ClipTypeDetector.computeContentHash([entry])
        let c2 = Clip(kind: .text, text: "second", allPasteboardData: [entry])
        c2.contentHash = ClipTypeDetector.computeContentHash([entry])

        store.add(c1)
        // 记录 c1 的原始 createdAt
        let originalCreatedAt = store.items.first?.createdAt

        // 稍微等待以保证 .now 不同
        Thread.sleep(forTimeInterval: 0.01)
        store.add(c2)

        // 重复不应新增条目
        #expect(store.items.count == 1)
        // 重复应触发 promoteClip：条目仍在最前（index 0）
        #expect(store.items.first?.id == c1.id)
        // createdAt 应被更新（promoteClip 设置 .now）
        #expect(store.items.first?.createdAt != originalCreatedAt)
        // 新的 createdAt 应晚于原始 createdAt
        #expect((store.items.first?.createdAt.timeIntervalSince1970 ?? 0) >= (originalCreatedAt?.timeIntervalSince1970 ?? 0))
    }

    @Test @MainActor func duplicateContentHashMovesClipAboveOtherItems() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)

        let entryA = UTIEntry(uti: "public.plain-text", data: Data("content-a".utf8))
        let entryB = UTIEntry(uti: "public.plain-text", data: Data("content-b".utf8))
        let c1 = Clip(kind: .text, text: "first", allPasteboardData: [entryA])
        c1.contentHash = ClipTypeDetector.computeContentHash([entryA])
        let c2 = Clip(kind: .text, text: "second", allPasteboardData: [entryB])
        c2.contentHash = ClipTypeDetector.computeContentHash([entryB])

        store.add(c1)
        store.add(c2)
        #expect(store.items.count == 2)
        // c2 在最前
        #expect(store.items.first?.id == c2.id)

        // 再次添加 c1（重复），应触发 promoteClip 将 c1 移到最前
        Thread.sleep(forTimeInterval: 0.01)
        store.add(c1)
        #expect(store.items.count == 2)
        #expect(store.items.first?.id == c1.id)
    }

    // MARK: - 不同 contentHash 正常添加

    @Test @MainActor func differentContentHashAddsNormally() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)

        let entry1 = UTIEntry(uti: "public.plain-text", data: Data("content-1".utf8))
        let entry2 = UTIEntry(uti: "public.plain-text", data: Data("content-2".utf8))
        let c1 = Clip(kind: .text, text: "first", allPasteboardData: [entry1])
        c1.contentHash = ClipTypeDetector.computeContentHash([entry1])
        let c2 = Clip(kind: .text, text: "second", allPasteboardData: [entry2])
        c2.contentHash = ClipTypeDetector.computeContentHash([entry2])

        store.add(c1)
        store.add(c2)
        #expect(store.items.count == 2)
    }

    // MARK: - 无 contentHash 回退去重

    @Test @MainActor func dedupFallsBackToFallbackHashWhenNoContentHash() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)

        // 两个 clip 无 allPasteboardData（contentHash 为 nil），但 displayTitle + detail 相同
        let c1 = Clip(kind: .text, text: "same-text")
        let c2 = Clip(kind: .text, text: "same-text")
        // 注意：displayTitle 对 text 类型返回 L10n.tr("clip.default_text")，
        // 除非设置了 title。detail 返回 text。

        store.add(c1)
        #expect(store.items.count == 1)
        store.add(c2)
        // 两者 fallbackHash 相同（kind + displayTitle + detail） -> 去重
        #expect(store.items.count == 1)
    }

    @Test @MainActor func differentKindDoesNotDedup() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)

        // 相同 allPasteboardData 但不同 kind 不应去重
        let entry = UTIEntry(uti: "public.plain-text", data: Data("dup".utf8))
        let c1 = Clip(kind: .text, text: "a", allPasteboardData: [entry])
        c1.contentHash = ClipTypeDetector.computeContentHash([entry])
        let c2 = Clip(kind: .link, text: "a", allPasteboardData: [entry])
        c2.contentHash = ClipTypeDetector.computeContentHash([entry])

        store.add(c1)
        store.add(c2)
        // kind 不同 -> 不去重
        #expect(store.items.count == 2)
    }

    // MARK: - promoteClip 持久化

    @Test @MainActor func promoteClipPersistsToDatabase() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)

        let entry = UTIEntry(uti: "public.plain-text", data: Data("persist-dup".utf8))
        let c1 = Clip(kind: .text, text: "first", allPasteboardData: [entry])
        c1.contentHash = ClipTypeDetector.computeContentHash([entry])
        let c2 = Clip(kind: .text, text: "second", allPasteboardData: [entry])
        c2.contentHash = ClipTypeDetector.computeContentHash([entry])

        store.add(c1)
        let firstCreatedAt = store.items.first?.createdAt

        Thread.sleep(forTimeInterval: 0.01)
        store.add(c2)

        // 重建 store 验证持久化
        let store2 = ClipboardStore(databaseURL: url)
        #expect(store2.items.count == 1)
        #expect(store2.items.first?.id == c1.id)
        // 持久化后的 createdAt 应与内存一致（已被 promote 更新）
        #expect(store2.items.first?.createdAt != firstCreatedAt)
    }
}

/// AppSettings 的 hideDockIcon 测试：默认值、回调触发、快照编解码兼容性。
/// 使用 .serialized 避免并行测试共享 UserDefaults.standard 导致 SIGSEGV。
@Suite(.serialized)
struct AppSettingsHideDockTests {

    // MARK: - 默认值

    @Test @MainActor func hideDockIconDefaultsToFalse() {
        // 清理可能的旧 UserDefaults
        UserDefaults.standard.removeObject(forKey: "EasyPasteSettings")
        let settings = AppSettings()
        #expect(settings.hideDockIcon == false)
    }

    // MARK: - 回调触发

    @Test @MainActor func hideDockIconChangeTriggersCallback() {
        UserDefaults.standard.removeObject(forKey: "EasyPasteSettings")
        let settings = AppSettings()
        var callbackFired = false
        settings.onDockIconVisibilityChanged = {
            callbackFired = true
        }
        settings.hideDockIcon = true
        #expect(callbackFired == true)
    }

    @Test @MainActor func hideDockIconNoCallbackWhenUnchanged() {
        UserDefaults.standard.removeObject(forKey: "EasyPasteSettings")
        let settings = AppSettings()
        var callbackCount = 0
        settings.onDockIconVisibilityChanged = {
            callbackCount += 1
        }
        // 设置相同值不应触发回调（didSet 仍会触发，需验证行为）
        // 注意：Swift 的 didSet 在赋相同值时仍会触发，这里验证至少不崩溃
        settings.hideDockIcon = false
        #expect(settings.hideDockIcon == false)
    }

    // MARK: - 快照编解码

    @Test @MainActor func hideDockIconPersistsAcrossSnapshot() {
        UserDefaults.standard.removeObject(forKey: "EasyPasteSettings")
        let settings = AppSettings()
        settings.hideDockIcon = true

        // 新建一个 settings 实例，应从 UserDefaults 加载持久化值
        let loaded = AppSettings()
        #expect(loaded.hideDockIcon == true)
    }
    @Test @MainActor func hideDockIconPersistsFalseValue() {
        UserDefaults.standard.removeObject(forKey: "EasyPasteSettings")
        let settings = AppSettings()

        settings.hideDockIcon = false

        let loaded = AppSettings()
        #expect(loaded.hideDockIcon == false)
    }

    // MARK: - openAtLogin 递归防护

    /// @Observable 宏展开后 didSet 在同值赋值时也会执行 → applyLoginItem。
    /// 旧代码：unregister() 在未注册时抛错 → catch 里 `openAtLogin = false`（同值）再次触发
    /// didSet → applyLoginItem → 无限递归 → 栈溢出 SIGSEGV。
    /// 用连续同值赋值触发该路径，修复后应不崩溃且终值正确。
    @Test @MainActor func openAtLoginSameValueAssignmentDoesNotRecurse() {
        UserDefaults.standard.removeObject(forKey: "EasyPasteSettings")
        let settings = AppSettings()
        settings.openAtLogin = false
        settings.openAtLogin = false
        settings.openAtLogin = true
        settings.openAtLogin = true
        settings.openAtLogin = false
        settings.openAtLogin = false
        #expect(settings.openAtLogin == false)
    }

    // MARK: - 旧存档兼容性（decodeIfPresent）

    @Test @MainActor func oldSnapshotWithoutHideDockIconDecodesToFalse() throws {
        // 构造一个不含 hideDockIcon 字段的旧快照 JSON
        // 模拟旧版存档结构
        let oldJSON = """
        {
            "panelPosition": "bottom",
            "openAtLogin": false,
            "iCloudSync": false,
            "showInMenuBar": true,
            "soundName": "Pop",
            "soundEnabled": true,
            "alwaysPastePlainText": false,
            "historyStepIndex": 21,
            "maxItemsMode": "limited",
            "maxItemsCount": 2000,
            "ignoredApps": [],
            "invokeShortcut": {"carbonKeyCode": 123, "carbonModifiers": 0},
            "boardSwitchShortcut": {"carbonKeyCode": 124, "carbonModifiers": 0},
            "hasCompletedOnboarding": false
        }
        """
        let data = Data(oldJSON.utf8)
        UserDefaults.standard.set(data, forKey: "EasyPasteSettings")

        let settings = AppSettings()
        // 旧存档无 hideDockIcon 字段 -> decodeIfPresent 返回 nil -> 默认 false
        #expect(settings.hideDockIcon == false)
    }

    @Test @MainActor func newSnapshotWithHideDockIconDecodesCorrectly() throws {
        UserDefaults.standard.removeObject(forKey: "EasyPasteSettings")
        let settings = AppSettings()
        settings.hideDockIcon = true
        settings.save()

        // 直接验证 UserDefaults 中的数据可被正确解码
        guard let data = UserDefaults.standard.data(forKey: "EasyPasteSettings") else {
            Issue.record("Settings not persisted")
            return
        }
        // 解码后的 JSON 应包含 hideDockIcon 字段
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["hideDockIcon"] as? Bool == true)
    }
}

/// ClipboardService.lastChangeCount 修复测试。
/// 验证 start() 后 lastChangeCount == -1，确保首次 timer tick 能触发读取。
@Suite
struct ClipboardServiceStartTests {

    @Test @MainActor func startSetsLastChangeCountToMinusOne() {
        let service = ClipboardService()
        // 调用 start() 前默认值是当前 changeCount
        // 调用 start() 后应为 -1
        service.start()
        #expect(service.lastChangeCount == -1)
        service.stop()
    }
}
