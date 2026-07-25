import SwiftUI

// MARK: - Onboarding View

/// 首次启动引导，按页展示 EasyPaste 的核心功能。
struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var currentPage = 0
    @State private var direction: Int = 1  // 1 = forward, -1 = backward

    private let pages: [OnboardingPage] = [
        .welcome,
        .autoCapture,
        .quickAccess,
        .organization,
        .searchPreview,
        .ready
    ]

    var body: some View {
        ZStack {
            // 背景
            backgroundGradient

            VStack(spacing: 0) {
                // 页面内容（macOS 不支持 .page tabViewStyle，用手动切换 + transition）
                ZStack {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        if index == currentPage {
                            pageView(page)
                                .transition(
                                    direction > 0
                                    ? .move(edge: .trailing).combined(with: .opacity)
                                    : .move(edge: .leading).combined(with: .opacity)
                                )
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.28), value: currentPage)

                // 底部指示器 + 按钮
                bottomBar
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
            }
        }
        .frame(width: 540, height: 440)
        .preferredColorScheme(.dark)
    }

    // MARK: Background

    private var backgroundGradient: some View {
        ZStack {
            Color(red: 0.08, green: 0.085, blue: 0.11)
            // subtle radial glow
            RadialGradient(
                colors: [
                    Color(red: 0.28, green: 0.54, blue: 0.90).opacity(0.12),
                    .clear
                ],
                center: .top,
                startRadius: 60,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }

    // MARK: Page Content

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // 图标区
            iconArea(page)
                .padding(.bottom, 28)

            // 标题
            Text(page.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 12)

            // 描述
            Text(page.description)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
                .fixedSize(horizontal: false, vertical: true)

            // 特性列表（如果有）
            if let features = page.features {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(red: 0.35, green: 0.78, blue: 0.56))
                            Text(feature)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                .padding(.top, 20)
            }

            // 快捷键标注
            if let shortcut = page.shortcutHint {
                shortcutBadge(shortcut)
                    .padding(.top, 18)
            }

            Spacer(minLength: 0)
        }
    }

    private func iconArea(_ page: OnboardingPage) -> some View {
        ZStack {
            // 背景圆
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            page.accentColor.opacity(0.18),
                            page.accentColor.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)

            // 图标
            Image(systemName: page.iconName)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(page.accentColor)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.white.opacity(0.08), in: Capsule())
    }

    // MARK: Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // 页面指示点
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }

            Spacer()

            // 上一步（不在第一页时显示）
            if currentPage > 0 {
                Button(L10n.onboardingPrevious) {
                    direction = -1
                    withAnimation(.easeInOut(duration: 0.28)) {
                        currentPage -= 1
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.white.opacity(0.07), in: Capsule())
            }

            // 下一步 / 开始使用
            Button(currentPage == pages.count - 1 ? L10n.onboardingStartUsing : L10n.onboardingNext) {
                if currentPage == pages.count - 1 {
                    onComplete()
                } else {
                    direction = 1
                    withAnimation(.easeInOut(duration: 0.28)) {
                        currentPage += 1
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.35, green: 0.54, blue: 0.90), Color(red: 0.28, green: 0.42, blue: 0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .shadow(color: Color(red: 0.28, green: 0.54, blue: 0.90).opacity(0.3), radius: 8, y: 2)
        }
    }
}

// MARK: - Onboarding Page Model

private struct OnboardingPage {
    let title: String
    let description: String
    let iconName: String
    let accentColor: Color
    let features: [String]?
    let shortcutHint: String?

    init(title: String, description: String, iconName: String,
         accentColor: Color, features: [String]? = nil,
         shortcutHint: String? = nil) {
        self.title = title
        self.description = description
        self.iconName = iconName
        self.accentColor = accentColor
        self.features = features
        self.shortcutHint = shortcutHint
    }

    // MARK: Presets

    static let welcome = OnboardingPage(
        title: L10n.onboardingWelcomeTitle,
        description: L10n.onboardingWelcomeDesc,
        iconName: "clipboard.fill",
        accentColor: Color(red: 0.28, green: 0.54, blue: 0.90),
        features: [
            L10n.tr("onboarding.feature_auto_save"),
            L10n.tr("onboarding.feature_cross_app"),
            L10n.tr("onboarding.feature_smart_org")
        ]
    )

    static let autoCapture = OnboardingPage(
        title: L10n.onboardingAutoCaptureTitle,
        description: L10n.onboardingAutoCaptureDesc,
        iconName: "tray.full.fill",
        accentColor: Color(red: 0.96, green: 0.62, blue: 0.24),
        features: [
            L10n.tr("onboarding.feature_types"),
            L10n.tr("onboarding.feature_source_app"),
            L10n.tr("onboarding.feature_ignore_apps")
        ]
    )

    static let quickAccess = OnboardingPage(
        title: L10n.onboardingQuickAccessTitle,
        description: L10n.onboardingQuickAccessDesc,
        iconName: "keyboard.fill",
        accentColor: Color(red: 0.35, green: 0.78, blue: 0.56),
        features: [
            L10n.tr("onboarding.feature_arrow_keys"),
            L10n.tr("onboarding.feature_shift_enter"),
            L10n.tr("onboarding.feature_cmd_c")
        ],
        shortcutHint: "⌘ ⇧ V  \(L10n.tr("onboarding.hint_invoke_panel"))"
    )

    static let organization = OnboardingPage(
        title: L10n.onboardingOrganizationTitle,
        description: L10n.onboardingOrganizationDesc,
        iconName: "square.grid.2x2.fill",
        accentColor: Color(red: 0.55, green: 0.33, blue: 0.76),
        features: [
            L10n.tr("onboarding.feature_drag_drop"),
            L10n.tr("onboarding.feature_custom_boards"),
            L10n.tr("onboarding.feature_filter_by_board")
        ]
    )

    static let searchPreview = OnboardingPage(
        title: L10n.onboardingSearchPreviewTitle,
        description: L10n.onboardingSearchPreviewDesc,
        iconName: "magnifyingglass.circle.fill",
        accentColor: Color(red: 0.92, green: 0.38, blue: 0.42),
        features: [
            L10n.tr("onboarding.feature_type_search"),
            L10n.tr("onboarding.feature_space_preview"),
            L10n.tr("onboarding.feature_double_click_paste")
        ],
        shortcutHint: "␣ \(L10n.tr("onboarding.hint_preview"))  |  \(L10n.tr("onboarding.hint_type_search"))"
    )

    static let ready = OnboardingPage(
        title: L10n.onboardingReadyTitle,
        description: L10n.onboardingReadyDesc,
        iconName: "sparkles",
        accentColor: Color(red: 0.28, green: 0.54, blue: 0.90),
        shortcutHint: "⌘ ⇧ V  \(L10n.onboardingStartUsing)"
    )
}
