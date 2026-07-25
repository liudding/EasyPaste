import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// 二维码展示 SwiftUI 视图。
/// 使用 CIFilter CIQRCodeGenerator 原生生成二维码 NSImage，无第三方依赖。
/// 当内容过长（> 500 字符）时显示警告提示。
struct QRCodeView: View {
    let content: String
    var onClose: (() -> Void)? = nil

    @State private var l10nStore = L10nStore.shared

    /// 生成二维码 NSImage
    private func generateQRCode() -> NSImage? {
        guard let data = content.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        // 放大到合适尺寸（默认 CIImage 很小，需 transform 缩放）
        let scale = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scale)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    var body: some View {
        let _ = l10nStore.version
        VStack(spacing: 16) {
            HStack {
                Text(L10n.menuQRCode)
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

            if let qrImage = generateQRCode() {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 240)
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
            }

            // 内容预览（截断显示）
            if !content.isEmpty {
                Text(content)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            // 文本过长警告
            if content.count > 500 {
                Label(L10n.qrTooLong, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text(L10n.previewCloseHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: 400, maxHeight: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.12)))
    }
}
