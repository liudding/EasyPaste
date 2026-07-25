import AppKit
import Foundation
import SwiftUI

/// JSON 格式化预览 SwiftUI 视图。
/// 使用 JSONSerialization .prettyPrinted 格式化展示，
/// 解析失败时显示原始文本 + 错误提示。
struct JSONPreviewView: View {
    let clip: Clip
    var onClose: (() -> Void)? = nil

    @State private var l10nStore = L10nStore.shared

    /// 格式化后的 JSON 文本，解析失败时为 nil
    private var formattedJSON: String? {
        let rawText = clip.text ?? clip.previewPlainText ?? ""
        guard let data = rawText.data(using: .utf8) else { return nil }
        guard let jsonObject = try? JSONSerialization.jsonObject(
            with: data, options: [.fragmentsAllowed]
        ) else { return nil }
        guard let prettyData = try? JSONSerialization.data(
            withJSONObject: jsonObject,
            options: [.prettyPrinted, .fragmentsAllowed]
        ) else { return nil }
        return String(data: prettyData, encoding: .utf8)
    }

    var body: some View {
        let _ = l10nStore.version
        VStack(spacing: 16) {
            HStack {
                Text(L10n.menuJSONPreview)
                    .font(.headline)
                Spacer()
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if let formatted = formattedJSON {
                ScrollView {
                    Text(formatted)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(4)
                }
            } else {
                // 解析失败：显示原始文本 + 错误提示
                VStack(spacing: 8) {
                    Label(L10n.jsonError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    ScrollView {
                        Text(clip.text ?? clip.previewPlainText ?? "")
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(4)
                    }
                }
            }

            Text(L10n.previewCloseHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: 520, maxHeight: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.12)))
    }
}
