import Testing
import AppKit
@testable import EasyPaste

// MARK: - ColorPasteFormat enum tests

/// ColorPasteFormat 枚举测试：验证 case 数量、CaseIterable、rawValue。
@Suite
struct ColorPasteFormatTests {

    @Test func hasExactlyThreeCases() {
        #expect(ColorPasteFormat.allCases.count == 3)
    }

    @Test func casesAreHexRgbHsl() {
        #expect(ColorPasteFormat.allCases == [.hex, .rgb, .hsl])
    }

    @Test func rawValuesMatchCaseNames() {
        #expect(ColorPasteFormat.hex.rawValue == "hex")
        #expect(ColorPasteFormat.rgb.rawValue == "rgb")
        #expect(ColorPasteFormat.hsl.rawValue == "hsl")
    }

    @Test func canIterateAllCases() {
        var formats: [String] = []
        for format in ColorPasteFormat.allCases {
            formats.append(format.rawValue)
        }
        #expect(formats == ["hex", "rgb", "hsl"])
    }
}

// MARK: - pasteString & pasteColorAs tests (serialized to avoid pasteboard interference)

/// ClipboardService.pasteString 和 ClipActionService.pasteColorAs 集成测试。
/// 所有用例写入共享的 NSPasteboard.general，使用 .serialized 避免并行干扰。
@Suite(.serialized)
struct ColorPasteIntegrationTests {

    // MARK: - pasteString: pasteboard write
    // Note: pasteString calls pasteToTarget() which accesses NSApp.keyWindow.
    // NSApp is nil in test env until NSApplication.shared is called, so we
    // initialize it here to avoid a crash when accessibility is granted.

    @Test @MainActor func pasteStringWritesValueToPasteboard() {
        _ = NSApplication.shared
        let service = ClipboardService()
        service.pasteString("test-paste-value")
        #expect(NSPasteboard.general.string(forType: .string) == "test-paste-value")
    }

    @Test @MainActor func pasteStringSyncsLastChangeCount() {
        _ = NSApplication.shared
        let service = ClipboardService()
        service.pasteString("change-count-test")
        // pasteString 内部先 clearContents 再 setString，changeCount 应与 pasteboard 同步
        #expect(service.lastChangeCount == NSPasteboard.general.changeCount)
    }

    @Test @MainActor func pasteStringReplacesPreviousContent() {
        _ = NSApplication.shared
        let service = ClipboardService()
        service.pasteString("first-value")
        service.pasteString("second-value")
        // clearContents 确保只有最后一次写入的值在 pasteboard 上
        #expect(NSPasteboard.general.string(forType: .string) == "second-value")
    }

    @Test @MainActor func pasteStringHandlesEmptyString() {
        _ = NSApplication.shared
        let service = ClipboardService()
        service.pasteString("")
        #expect(NSPasteboard.general.string(forType: .string) == "")
    }

    // MARK: - pasteColorAs: hex format

