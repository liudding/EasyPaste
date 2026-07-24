import Foundation
import Observation

/// 面板的瞬时交互状态（选中、搜索展开、预览、重命名、添加 Pinboard 等）。
@Observable @MainActor
final class PanelState {
    var selectedID: UUID?
    var searchExpanded = false
    var searchFocused = false
    var previewItem: Clip?
    var renamingID: UUID?
    var addingBoard = false
    var newBoardName = ""
    var newBoardColor = "orange"
    var targetAppName: String?
    /// 由 PanelView 注入：控制器请求聚焦搜索框时调用。
    var focusSearch: () -> Void = {}
    /// 由 PanelController 注入：请求隐藏面板（粘贴/退出后）。
    var hidePanel: () -> Void = {}
}
