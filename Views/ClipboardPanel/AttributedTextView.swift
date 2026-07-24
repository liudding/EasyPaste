import SwiftUI

/// Attributed text view (NSTextView wrapper)
struct AttributedTextView: NSViewRepresentable {
    let attributedString: NSAttributedString
    /// 卡片 body 最多显示行数（超出截断），预览浮层不限制。
    let maxLines: Int
    
    init(attributedString: NSAttributedString, maxLines: Int = 4) {
        self.attributedString = attributedString
        self.maxLines = maxLines
    }
    
    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
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
