import Foundation

// MARK: - Localization Namespace

/// 多语言本地化命名空间。
/// 翻译数据由 `L10nStore` 从 JSON 文件加载；L10n 提供 `Locale` 枚举和便捷静态属性。
enum L10n {

    // MARK: - Locale

    enum Locale: String, CaseIterable, Identifiable, Hashable {
        case followSystem = "follow_system"
        case simplifiedChinese = "zh-CN"
        case traditionalChinese = "zh-TW"
        case english = "en"
        case japanese = "ja"
        case korean = "ko"
        case french = "fr"
        case spanish = "es"
        case portuguese = "pt"
        case russian = "ru"
        case german = "de"

        var id: String { rawValue }

        /// 各语言自身的原生名称。
        var name: String {
            switch self {
            case .followSystem: return tr("language.follow_system")
            case .simplifiedChinese: return tr("language.simplified_chinese")
            case .traditionalChinese: return tr("language.traditional_chinese")
            case .english: return tr("language.english")
            case .japanese: return tr("language.japanese")
            case .korean: return tr("language.korean")
            case .french: return tr("language.french")
            case .spanish: return tr("language.spanish")
            case .portuguese: return tr("language.portuguese")
            case .russian: return tr("language.russian")
            case .german: return tr("language.german")
            }
        }

        /// BCP-47 语言标签，用于系统 API。
        var languageTag: String {
            switch self {
            case .followSystem: return Foundation.Locale.preferredLanguages.first ?? "en"
            case .simplifiedChinese: return "zh-Hans"
            case .traditionalChinese: return "zh-Hant"
            case .english: return "en"
            case .japanese: return "ja"
            case .korean: return "ko"
            case .french: return "fr"
            case .spanish: return "es"
            case .portuguese: return "pt"
            case .russian: return "ru"
            case .german: return "de"
            }
        }
    }

    // MARK: - Translation (delegates to L10nStore)

    /// 获取指定 key 的翻译字符串。
    /// - Parameter key: 翻译键
    /// - Returns: 当前语言的翻译，或回退到英语，最后回退到 key 自身。
    static func tr(_ key: String) -> String {
        L10nStore.shared.tr(key)
    }

    // MARK: - App

    static var appName: String {
        Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "EasyPaste"
    }

    // MARK: - Menu Bar

    static var showPanel: String { tr("menu.show_panel") }
    static var checkUpdates: String { tr("menu.check_updates") }
    static var settings: String { tr("menu.settings") }
    static var aboutEasyPaste: String { tr("menu.about") }
    static var exitEasyPaste: String { tr("menu.exit") }

    // MARK: - About

    static var aboutTitle: String { tr("about.title") }
    static var aboutDescription: String { tr("about.description") }
    static var aboutButton: String { tr("about.button") }

    // MARK: - Settings Tabs

    static var tabGeneral: String { tr("settings.tab_general") }
    static var tabPrivacy: String { tr("settings.tab_privacy") }
    static var tabShortcuts: String { tr("settings.tab_shortcuts") }
    static var tabUpdates: String { tr("settings.tab_updates") }

    // MARK: - Language

    static var languageSection: String { tr("settings.language_section") }
    static var languageDescription: String { tr("settings.language_description") }

    // MARK: - Theme

    static var themeSection: String { tr("theme.section") }
    static var themeAppearance: String { tr("theme.appearance") }
    static var themeDescription: String { tr("theme.description") }

    // MARK: - Settings General

    static var sectionPanel: String { tr("settings.section_panel") }
    static var panelPosition: String { tr("settings.panel_position") }
    static var sectionGeneral: String { tr("settings.section_general") }
    static var openAtLogin: String { tr("settings.open_at_login") }
    static var icloudSync: String { tr("settings.icloud_sync") }
    static var showInMenuBar: String { tr("settings.show_in_menu_bar") }
    static var menuBarHelp: String { tr("settings.menu_bar_help") }
    static var pasteSound: String { tr("settings.paste_sound") }
    static var copySound: String { tr("settings.copy_sound") }
    static var soundNone: String { tr("settings.sound_none") }
    static var alwaysPastePlainText: String { tr("settings.always_paste_plain_text") }
    static var plainTextPasteOn: String { tr("settings.plain_text_paste_on") }
    static var plainTextPasteOff: String { tr("settings.plain_text_paste_off") }
    static var sectionHistory: String { tr("settings.section_history") }
    static var retentionPeriod: String { tr("settings.retention_period") }
    static var maxRetentionCount: String { tr("settings.max_retention_count") }
    static var clearAllHistory: String { tr("settings.clear_all_history") }
    static var clearConfirmTitle: String { tr("settings.clear_confirm_title") }
    static var clearConfirmAction: String { tr("settings.clear_confirm_action") }
    static var clearConfirmCancel: String { tr("settings.clear_confirm_cancel") }
    static var clearConfirmMessage: String { tr("settings.clear_confirm_message") }

