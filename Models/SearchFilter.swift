import Foundation
import SwiftUI

/// 日期筛选范围。
enum DateRange: String, CaseIterable, Hashable, Identifiable {
    case today, yesterday, thisWeek, lastWeek, last30Days, last90Days

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: L10n.tr("filter.date.today")
        case .yesterday: L10n.tr("filter.date.yesterday")
        case .thisWeek: L10n.tr("filter.date.this_week")
        case .lastWeek: L10n.tr("filter.date.last_week")
        case .last30Days: L10n.tr("filter.date.last_30_days")
        case .last90Days: L10n.tr("filter.date.last_90_days")
        }
    }

    /// 该范围的起始日期（与当前时间比较）。
    func startDate() -> Date {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .today:
            return cal.startOfDay(for: now)
        case .yesterday:
            return cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: now) ?? now)
        case .thisWeek:
            // 周一作为一周的开始：weekday 1=Sun → 6, 2=Mon → 0, 3=Tue → 1, ...
            let weekday = cal.component(.weekday, from: now)
            let daysToSubtract = (weekday + 5) % 7
            return cal.startOfDay(for: cal.date(byAdding: .day, value: -daysToSubtract, to: now) ?? now)
        case .lastWeek:
            let weekday = cal.component(.weekday, from: now)
            let daysToSubtract = (weekday + 5) % 7
            let thisWeekStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysToSubtract, to: now) ?? now)
            return cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? thisWeekStart
        case .last30Days:
            return cal.date(byAdding: .day, value: -30, to: now) ?? now
        case .last90Days:
            return cal.date(byAdding: .day, value: -90, to: now) ?? now
        }
    }

    /// 判断给定日期是否在该范围内。
    func contains(_ date: Date) -> Bool {
        date >= startDate()
    }
}

/// 搜索筛选条件，以 tag 形式展示在搜索栏中。
/// 分为四个维度：类型 (kind)、来源应用 (app)、看板 (board)、日期范围 (dateRange)。
/// board 维度与 ClipboardStore.selectedBoardID 联动（单选），其余维度支持多选。
enum SearchFilter: Hashable, Identifiable {
    case kind(ClipKind)
    case app(String)
    case board(UUID)
    case dateRange(DateRange)

    var id: String {
        switch self {
        case .kind(let k): return "kind:\(k.rawValue)"
        case .app(let a): return "app:\(a)"
        case .board(let b): return "board:\(b.uuidString)"
        case .dateRange(let d): return "date:\(d.rawValue)"
        }
    }

    /// 分类标签。
    var categoryLabel: String {
        switch self {
        case .kind: L10n.tr("filter.group.type")
        case .app: L10n.tr("filter.group.app")
        case .board: L10n.tr("filter.group.pinboard")
        case .dateRange: L10n.tr("filter.group.date")
        }
    }

    /// 从 boards 解析显示标签。
    func resolveLabel(boards: [Pasteboard]) -> String {
        switch self {
        case .kind(let k): return k.title
        case .app(let a): return a
        case .board(let b): return boards.first(where: { $0.id == b })?.name ?? "?"
        case .dateRange(let d): return d.label
        }
    }

    /// 从 boards 解析 SF Symbol 图标名。
    func resolveIcon(boards: [Pasteboard]) -> String {
        switch self {
        case .kind(let k): return k.symbol
        case .app: return "app"
        case .board: return "pin.fill"
        case .dateRange: return "calendar"
        }
    }

    /// 从 boards 解析颜色（类型 / 看板有专属色）。
    func resolveColor(boards: [Pasteboard]) -> Color? {
        switch self {
        case .kind(let k): return k.defaultColor
        case .app: return nil
        case .board(let b): return boards.first(where: { $0.id == b })?.swiftUIColor
        case .dateRange: return nil
        }
    }
}
