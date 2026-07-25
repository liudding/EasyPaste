import Foundation

/// Clip 子类型检测器：纯函数式，无状态，可安全在任意上下文调用。
/// 检测 text 类型的子类型（richText / email / json），并计算基于实际内容的 SHA-256 hash。
struct ClipTypeDetector {

    /// 检测 text 类型的子类型。
    /// 按优先级：richText > json > email > nil(普通文本)
    /// 注意：颜色值检测在 makeItem() 中已将 kind 重分类为 .color，不进入此函数。
    /// - Parameters:
    ///   - text: 剪贴板纯文本内容
    ///   - allPasteboardData: 剪贴板所有 UTI 类型及原始数据
    /// - Returns: 检测到的子类型，nil 表示普通纯文本
    static func detect(text: String?, allPasteboardData: [UTIEntry]?) -> ClipSubkind? {
        // 1. 富文本优先：allPasteboardData 含 public.rtf / com.apple.flat-rtfd / public.html
        if isRichText(allPasteboardData) {
            return .richText
        }
        // 2. JSON：首字符为 { 或 [，且 JSONSerialization 可解析
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            if isJSON(text) {
                return .json
            }
            // 3. email：匹配标准 email 正则
            if isEmail(text) {
                return .email
            }
        }
        return nil
    }

    /// 判断是否为富文本：allPasteboardData 含 public.rtf / com.apple.flat-rtfd / public.html
    static func isRichText(_ entries: [UTIEntry]?) -> Bool {
        guard let entries = entries, !entries.isEmpty else { return false }
        let richTextUTIs: Set<String> = [
            "public.rtf",
            "com.apple.flat-rtfd",
            "public.html",
        ]
        return entries.contains { richTextUTIs.contains($0.uti) }
    }

    /// 判断是否为 JSON：首字符为 { 或 [，且 JSONSerialization 可解析
    static func isJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    /// 判断是否为 email：匹配 ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$
    static func isEmail(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(
            pattern: "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        ) else { return false }
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        return regex.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    /// 基于 allPasteboardData 的实际内容计算 SHA-256 hash。
    /// 对每个 UTIEntry 计算 "uti:sha256(data)"，按 UTI 字母排序后用 "|" 拼接，再对拼接结果做一次 SHA-256。
    /// 确保不同内容即使数据长度相同也不会碰撞。
    /// - Returns: SHA-256 hex 字符串；无 allPasteboardData 时返回 nil
    static func computeContentHash(_ entries: [UTIEntry]?) -> String? {
        guard let entries = entries, !entries.isEmpty else { return nil }
        // 对每个 entry 计算 "uti:sha256hex(data)"，按 UTI 排序后拼接
        let components = entries
            .sorted { $0.uti < $1.uti }
            .map { entry in
                "\(entry.uti):\(entry.data.sha256Hex)"
            }
        let joined = components.joined(separator: "|")
        guard let data = joined.data(using: .utf8) else { return nil }
        return data.sha256Hex
    }

    /// 对无 allPasteboardData 的旧数据，用 displayTitle + detail 生成回退 hash。
    /// 格式为 "kind:displayTitle:detail" 的 SHA-256。
    static func computeFallbackHash(kind: ClipKind, title: String?, detail: String) -> String {
        let input = "\(kind.rawValue):\(title ?? ""):\(detail)"
        guard let data = input.data(using: .utf8) else { return input }
        return data.sha256Hex
    }
}