    // MARK: - Settings Privacy

    static var ignoredAppsHeader: String { tr("settings.ignored_apps_header") }
    static var noIgnoredApps: String { tr("settings.no_ignored_apps") }
    static var addApp: String { tr("settings.add_app") }
    static var ignoredAppsFooter: String { tr("settings.ignored_apps_footer") }
    static var selectAppDialogTitle: String { tr("settings.select_app_dialog_title") }

    // MARK: - Settings Shortcuts

    static var invokePanelLabel: String { tr("settings.invoke_panel_label") }
    static var switchBoardShortcutLabel: String { tr("settings.switch_board_shortcut_label") }
    static var tabSwitchBoardLabel: String { tr("settings.tab_switch_board_label") }
    static var tabSwitchBoardHelp: String { tr("settings.tab_switch_board_help") }
    static var shortcutsFooter: String { tr("settings.shortcuts_footer") }
    static var contextMenuShortcutsSection: String { tr("settings.context_menu_shortcuts_section") }
    static var contextMenuShortcutsUniversal: String { tr("settings.context_menu_shortcuts_universal") }
    static var contextMenuShortcutsTypeSpecific: String { tr("settings.context_menu_shortcuts_type_specific") }
    static var shortcutPasteToApp: String { tr("clip.menu.shortcut.paste_to_app") }
    static var shortcutPastePlainText: String { tr("clip.menu.shortcut.paste_plain_text") }
    static var shortcutCopy: String { tr("clip.menu.shortcut.copy") }
    static var shortcutRename: String { tr("clip.menu.shortcut.rename") }
    static var shortcutPreview: String { tr("clip.menu.shortcut.preview") }
    static var shortcutDelete: String { tr("clip.menu.shortcut.delete") }
    static var shortcutExportTxt: String { tr("clip.menu.shortcut.export_txt") }
    static var shortcutExportRtf: String { tr("clip.menu.shortcut.export_rtf") }
    static var shortcutSaveAs: String { tr("clip.menu.shortcut.save_as") }
    static var shortcutQrCode: String { tr("clip.menu.shortcut.qr_code") }
    static var shortcutSendEmail: String { tr("clip.menu.shortcut.send_email") }
    static var shortcutJsonPreview: String { tr("clip.menu.shortcut.json_preview") }
    static var shortcutOpenLink: String { tr("clip.menu.shortcut.open_link") }
    static var shortcutConflictWarning: String { tr("settings.shortcut_conflict_warning") }

    // MARK: - Settings Updates

    static var autoUpdate: String { tr("settings.auto_update") }
    static var updateEngine: String { tr("settings.update_engine") }
    static var checkUpdatesButton: String { tr("settings.check_updates_button") }
    static var currentVersion: String { tr("settings.current_version") }
    static var unknownVersion: String { tr("settings.unknown_version") }
    static var updateEngineEnabled: String { tr("settings.update_engine_enabled") }
    static var updateEngineDevMode: String { tr("settings.update_engine_dev_mode") }
    static var releaseNotesSection: String { tr("settings.release_notes_section") }
    static var releaseNotesPlaceholder: String { tr("settings.release_notes_placeholder") }
    static var updateConfigSection: String { tr("settings.update_config_section") }
    static var updateConfigText: String { tr("settings.update_config_text") }

    // MARK: - Panel Header

    static var clipboardTitle: String { tr("panel.clipboard_title") }
    static var allBoards: String { tr("panel.all_boards") }
    static var searchPlaceholder: String { tr("panel.search_placeholder") }
    static var newBoardPlaceholder: String { tr("panel.new_board_placeholder") }
    static var addBoardConfirm: String { tr("panel.add_board_confirm") }
    static var boardColor: String { tr("panel.board_color") }
    static var deleteBoardTitle: String { tr("panel.delete_board_title") }
    static var deleteBoardMessage: String { tr("panel.delete_board_message") }
    static var deleteBoardOnly: String { tr("panel.delete_board_only") }
    static var deleteBoardAll: String { tr("panel.delete_board_all") }
    static var cancel: String { tr("panel.cancel") }
    static var soundOn: String { tr("panel.sound_on") }
    static var soundOff: String { tr("panel.sound_off") }

