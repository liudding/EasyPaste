import SwiftUI

/// 卡片视口位置的非观察存储：滚动中 preference 逐帧写入此处，但不会触发视图重渲染。
/// Lazy 布局下卡片销毁后，其条目会自动从 preference 聚合结果中消失，无需额外失效校验。
final class ClipFrameStore {
    var frames: [UUID: CGRect] = [:]
}

struct ClipFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
