import Foundation

// MARK: - Localization System

enum L10n {
    
    // MARK: - Locale
    
    enum Locale: String, CaseIterable, Identifiable, Hashable {
        /// 跟随系统（默认）
        case followSystem = "follow_system"
        /// 简体中文
        case simplifiedChinese = "zh-CN"
        /// 繁体中文
        case traditionalChinese = "zh-TW"
        /// 英文
        case english = "en"
        
        var id: String { rawValue }
        
        var name: String {
            switch self {
            case .followSystem: L10n.tr("language.follow_system")
            case .simplifiedChinese: L10n.tr("language.simplified_chinese")
            case .traditionalChinese: L10n.tr("language.traditional_chinese")
            case .english: L10n.tr("language.english")
            }
        }
        
        /// 返回该语言对应的语言标签，用于 Bundle 查找
        var languageTag: String {
            switch self {
            case .followSystem: Foundation.Locale.preferredLanguages.first ?? "en"
            case .simplifiedChinese: "zh-Hans"
            case .traditionalChinese: "zh-Hant"
            case .english: "en"
            }
        }
    }
    
    // MARK: - Current Locale
    
    private static let userDefaultKey = "EasyPasteLocale"
    
    static var current: Locale {
        get {
            if let saved = UserDefaults.standard.string(forKey: userDefaultKey),
               let locale = Locale(rawValue: saved) {
                return locale
            }
            return .followSystem
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultKey)
        }
    }
    
    /// 获取当前生效的语言标签（resolve followSystem → actual system language）
    static var effectiveLanguageTag: String {
        switch current {
        case .followSystem:
            return Foundation.Locale.preferredLanguages.first ?? "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        case .english:
            return "en"
        }
    }
    
    // MARK: - Localization Function
    
    static func tr(_ key: String) -> String {
        let bundle = Bundle.main
        
        // 尝试从 Localizable.strings 获取（标准方式）
        let localized = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        if localized != key { return localized }
        
        // fallback 到代码中的字典
        return strings[key]?[effectiveLocale] ?? key
    }
    
    /// 根据当前设置解析出实际使用的 Locale
    private static var effectiveLocale: Locale {
        switch current {
        case .followSystem:
            let systemLang = Foundation.Locale.preferredLanguages.first?.prefix(2) ?? "en"
            if systemLang == "zh" {
                // 进一步区分简繁
                let region = Foundation.Locale.current.region?.identifier
                if region == "TW" || region == "HK" { return .traditionalChinese }
                return .simplifiedChinese
            }
            return .english
        case .simplifiedChinese: return .simplifiedChinese
        case .traditionalChinese: return .traditionalChinese
        case .english: return .english
        }
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
    
    // MARK: - Settings Updates
    
    static var autoUpdate: String { tr("settings.auto_update") }
    static var updateEngine: String { tr("settings.update_engine") }
    
    // MARK: - Settings General
    
    static var sectionPanel: String { tr("settings.section_panel") }
    static var panelPosition: String { tr("settings.panel_position") }
    static var sectionGeneral: String { tr("settings.section_general") }
    static var openAtLogin: String { tr("settings.open_at_login") }
    static var icloudSync: String { tr("settings.icloud_sync") }
    static var showInMenuBar: String { tr("settings.show_in_menu_bar") }
    static var pasteSound: String { tr("settings.paste_sound") }
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
    static var shortcutsFooter: String { tr("settings.shortcuts_footer") }
    
    // MARK: - Settings Updates
    
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
    
    // MARK: - Internal Strings Dictionary (fallback)
    
    private static let strings: [String: [Locale: String]] = [
        // Menu Bar
        "menu.show_panel": [.english: "Show Panel", .simplifiedChinese: "显示面板", .traditionalChinese: "顯示面板"],
        "menu.check_updates": [.english: "Check for Updates…", .simplifiedChinese: "检查更新…", .traditionalChinese: "檢查更新…"],
        "menu.settings": [.english: "Settings…", .simplifiedChinese: "设置…", .traditionalChinese: "設置…"],
        "menu.about": [.english: "About EasyPaste", .simplifiedChinese: "关于 EasyPaste", .traditionalChinese: "關於 EasyPaste"],
        "menu.exit": [.english: "Quit EasyPaste", .simplifiedChinese: "退出 EasyPaste", .traditionalChinese: "退出 EasyPaste"],
        
        // About
        "about.title": [.english: "EasyPaste", .simplifiedChinese: "EasyPaste", .traditionalChinese: "EasyPaste"],
        "about.description": [.english: "Version 1.0\n\n⌘⇧V to open the clipboard panel, double-click or Enter to paste into the previous app.", .simplifiedChinese: "版本 1.0\n\n⌘⇧V 唤起剪贴板面板，双击或回车粘贴到之前的应用。", .traditionalChinese: "版本 1.0\n\n⌘⇧V 喚起剪貼板面板，雙擊或回車粘貼到之前的應用。"],
        "about.button": [.english: "OK", .simplifiedChinese: "好", .traditionalChinese: "好"],
        
        // Settings Tabs
        "settings.tab_general": [.english: "General", .simplifiedChinese: "通用", .traditionalChinese: "通用"],
        "settings.tab_privacy": [.english: "Privacy", .simplifiedChinese: "隐私", .traditionalChinese: "隱私"],
        "settings.tab_shortcuts": [.english: "Shortcuts", .simplifiedChinese: "快捷键", .traditionalChinese: "快捷鍵"],
        "settings.tab_updates": [.english: "Updates", .simplifiedChinese: "更新", .traditionalChinese: "更新"],
        
        // Language
        "settings.language_section": [.english: "Language", .simplifiedChinese: "语言", .traditionalChinese: "語言"],
        "settings.language_description": [.english: "Restart the app for changes to take effect.", .simplifiedChinese: "重启应用后生效。", .traditionalChinese: "重新啟動應用後生效。"],
        
        // Language Names
        "language.follow_system": [.english: "Follow System", .simplifiedChinese: "跟随系统", .traditionalChinese: "跟隨系統"],
        "language.simplified_chinese": [.english: "简体中文", .simplifiedChinese: "简体中文", .traditionalChinese: "簡體中文"],
        "language.traditional_chinese": [.english: "繁體中文", .simplifiedChinese: "繁體中文", .traditionalChinese: "繁體中文"],
        "language.english": [.english: "English", .simplifiedChinese: "English", .traditionalChinese: "English"],
        
        // Settings General
        "settings.section_panel": [.english: "Panel", .simplifiedChinese: "面板", .traditionalChinese: "面板"],
        "settings.panel_position": [.english: "Panel Position", .simplifiedChinese: "面板位置", .traditionalChinese: "面板位置"],
        "settings.section_general": [.english: "General", .simplifiedChinese: "通用", .traditionalChinese: "通用"],
        "settings.open_at_login": [.english: "Open at Login", .simplifiedChinese: "登录时打开", .traditionalChinese: "登錄時打開"],
        "settings.icloud_sync": [.english: "iCloud Sync Clipboard History", .simplifiedChinese: "iCloud 同步剪贴板历史", .traditionalChinese: "iCloud 同步剪貼板歷史"],
        "settings.show_in_menu_bar": [.english: "Show in Menu Bar", .simplifiedChinese: "在菜单栏显示", .traditionalChinese: "在菜單欄顯示"],
        "settings.paste_sound": [.english: "Paste Sound", .simplifiedChinese: "粘贴音效", .traditionalChinese: "粘貼音效"],
        "settings.sound_none": [.english: "None", .simplifiedChinese: "无", .traditionalChinese: "無"],
        "settings.always_paste_plain_text": [.english: "Always Paste as Plain Text", .simplifiedChinese: "始终以纯文本粘贴", .traditionalChinese: "始終以純文本粘貼"],
        "settings.plain_text_paste_on": [.english: "Plain text paste enabled", .simplifiedChinese: "纯文本粘贴已开启", .traditionalChinese: "純文本粘貼已開啟"],
        "settings.plain_text_paste_off": [.english: "Plain text paste disabled", .simplifiedChinese: "纯文本粘贴已关闭", .traditionalChinese: "純文本粘貼已關閉"],
        "settings.section_history": [.english: "History", .simplifiedChinese: "历史", .traditionalChinese: "歷史"],
        "settings.retention_period": [.english: "Retention Period", .simplifiedChinese: "保留时长", .traditionalChinese: "保留時長"],
        "settings.max_retention_count": [.english: "Max Retention Count", .simplifiedChinese: "最大保留条数", .traditionalChinese: "最大保留條數"],
        "settings.clear_all_history": [.english: "Clear All History…", .simplifiedChinese: "清除全部历史…", .traditionalChinese: "清除全部歷史…"],
        "settings.clear_confirm_title": [.english: "Clear All Clipboard History?", .simplifiedChinese: "清除全部剪贴板历史？", .traditionalChinese: "清除全部剪貼板歷史？"],
        "settings.clear_confirm_action": [.english: "Clear", .simplifiedChinese: "清除", .traditionalChinese: "清除"],
        "settings.clear_confirm_cancel": [.english: "Cancel", .simplifiedChinese: "取消", .traditionalChinese: "取消"],
        "settings.clear_confirm_message": [.english: "This action cannot be undone.", .simplifiedChinese: "此操作不可撤销。", .traditionalChinese: "此操作不可撤銷。"],
        
        // Settings Privacy
        "settings.ignored_apps_header": [.english: "Ignore clipboard content from these apps", .simplifiedChinese: "忽略以下 App 的剪贴板内容", .traditionalChinese: "忽略以下 App 的剪貼板內容"],
        "settings.no_ignored_apps": [.english: "No ignored apps", .simplifiedChinese: "没有忽略的 App", .traditionalChinese: "沒有忽略的 App"],
        "settings.add_app": [.english: "Add App…", .simplifiedChinese: "添加 App…", .traditionalChinese: "添加 App…"],
        "settings.ignored_apps_footer": [.english: "Clipboard content copied within these apps will not be saved to history.", .simplifiedChinese: "在这些 App 中拷贝的内容不会保存到历史。", .traditionalChinese: "在這些 App 中拷貝的內容不會保存到歷史。"],
        "settings.select_app_dialog_title": [.english: "Select App to Ignore", .simplifiedChinese: "选择要忽略的应用", .traditionalChinese: "選擇要忽略的應用"],
        
        // Settings Shortcuts
        "settings.invoke_panel_label": [.english: "Invoke Panel", .simplifiedChinese: "唤起面板", .traditionalChinese: "喚起面板"],
        "settings.switch_board_shortcut_label": [.english: "Switch Pinboard (in panel)", .simplifiedChinese: "切换 Pinboard（面板内）", .traditionalChinese: "切換 Pinboard（面板內）"],
        "settings.shortcuts_footer": [.english: "Press a new shortcut after clicking the button on the right. Esc to cancel. Changes take effect immediately.", .simplifiedChinese: "点击右侧按钮后按下新的快捷键，Esc 取消。修改立即生效。", .traditionalChinese: "點擊右側按鈕後按下新的快捷鍵，Esc 取消。修改立即生效。"],
        
        // Settings Updates
        "settings.check_updates_button": [.english: "Check for Updates…", .simplifiedChinese: "检查更新…", .traditionalChinese: "檢查更新…"],
        "settings.current_version": [.english: "Current Version", .simplifiedChinese: "当前版本", .traditionalChinese: "當前版本"],
        "settings.unknown_version": [.english: "Unknown", .simplifiedChinese: "未知", .traditionalChinese: "未知"],
        "settings.update_engine_enabled": [.english: "Sparkle Enabled", .simplifiedChinese: "Sparkle 已启用", .traditionalChinese: "Sparkle 已啟用"],
        "settings.update_engine_dev_mode": [.english: "Development Mode Only (requires Xcode build)", .simplifiedChinese: "仅开发模式（需 Xcode 构建）", .traditionalChinese: "僅開發模式（需 Xcode 構建）"],
        "settings.release_notes_section": [.english: "Release Notes", .simplifiedChinese: "更新说明", .traditionalChinese: "更新說明"],
        "settings.release_notes_placeholder": [.english: "Release notes for new versions will appear here.", .simplifiedChinese: "新版本将在此处显示更新说明。", .traditionalChinese: "新版本將在此處顯示更新說明。"],
        "settings.update_config_section": [.english: "Configuration", .simplifiedChinese: "配置", .traditionalChinese: "配置"],
        "settings.update_config_text": [.english: "After deploying appcast.xml, uncomment SUFeedURL and SUPublicEDKey in Info.plist to enable auto-updates.", .simplifiedChinese: "部署 appcast.xml 后，取消 Info.plist 中 SUFeedURL 和 SUPublicEDKey 的注释即可启用自动更新。", .traditionalChinese: "部署 appcast.xml 後，取消 Info.plist 中 SUFeedURL 和 SUPublicEDKey 的註解即可啟用自動更新。"],
        "settings.auto_update": [.english: "Auto Update", .simplifiedChinese: "自动更新", .traditionalChinese: "自動更新"],
        "settings.update_engine": [.english: "Update Engine", .simplifiedChinese: "更新引擎", .traditionalChinese: "更新引擎"],
        
        // Panel
        "panel.clipboard_title": [.english: "Clipboard", .simplifiedChinese: "剪贴板", .traditionalChinese: "剪貼板"],
        "panel.all_boards": [.english: "All", .simplifiedChinese: "全部", .traditionalChinese: "全部"],
        "panel.search_placeholder": [.english: "Search clipboard", .simplifiedChinese: "搜索剪贴板", .traditionalChinese: "搜索剪貼板"],
        "panel.new_board_placeholder": [.english: "New Board", .simplifiedChinese: "新 Board", .traditionalChinese: "新 Board"],
        "panel.add_board_confirm": [.english: "OK", .simplifiedChinese: "确定", .traditionalChinese: "確定"],
        "panel.sound_on": [.english: "Sound enabled", .simplifiedChinese: "音效已开启", .traditionalChinese: "音效已開啟"],
        "panel.sound_off": [.english: "Sound disabled", .simplifiedChinese: "音效已关闭", .traditionalChinese: "音效已關閉"],
        
        // Clip Card
        "clip.paste_to_app": [.english: "Paste to %@", .simplifiedChinese: "粘贴到 %@", .traditionalChinese: "粘貼到 %@"],
        "clip.paste_plain_text": [.english: "Paste as Plain Text", .simplifiedChinese: "以纯文本粘贴", .traditionalChinese: "以純文本粘貼"],
        "clip.copy": [.english: "Copy", .simplifiedChinese: "拷贝", .traditionalChinese: "拷貝"],
        "clip.rename": [.english: "Rename…", .simplifiedChinese: "重命名…", .traditionalChinese: "重命名…"],
        "clip.pin_to": [.english: "Pin to", .simplifiedChinese: "固定到", .traditionalChinese: "固定到"],
        "clip.unpin": [.english: "Unpin", .simplifiedChinese: "取消固定", .traditionalChinese: "取消固定"],
        "clip.preview": [.english: "Preview", .simplifiedChinese: "预览", .traditionalChinese: "預覽"],
        "clip.delete": [.english: "Delete", .simplifiedChinese: "删除", .traditionalChinese: "刪除"],
        "clip.cannot_preview": [.english: "Cannot preview", .simplifiedChinese: "无法预览", .traditionalChinese: "無法預覽"],
        "clip.count_suffix": [.english: " chars", .simplifiedChinese: " 字符", .traditionalChinese: " 字符"],
        
        // Panel View
        "panel.empty_state": [.english: "No clipboard content", .simplifiedChinese: "暂无剪贴内容", .traditionalChinese: "暫無剪貼內容"],
        "panel.preview_close_hint": [.english: "Space / Esc to close", .simplifiedChinese: "空格 / Esc 关闭", .traditionalChinese: "空格 / Esc 關閉"],
        
        // Onboarding
        "onboarding.welcome_title": [.english: "Welcome to EasyPaste", .simplifiedChinese: "欢迎使用 EasyPaste", .traditionalChinese: "歡迎使用 EasyPaste"],
        "onboarding.welcome_desc": [.english: "Your smart clipboard assistant.\nAuto-save, quick paste, smart organization —\nevery copy keeps things tidy.", .simplifiedChinese: "你的智能剪贴板助手。\n自动保存、快速粘贴、智能整理——\n让每一次复制都井井有条。", .traditionalChinese: "你的智能剪貼板助手。\n自動保存、快速粘貼、智能整理——\n讓每一次複製都井井有條。"],
        "onboarding.auto_capture_title": [.english: "Auto Capture", .simplifiedChinese: "自动捕获", .traditionalChinese: "自動捕獲"],
        "onboarding.auto_capture_desc": [.english: "Everything you copy is automatically saved by EasyPaste.", .simplifiedChinese: "一切你拷贝的内容，EasyPaste 都会自动保存。", .traditionalChinese: "一切你拷貝的內容，EasyPaste 都會自動保存。"],
        "onboarding.quick_access_title": [.english: "One-Tap Access", .simplifiedChinese: "一键唤起", .traditionalChinese: "一鍵喚起"],
        "onboarding.quick_access_desc": [.english: "Press the shortcut anytime,\nand the clipboard panel slides out from the screen edge.", .simplifiedChinese: "随时随地按下快捷键，\n剪贴板面板即刻从屏幕边缘滑出。", .traditionalChinese: "隨時隨地按下快捷鍵，\n剪貼板面板即刻從屏幕邊緣滑出。"],
        "onboarding.organization_title": [.english: "Smart Organization", .simplifiedChinese: "智能整理", .traditionalChinese: "智能整理"],
        "onboarding.organization_desc": [.english: "Organize your clipboard content with Pinboards.\nIdeas, work, code — each in its place.", .simplifiedChinese: "用 Pinboard 分类整理你的剪贴内容，\n灵感、工作、代码……各归其位。", .traditionalChinese: "用 Pinboard 分類整理你的剪貼內容，\n靈感、工作、代碼……各歸其位。"],
        "onboarding.search_preview_title": [.english: "Search & Preview", .simplifiedChinese: "搜索与预览", .traditionalChinese: "搜索與預覽"],
        "onboarding.search_preview_desc": [.english: "Type directly in the panel to search.\nPress Space to preview any item.", .simplifiedChinese: "面板打开后直接打字即可搜索，\n按空格键预览任意内容。", .traditionalChinese: "面板打開後直接打字即可搜索，\n按空格鍵預覽任意內容。"],
        "onboarding.ready_title": [.english: "Ready to Go", .simplifiedChinese: "准备就绪", .traditionalChinese: "準備就緒"],
        "onboarding.ready_desc": [.english: "EasyPaste is ready.\nCopy some text and try it —\nthen press ⌘⇧V to open the panel.", .simplifiedChinese: "EasyPaste 已就绪。\n复制一段文字试试吧——\n然后按 ⌘⇧V 唤出面板。", .traditionalChinese: "EasyPaste 已就緒。\n複製一段文字試試吧——\n然後按 ⌘⇧V 喚出面板。"],
        "onboarding.start_using": [.english: "Get Started", .simplifiedChinese: "开始使用", .traditionalChinese: "開始使用"],
        "onboarding.next": [.english: "Next", .simplifiedChinese: "下一步", .traditionalChinese: "下一步"],
        "onboarding.previous": [.english: "Previous", .simplifiedChinese: "上一步", .traditionalChinese: "上一步"],
        
        // Onboarding Features
        "onboarding.feature_auto_save": [.english: "Auto-saves clipboard history", .simplifiedChinese: "自动记录剪贴板历史", .traditionalChinese: "自動記錄剪貼板歷史"],
        "onboarding.feature_cross_app": [.english: "Quick paste across apps", .simplifiedChinese: "跨应用快速粘贴", .traditionalChinese: "跨應用快速粘貼"],
        "onboarding.feature_smart_org": [.english: "Smart categorization & search", .simplifiedChinese: "智能分类与搜索", .traditionalChinese: "智能分類與搜索"],
        "onboarding.feature_types": [.english: "Text, links, images, files, color values", .simplifiedChinese: "文本、链接、图片、文件、色值", .traditionalChinese: "文本、鏈接、圖片、文件、色值"],
        "onboarding.feature_source_app": [.english: "Records source application", .simplifiedChinese: "记录内容来源应用", .traditionalChinese: "記錄內容來源應用"],
        "onboarding.feature_ignore_apps": [.english: "Ignore sensitive apps in Privacy settings", .simplifiedChinese: "可在隐私设置中忽略敏感应用", .traditionalChinese: "可在隱私設置中忽略敏感應用"],
        "onboarding.feature_arrow_keys": [.english: "Arrow keys to select, Enter to paste", .simplifiedChinese: "方向键选择，回车粘贴到当前应用", .traditionalChinese: "方向鍵選擇，回車粘貼到當前應用"],
        "onboarding.feature_shift_enter": [.english: "⇧Enter to paste as plain text", .simplifiedChinese: "⇧回车以纯文本粘贴", .traditionalChinese: "⇧回車以純文本粘貼"],
        "onboarding.feature_cmd_c": [.english: "⌘C to re-copy to clipboard", .simplifiedChinese: "⌘C 重新拷贝到剪贴板", .traditionalChinese: "⌘C 重新拷貝到剪貼板"],
        "onboarding.feature_drag_drop": [.english: "Drag cards between Pinboards", .simplifiedChinese: "拖拽卡片到不同 Pinboard", .traditionalChinese: "拖拽卡片到不同 Pinboard"],
        "onboarding.feature_custom_boards": [.english: "Custom Pinboard names and colors", .simplifiedChinese: "自定义 Pinboard 名称和颜色", .traditionalChinese: "自定義 Pinboard 名稱和顏色"],
        "onboarding.feature_filter_by_board": [.english: "Filter content by Pinboard in panel", .simplifiedChinese: "面板内按 Pinboard 筛选内容", .traditionalChinese: "面板內按 Pinboard 篩選內容"],
        "onboarding.feature_type_search": [.english: "Type directly in panel to search", .simplifiedChinese: "面板内直接输入即开始搜索", .traditionalChinese: "面板內直接輸入即開始搜索"],
        "onboarding.feature_space_preview": [.english: "Space to preview text/image/link", .simplifiedChinese: "空格键查看文本/图片/链接预览", .traditionalChinese: "空格鍵查看文本/圖片/鏈接預覽"],
        "onboarding.feature_double_click_paste": [.english: "Double-click card to paste directly", .simplifiedChinese: "双击卡片直接粘贴", .traditionalChinese: "雙擊卡片直接粘貼"],
        "onboarding.hint_invoke_panel": [.english: "Open Panel", .simplifiedChinese: "唤起面板", .traditionalChinese: "喚起面板"],
        "onboarding.hint_preview": [.english: "Preview", .simplifiedChinese: "预览", .traditionalChinese: "預覽"],
        "onboarding.hint_type_search": [.english: "Type to Search", .simplifiedChinese: "输入即搜索", .traditionalChinese: "輸入即搜索"],
        
        // History Step Labels
        "history.1d": [.english: "1 day", .simplifiedChinese: "1 天", .traditionalChinese: "1 天"],
        "history.2d": [.english: "2 days", .simplifiedChinese: "2 天", .traditionalChinese: "2 天"],
        "history.3d": [.english: "3 days", .simplifiedChinese: "3 天", .traditionalChinese: "3 天"],
        "history.4d": [.english: "4 days", .simplifiedChinese: "4 天", .traditionalChinese: "4 天"],
        "history.5d": [.english: "5 days", .simplifiedChinese: "5 天", .traditionalChinese: "5 天"],
        "history.6d": [.english: "6 days", .simplifiedChinese: "6 天", .traditionalChinese: "6 天"],
        "history.1w": [.english: "1 week", .simplifiedChinese: "1 周", .traditionalChinese: "1 周"],
        "history.2w": [.english: "2 weeks", .simplifiedChinese: "2 周", .traditionalChinese: "2 周"],
        "history.3w": [.english: "3 weeks", .simplifiedChinese: "3 周", .traditionalChinese: "3 周"],
        "history.1mo": [.english: "1 month", .simplifiedChinese: "1 个月", .traditionalChinese: "1 個月"],
        "history.2mo": [.english: "2 months", .simplifiedChinese: "2 个月", .traditionalChinese: "2 個月"],
        "history.3mo": [.english: "3 months", .simplifiedChinese: "3 个月", .traditionalChinese: "3 個月"],
        "history.4mo": [.english: "4 months", .simplifiedChinese: "4 个月", .traditionalChinese: "4 個月"],
        "history.5mo": [.english: "5 months", .simplifiedChinese: "5 个月", .traditionalChinese: "5 個月"],
        "history.6mo": [.english: "6 months", .simplifiedChinese: "6 个月", .traditionalChinese: "6 個月"],
        "history.7mo": [.english: "7 months", .simplifiedChinese: "7 个月", .traditionalChinese: "7 個月"],
        "history.8mo": [.english: "8 months", .simplifiedChinese: "8 个月", .traditionalChinese: "8 個月"],
        "history.9mo": [.english: "9 months", .simplifiedChinese: "9 个月", .traditionalChinese: "9 個月"],
        "history.10mo": [.english: "10 months", .simplifiedChinese: "10 个月", .traditionalChinese: "10 個月"],
        "history.11mo": [.english: "11 months", .simplifiedChinese: "11 个月", .traditionalChinese: "11 個月"],
        "history.1y": [.english: "1 year", .simplifiedChinese: "1 年", .traditionalChinese: "1 年"],
        "history.unlimited": [.english: "Unlimited", .simplifiedChinese: "无限", .traditionalChinese: "無限"],
        
        // Panel Position
        "settings.position_bottom": [.english: "Bottom", .simplifiedChinese: "底部", .traditionalChinese: "底部"],
        "settings.position_top": [.english: "Top", .simplifiedChinese: "顶部", .traditionalChinese: "頂部"],
        "settings.position_left": [.english: "Left", .simplifiedChinese: "左侧", .traditionalChinese: "左側"],
        "settings.position_right": [.english: "Right", .simplifiedChinese: "右侧", .traditionalChinese: "右側"],
        
        // Max Items
        "settings.max_items_limited": [.english: "Limited", .simplifiedChinese: "限制", .traditionalChinese: "限制"],
        "settings.max_items_unlimited": [.english: "Unlimited", .simplifiedChinese: "无限", .traditionalChinese: "無限"],
        
        // Privacy
        "privacy.keychain_access": [.english: "Keychain Access", .simplifiedChinese: "钥匙串访问", .traditionalChinese: "鑰匙串訪問"],
        "privacy.passwords": [.english: "Passwords", .simplifiedChinese: "密码", .traditionalChinese: "密碼"],
        
        // Clip Kind Titles (used in Clip.swift)
        "clip.kind.text": [.english: "Text", .simplifiedChinese: "文本", .traditionalChinese: "文本"],
        "clip.kind.link": [.english: "Link", .simplifiedChinese: "链接", .traditionalChinese: "鏈接"],
        "clip.kind.image": [.english: "Image", .simplifiedChinese: "图片", .traditionalChinese: "圖片"],
        "clip.kind.file": [.english: "File", .simplifiedChinese: "文件", .traditionalChinese: "文件"],
        "clip.kind.color": [.english: "Color", .simplifiedChinese: "颜色", .traditionalChinese: "顏色"],
        "clip.default_text": [.english: "Text", .simplifiedChinese: "文本", .traditionalChinese: "文本"],
        "clip.default_link": [.english: "Link", .simplifiedChinese: "链接", .traditionalChinese: "鏈接"],
        "clip.default_image": [.english: "Image", .simplifiedChinese: "图片", .traditionalChinese: "圖片"],
        "clip.default_file": [.english: "File", .simplifiedChinese: "文件", .traditionalChinese: "文件"],
        "clip.default_color": [.english: "Color", .simplifiedChinese: "颜色", .traditionalChinese: "顏色"],
        "clip.files_count": [.english: "%d files", .simplifiedChinese: "%d 个文件", .traditionalChinese: "%d 個文件"],
        
        // Time Ago
        "time.just_now": [.english: "just now", .simplifiedChinese: "刚刚", .traditionalChinese: "剛剛"],
        "time.minutes_ago": [.english: " min ago", .simplifiedChinese: " 分钟前", .traditionalChinese: " 分鐘前"],
        "time.hours_ago": [.english: " hr ago", .simplifiedChinese: " 小时前", .traditionalChinese: " 小時前"],
        "time.days_ago": [.english: " day ago", .simplifiedChinese: " 天前", .traditionalChinese: " 天前"],
        "time.weeks_ago": [.english: " week ago", .simplifiedChinese: " 周前", .traditionalChinese: " 周前"],
        "time.months_ago": [.english: " month ago", .simplifiedChinese: " 月前", .traditionalChinese: " 月前"],
        "time.years_ago": [.english: " year ago", .simplifiedChinese: " 年前", .traditionalChinese: " 年前"],
    ]
}
