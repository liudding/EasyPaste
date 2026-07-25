import SwiftUI

/// Attributed text view (NSTextView wrapper)
struct AttributedTextView: NSViewRepresentable {
    let attributedString: NSAttributedString
    /// 卡片 body 最多显示行数（超出截断），预览浮层不限制。
    let maxLines: Int
    /// 是否允许用户光标选中文本：卡片预览区禁止（避免误选），预览浮层允许复制。
    let isSelectable: Bool

    init(attributedString: NSAttributedString, maxLines: Int = 4, isSelectable: Bool = true) {
        self.attributedString = attributedString
        self.maxLines = maxLines
        self.isSelectable = isSelectable
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        // NSTextView 默认 selectable=true；SwiftUI 的 .textSelection(.disabled) 对 AppKit 视图不生效，
        // 必须在此显式控制。卡片预览区传 isSelectable=false 禁止光标选中。
        textView.isSelectable = isSelectable
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 10)
        textView.textColor = .secondaryLabelColor
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byTruncatingTail
        if maxLines > 0 {
            textView.textContainer?.maximumNumberOfLines = maxLines
        }
        textView.textStorage?.setAttributedString(attributedString)
        return textView
    }
    
    func updateNSView(_ nsView: NSTextView, context: Context) {
        nsView.textStorage?.setAttributedString(attributedString)
    }
}