    @Test @MainActor func pasteColorAsHexForRRGGBB() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#FF5500")
            action.pasteColorAs(clip, format: .hex)
            #expect(NSPasteboard.general.string(forType: .string) == "#FF5500")
        }
    }

    @Test @MainActor func pasteColorAsHexForThreeDigitShorthand() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#F50")
            action.pasteColorAs(clip, format: .hex)
            // #F50 展开为 #FF5500
            #expect(NSPasteboard.general.string(forType: .string) == "#FF5500")
        }
    }

    @Test @MainActor func pasteColorAsHexForPureRed() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#FF0000")
            action.pasteColorAs(clip, format: .hex)
            #expect(NSPasteboard.general.string(forType: .string) == "#FF0000")
        }
    }

    @Test @MainActor func pasteColorAsHexForPureGreen() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#00FF00")
            action.pasteColorAs(clip, format: .hex)
            #expect(NSPasteboard.general.string(forType: .string) == "#00FF00")
        }
    }

    @Test @MainActor func pasteColorAsHexForPureBlue() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#0000FF")
            action.pasteColorAs(clip, format: .hex)
            #expect(NSPasteboard.general.string(forType: .string) == "#0000FF")
        }
    }

    @Test @MainActor func pasteColorAsHexForGray() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#808080")
            action.pasteColorAs(clip, format: .hex)
            #expect(NSPasteboard.general.string(forType: .string) == "#808080")
        }
    }

    // MARK: - pasteColorAs: rgb format

    @Test @MainActor func pasteColorAsRGBForFF5500() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#FF5500")
            action.pasteColorAs(clip, format: .rgb)
            #expect(NSPasteboard.general.string(forType: .string) == "rgb(255, 85, 0)")
        }
    }

    @Test @MainActor func pasteColorAsRGBForPureRed() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#FF0000")
            action.pasteColorAs(clip, format: .rgb)
            #expect(NSPasteboard.general.string(forType: .string) == "rgb(255, 0, 0)")
        }
    }

    @Test @MainActor func pasteColorAsRGBForPureGreen() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#00FF00")
            action.pasteColorAs(clip, format: .rgb)
            #expect(NSPasteboard.general.string(forType: .string) == "rgb(0, 255, 0)")
        }
    }

    @Test @MainActor func pasteColorAsRGBForPureBlue() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#0000FF")
            action.pasteColorAs(clip, format: .rgb)
            #expect(NSPasteboard.general.string(forType: .string) == "rgb(0, 0, 255)")
        }
    }

    @Test @MainActor func pasteColorAsRGBForGray() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#808080")
            action.pasteColorAs(clip, format: .rgb)
            #expect(NSPasteboard.general.string(forType: .string) == "rgb(128, 128, 128)")
        }
    }

    // MARK: - pasteColorAs: hsl format

    @Test @MainActor func pasteColorAsHSLForFF5500() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#FF5500")
            action.pasteColorAs(clip, format: .hsl)
            // r=1.0, g≈0.333, b=0 → hue=20, sat=100%, light=50%
            #expect(NSPasteboard.general.string(forType: .string) == "hsl(20, 100%, 50%)")
        }
    }

    @Test @MainActor func pasteColorAsHSLForPureGreen() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#00FF00")
            action.pasteColorAs(clip, format: .hsl)
            #expect(NSPasteboard.general.string(forType: .string) == "hsl(120, 100%, 50%)")
        }
    }

    @Test @MainActor func pasteColorAsHSLForPureBlue() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#0000FF")
            action.pasteColorAs(clip, format: .hsl)
            #expect(NSPasteboard.general.string(forType: .string) == "hsl(240, 100%, 50%)")
        }
    }

    @Test @MainActor func pasteColorAsHSLForGray() {
        withColorService { action in
            let clip = Clip(kind: .color, text: "#808080")
            action.pasteColorAs(clip, format: .hsl)
            // 灰色：delta=0 → hue=0, sat=0, light=50%
            #expect(NSPasteboard.general.string(forType: .string) == "hsl(0, 0%, 50%)")
        }
    }

    // MARK: - pasteColorAs: edge cases

    @Test @MainActor func pasteColorAsDoesNotPasteWhenColorNotResolvable() {
        withColorService { action in
            NSPasteboard.general.clearContents()
            // rgb() 文本不是 hex，resolvedColorValue 返回 nil → 不调用 pasteString
            let clip = Clip(kind: .color, text: "rgb(255, 0, 0)")
            action.pasteColorAs(clip, format: .hex)
            #expect(NSPasteboard.general.string(forType: .string) == nil)
        }
    }

    @Test @MainActor func pasteColorAsDoesNotPasteWhenTextIsNil() {
        withColorService { action in
            NSPasteboard.general.clearContents()
            let clip = Clip(kind: .color, text: nil)
            action.pasteColorAs(clip, format: .hex)
            #expect(NSPasteboard.general.string(forType: .string) == nil)
        }
    }

    @Test @MainActor func pasteColorAsDoesNotPasteForAllFormatsWhenUnresolvable() {
        withColorService { action in
            for format in ColorPasteFormat.allCases {
                NSPasteboard.general.clearContents()
                let clip = Clip(kind: .color, text: "not-a-color")
                action.pasteColorAs(clip, format: format)
                #expect(NSPasteboard.general.string(forType: .string) == nil,
                        "Format \(format.rawValue) should not paste when color is unresolvable")
            }
        }
    }

    // MARK: - L10n keys for new menu items

    @Test func l10nKeysExistForPasteAsMenu() {
        // 验证新增的 L10n 静态属性返回非空字符串
        #expect(!L10n.menuPasteAs.isEmpty)
        #expect(!L10n.menuHex.isEmpty)
        #expect(!L10n.menuRGB.isEmpty)
        #expect(!L10n.menuHSL.isEmpty)
    }

    // MARK: - Helper

    /// 创建 ClipActionService 并在闭包内保持 ClipboardService 强引用存活。
    /// ClipActionService 持有 ClipboardService 的弱引用，调用方必须保证
    /// ClipboardService 在 action 使用期间不被释放。
    @MainActor private func withColorService<T>(_ body: (ClipActionService) throws -> T) rethrows -> T {
        // pasteToTarget() accesses NSApp.keyWindow; ensure NSApp is initialized.
        _ = NSApplication.shared
        let clipboard = ClipboardService()
        let panelState = PanelState()
        let action = ClipActionService(clipboard: clipboard, panelState: panelState)
        return try withExtendedLifetime(clipboard) {
            try body(action)
        }
    }
}
