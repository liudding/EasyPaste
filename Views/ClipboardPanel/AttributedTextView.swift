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

    /// 报告文本的自然内容尺寸：NSTextView 默认无 intrinsic content size，会被视为 greedy
    /// 而撑满父级提议的全部空间，导致卡片 body 内的 Spacer 失效、内容无法垂直居中。
    /// 这里按可用宽度换行布局后返回实际占用高度，让 SwiftUI 将其视为定高视图。
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        guard let layoutManager = nsView.layoutManager,
              let textContainer = nsView.textContainer else { return nil }
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0 else { return nil }
        // 限定容器宽度让文本按可用宽度换行；高度不限，由布局结果决定。
        textContainer.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: width, height: ceil(usedRect.height))
    }
}
