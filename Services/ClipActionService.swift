import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Color format options for the "Paste as" submenu on color clip cards.
enum ColorPasteFormat: String, CaseIterable {
    case hex, rgb, hsl
}

/// 执行 Clip 类型专属操作的 Action 服务。
/// 持有 ClipboardService 弱引用，以便在写入剪贴板后同步 lastChangeCount。
/// 持有 PanelState 弱引用，用于触发 QR 码和 JSON 预览浮层。
@MainActor
final class ClipActionService {
    private weak var clipboard: ClipboardService?
    private weak var panelState: PanelState?

    init(clipboard: ClipboardService, panelState: PanelState) {
        self.clipboard = clipboard
        self.panelState = panelState
    }

    // MARK: - 二维码

    /// 在面板预览浮层中展示二维码。
    /// - Parameter content: 要编码为二维码的文本内容
    func showQRCode(content: String) {
        panelState?.qrCodeContent = content
    }

    // MARK: - 文件导出

    /// 导出为 .txt 文件（text / 富文本）
    func exportAsText(_ clip: Clip) {
        let text = clip.text ?? clip.previewPlainText ?? ""
        guard !text.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = L10n.menuExportTxt
        panel.nameFieldStringValue = defaultFileName(ext: "txt")
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? text.data(using: .utf8)?.write(to: url)
        }
    }

    /// 导出为 .rtf 文件（仅富文本）
    func exportAsRTF(_ clip: Clip) {
        guard let attr = clip.attributedText else { return }
        let panel = NSSavePanel()
        panel.title = L10n.menuExportRtf
        panel.nameFieldStringValue = defaultFileName(ext: "rtf")
        panel.allowedContentTypes = [.rtf]
        if panel.runModal() == .OK, let url = panel.url {
            // 生成 RTF 数据
            if let rtfData = try? attr.data(
                from: NSRange(location: 0, length: attr.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ) {
                try? rtfData.write(to: url)
            }
        }
    }

    /// 另存为图片文件（image）
    func exportAsImage(_ clip: Clip) {
        guard let imageData = clip.imageData else { return }
        let panel = NSSavePanel()
        panel.title = L10n.menuSaveAs
        // 根据 uti 推断扩展名
        let ext = imageExtension(for: clip.uti)
        panel.nameFieldStringValue = defaultFileName(ext: ext)
        if let uti = clip.uti, let utType = UTType(uti) {
            panel.allowedContentTypes = [utType]
        }
        if panel.runModal() == .OK, let url = panel.url {
            try? imageData.write(to: url)
        }
    }

    // MARK: - 邮件

    /// 打开 mailto: 链接，调用系统默认邮件客户端
    func sendEmail(to address: String) {
        guard let url = URL(string: "mailto:\(address)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 色值粘贴

    /// Paste a color value in the specified format to the target app.
    /// - Parameters:
    ///   - clip: The color clip item.
    ///   - format: The desired color format (.hex, .rgb, or .hsl).
    func pasteColorAs(_ clip: Clip, format: ColorPasteFormat) {
        let value: String?
        switch format {
        case .hex: value = colorHex(from: clip)
        case .rgb: value = colorRGB(from: clip)
        case .hsl: value = colorHSL(from: clip)
        }
        guard let value else { return }
        clipboard?.pasteString(value)
    }

    // MARK: - URL

    /// 在默认浏览器中打开链接
    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - JSON 预览

    /// 在面板预览浮层中展示格式化 JSON
    func previewJSON(_ clip: Clip) {
        panelState?.jsonPreviewItem = clip
    }

    // MARK: - Private helpers

    /// 生成默认文件名：clip_yyyyMMdd_HHmmss.ext
    private func defaultFileName(ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        return "clip_\(timestamp).\(ext)"
    }

    /// 根据 UTI 推断图片文件扩展名
    private func imageExtension(for uti: String?) -> String {
        guard let uti = uti else { return "png" }
        switch uti {
        case "public.png": return "png"
        case "public.jpeg", "public.jpg": return "jpg"
        case "public.heic", "public.heif": return "heic"
        case "public.tiff": return "tiff"
        case "com.microsoft.bmp": return "bmp"
        case "public.svg-image": return "svg"
        case "public.webp": return "webp"
        default: return "png"
        }
    }

    /// 从 Clip 的 resolvedColorValue 提取 NSColor sRGB 分量
    private func nsColor(from clip: Clip) -> NSColor? {
        guard let color = clip.resolvedColorValue else { return nil }
        return NSColor(color).usingColorSpace(.sRGB)
    }

    /// 计算 hex 色值字符串：#RRGGBB
    private func colorHex(from clip: Clip) -> String? {
        guard let nsColor = nsColor(from: clip) else { return nil }
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// 计算 rgb 色值字符串：rgb(255, 128, 0)
    private func colorRGB(from clip: Clip) -> String? {
        guard let nsColor = nsColor(from: clip) else { return nil }
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return "rgb(\(r), \(g), \(b))"
    }

    /// 计算 hsl 色值字符串：hsl(30, 100%, 50%)
    private func colorHSL(from clip: Clip) -> String? {
        guard let nsColor = nsColor(from: clip) else { return nil }
        let r = nsColor.redComponent
        let g = nsColor.greenComponent
        let b = nsColor.blueComponent

        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let delta = maxVal - minVal

        // 亮度
        let lightness = (maxVal + minVal) / 2.0

        // 饱和度
        let saturation: Double
        if delta == 0 {
            saturation = 0
        } else {
            saturation = delta / (1.0 - abs(2.0 * lightness - 1.0))
        }

        // 色相
        let hue: Double
        if delta == 0 {
            hue = 0
        } else if maxVal == r {
            hue = 60.0 * (((g - b) / delta).truncatingRemainder(dividingBy: 6.0))
        } else if maxVal == g {
            hue = 60.0 * ((b - r) / delta + 2.0)
        } else {
            hue = 60.0 * ((r - g) / delta + 4.0)
        }
        let hueDegrees = hue < 0 ? hue + 360.0 : hue

        let h = Int(round(hueDegrees))
        let s = Int(round(saturation * 100))
        let l = Int(round(lightness * 100))
        return "hsl(\(h), \(s)%, \(l)%)"
    }
}
