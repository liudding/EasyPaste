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

    func makeNSView(context: Context) -> PassthroughTextView {
        let textView = PassthroughTextView()
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
        // 不可选中（卡片 body）时让点击事件穿透到下层视图，使父级卡片的 onTapGesture / onDrag 正常触发；
        // 可选中（预览浮层）时保持默认命中行为以便用户选中/复制。
        textView.hitTestPassthrough = !isSelectable
        return textView
    }

    func updateNSView(_ nsView: PassthroughTextView, context: Context) {
        nsView.textStorage?.setAttributedString(attributedString)
        nsView.hitTestPassthrough = !isSelectable
    }

    /// 报告文本的自然内容尺寸：NSTextView 默认无 intrinsic content size，会被视为 greedy
    /// 而撑满父级提议的全部空间，导致卡片 body 内的 Spacer 失效、内容无法垂直居中。
    /// 这里按可用宽度换行布局后返回实际占用高度，让 SwiftUI 将其视为定高视图。
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PassthroughTextView, context: Context) -> CGSize? {
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

/// NSTextView 子类：当 `hitTestPassthrough` 为 true（卡片 body 中的不可选文本）时，
/// `hitTest` 返回 nil 让鼠标事件穿透到下层视图，使父级卡片的 onTapGesture（选中）/
/// onDrag（拖拽）等手势正常触发——否则 NSTextView 会吞掉 mouseDown 导致点击 body 不选中。
/// `hitTestPassthrough` 为 false（预览浮层中的可选文本）时保持默认行为以便用户选中/复制。
final class PassthroughTextView: NSTextView {
    var hitTestPassthrough: Bool = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitTestPassthrough else { return super.hitTest(point) }
        return nil
    }
}