    // MARK: - Clip Card

    static var pasteToApp: String { tr("clip.paste_to_app") }
    static var pastePlainText: String { tr("clip.paste_plain_text") }
    static var copyAction: String { tr("clip.copy") }
    static var rename: String { tr("clip.rename") }
    static var pinTo: String { tr("clip.pin_to") }
    static var unpin: String { tr("clip.unpin") }
    static var preview: String { tr("clip.preview") }
    static var delete: String { tr("clip.delete") }
    static var cannotPreview: String { tr("clip.cannot_preview") }
    static var characters: String { tr("clip.count_suffix") }

    // MARK: - Time Ago

    static var justNow: String { tr("time.just_now") }
    static var minutesAgo: String { tr("time.minutes_ago") }
    static var hoursAgo: String { tr("time.hours_ago") }
    static var daysAgo: String { tr("time.days_ago") }
    static var weeksAgo: String { tr("time.weeks_ago") }
    static var monthsAgo: String { tr("time.months_ago") }
    static var yearsAgo: String { tr("time.years_ago") }

    // MARK: - Panel View

    static var emptyState: String { tr("panel.empty_state") }
    static var previewCloseHint: String { tr("panel.preview_close_hint") }

    // MARK: - Shortcut Recorder

    static var shortcutRecording: String { tr("shortcut.recording") }

    // MARK: - Keyboard Keys

    /// 空格键的本地化名称。
    static var spaceKey: String { tr("space_key") }
    /// 上下文菜单预览提示键。
    static var previewHint: String { tr("preview_hint") }

    // MARK: - Clip Menu (type-specific)

    static var menuExportTxt: String { tr("clip.menu.export_txt") }
    static var menuExportRtf: String { tr("clip.menu.export_rtf") }
    static var menuQRCode: String { tr("clip.menu.qr_code") }
    static var menuSaveAs: String { tr("clip.menu.save_as") }
    static var menuSendEmail: String { tr("clip.menu.send_email") }
    static var menuPasteAs: String { tr("clip.menu.paste_as") }
    static var menuHex: String { tr("clip.menu.hex") }
    static var menuRGB: String { tr("clip.menu.rgb") }
    static var menuHSL: String { tr("clip.menu.hsl") }
    static var menuOpenLink: String { tr("clip.menu.open_link") }
    static var menuJSONPreview: String { tr("clip.menu.json_preview") }

    // MARK: - Settings (hide dock icon)

    static var hideDockIconSetting: String { tr("settings.hide_dock_icon") }
    static var hideDockIconHelp: String { tr("settings.hide_dock_icon_help") }

    // MARK: - Preview (errors/warnings)

    static var jsonError: String { tr("clip.preview.json_error") }
    static var qrTooLong: String { tr("clip.preview.qr_too_long") }

    // MARK: - Default Boards

    static var defaultBoardIdeas: String { tr("default_board.ideas") }
    static var defaultBoardWork: String { tr("default_board.work") }

    // MARK: - Onboarding

    static var onboardingWelcomeTitle: String { tr("onboarding.welcome_title") }
    static var onboardingWelcomeDesc: String { tr("onboarding.welcome_desc") }
    static var onboardingAutoCaptureTitle: String { tr("onboarding.auto_capture_title") }
    static var onboardingAutoCaptureDesc: String { tr("onboarding.auto_capture_desc") }
    static var onboardingQuickAccessTitle: String { tr("onboarding.quick_access_title") }
    static var onboardingQuickAccessDesc: String { tr("onboarding.quick_access_desc") }
    static var onboardingOrganizationTitle: String { tr("onboarding.organization_title") }
    static var onboardingOrganizationDesc: String { tr("onboarding.organization_desc") }
    static var onboardingSearchPreviewTitle: String { tr("onboarding.search_preview_title") }
    static var onboardingSearchPreviewDesc: String { tr("onboarding.search_preview_desc") }
    static var onboardingReadyTitle: String { tr("onboarding.ready_title") }
    static var onboardingReadyDesc: String { tr("onboarding.ready_desc") }
    static var onboardingStartUsing: String { tr("onboarding.start_using") }
    static var onboardingNext: String { tr("onboarding.next") }
    static var onboardingPrevious: String { tr("onboarding.previous") }
}
