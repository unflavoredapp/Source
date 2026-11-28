import SwiftUI
import UIKit

struct SettingsTabBarView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var tabBarStyleManager: TabBarStyleManager

    private var availableTabStyles: [TabBarStyle] {
        if #available(iOS 18.0, *) {
            return TabBarStyle.allCases
        }
        return TabBarStyle.allCases.filter { $0 != .floatingCard }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    TabOrderSettingsView()
                        .environmentObject(themeManager)
                } label: {
                    Label("tab_order_title".localized, systemImage: "square.grid.2x2")
                }
            }

            Section("settings_tab_bar".localized) {
                ForEach(availableTabStyles, id: \.id) { style in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            tabBarStyleManager.currentStyle = style
                            UserDefaults.standard.set(style == .systemDefault, forKey: "TabBarStyle.userChoseSystem")
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(alignment: .center, spacing: 16) {
                            tabBarStylePreview(style: style)
                                .frame(width: 140, height: 72, alignment: .center)
                                .clipped()
                                .cornerRadius(10)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(style.name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(styleDescription(for: style))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(themeManager.accentColor)
                                .opacity(tabBarStyleManager.currentStyle == style ? 1 : 0)
                        }
                    }
                    .buttonStyle(.plain, sound: .tick)
                }
            }

            if tabBarStyleManager.currentStyle == .floatingCard {
                Section {
                    floatingSlider(
                        title: "floating_tabbar_horizontal_padding".localized,
                        value: Binding(
                            get: { tabBarStyleManager.floatingConfig.horizontalPadding },
                            set: { tabBarStyleManager.floatingConfig.horizontalPadding = $0 }
                        ),
                        range: FloatingTabBarConfig.minHorizontalPadding...FloatingTabBarConfig.maxHorizontalPadding
                    )
                    floatingSlider(
                        title: "floating_tabbar_bottom_offset".localized,
                        value: Binding(
                            get: { tabBarStyleManager.floatingConfig.bottomOffset },
                            set: { tabBarStyleManager.floatingConfig.bottomOffset = $0 }
                        ),
                        range: FloatingTabBarConfig.minBottomOffset...FloatingTabBarConfig.maxBottomOffset
                    )
                    floatingSlider(
                        title: "floating_tabbar_height".localized,
                        value: Binding(
                            get: { tabBarStyleManager.floatingConfig.height },
                            set: { tabBarStyleManager.floatingConfig.height = $0 }
                        ),
                        range: FloatingTabBarConfig.minHeight...FloatingTabBarConfig.maxHeight
                    )
                    floatingSlider(
                        title: "floating_tabbar_corner_radius".localized,
                        value: Binding(
                            get: { tabBarStyleManager.floatingConfig.cornerRadius },
                            set: { tabBarStyleManager.floatingConfig.cornerRadius = $0 }
                        ),
                        range: FloatingTabBarConfig.minCornerRadius...FloatingTabBarConfig.maxCornerRadius
                    )
                } header: {
                    HStack {
                        Text("floating_tabbar_customize".localized)
                        Spacer()
                        Button("reset".localized) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                tabBarStyleManager.resetFloatingConfig()
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(themeManager.accentColor)
                    }
                }
            }
        }
        .navigationTitle("settings_tab_bar".localized)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func floatingSlider(title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 14))
                Spacer()
                Text(String(format: "%.0f pt", value.wrappedValue))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.accentColor)
            }
            Slider(value: value, in: range, step: 1)
                .tint(themeManager.accentColor)
        }
        .padding(.vertical, 4)
    }

    private func styleDescription(for style: TabBarStyle) -> String {
        switch style {
        case .systemDefault:
            return "tab_style_default_desc".localized
        case .floatingCard:
            return "tab_style_floating_desc".localized
        }
    }

    @ViewBuilder
    private func tabBarStylePreview(style: TabBarStyle) -> some View {
        ZStack {
            Color(.systemBackground)
            switch style {
            case .systemDefault:
                VStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(TabEnum.allCases, id: \.self) { tab in
                            VStack(spacing: 3) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(tab == .settings ? themeManager.accentColor : .secondary.opacity(0.6))
                                Text(tab.title)
                                    .font(.system(size: 7, weight: .regular))
                                    .foregroundStyle(tab == .settings ? themeManager.accentColor : .secondary.opacity(0.6))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                    .background(Color(.systemBackground))
                }
            case .floatingCard:
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        HStack(spacing: 0) {
                            ForEach([TabEnum.settings, .downloads, .decrypt, .sign], id: \.self) { tab in
                                VStack(spacing: 1) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 9))
                                        .foregroundStyle(tab == .settings ? themeManager.accentColor : .secondary.opacity(0.6))
                                    Text(tab.title)
                                        .font(.system(size: 5.5, weight: .regular))
                                        .foregroundStyle(tab == .settings ? themeManager.accentColor : .secondary.opacity(0.6))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                }
                                .frame(width: 22)
                            }
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )

                        Circle()
                            .fill(themeManager.accentColor)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}
