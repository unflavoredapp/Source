import SwiftUI
import UIKit

enum TabEnum: String, CaseIterable, Hashable {
    case browse
    case downloads
    case sign
    case settings
    /// App Store Search — equal tab between Library and Signed.
    case search
    /// Kept for deep links / Island; not shown in the tab bar.
    case decrypt

    var title: String {
        switch self {
        case .browse:    return "tab_browse".localized
        case .settings:  return "tab_settings".localized
        case .downloads: return "tab_library".localized
        case .decrypt:   return "tab_decrypt".localized
        case .sign:      return "tab_signed".localized
        case .search:    return "tab_search".localized
        }
    }

    var icon: String {
        switch self {
        case .browse:    return "circle.grid.3x3.fill"
        case .downloads: return "square.grid.2x2.fill"
        case .search:    return "magnifyingglass"
        case .sign:      return "signature"
        case .settings:  return "gearshape.fill"
        case .decrypt:   return "folder.fill"
        }
    }

    /// Browse · Library · Search · Signed · Settings
    static var barTabs: [TabEnum] { [.browse, .downloads, .search, .sign, .settings] }

    @ViewBuilder
    static func view(for tab: TabEnum, themeManager: ThemeManager, tabBarStyleManager: TabBarStyleManager) -> some View {
        switch tab {
        case .browse:
            BrowseView()
                .environmentObject(themeManager)
                .environmentObject(tabBarStyleManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .settings:
            SettingsView()
                .environmentObject(themeManager)
                .environmentObject(tabBarStyleManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .downloads:
            NavigationStack {
                DownloadView()
                    .environmentObject(themeManager)
                    .environmentObject(tabBarStyleManager)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .decrypt:
            NavigationStack {
                DecryptView()
                    .environmentObject(themeManager)
                    .environmentObject(tabBarStyleManager)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .sign:
            NavigationStack {
                SignView()
                    .environmentObject(themeManager)
                    .environmentObject(tabBarStyleManager)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .search:
            // App Store search — separate from DELvEK repo Browse.
            SearchView()
                .environmentObject(themeManager)
                .environmentObject(tabBarStyleManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct TabbarView: View {
    @State private var selectedTab: TabEnum = {
        if let raw = UserDefaults.standard.string(forKey: "initialTab"),
           let tab = TabEnum(rawValue: raw),
           TabEnum.barTabs.contains(tab) || tab == .decrypt {
            return tab
        }
        return .browse
    }()
    @ObservedObject private var tabOrder = TabOrderStore.shared
    @ObservedObject private var router = TabRouter.shared
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tabBarStyleManager: TabBarStyleManager

    private static let floatingTabMinWidth: CGFloat = 44

    var body: some View {
        Group {
            if tabBarStyleManager.currentStyle == .floatingCard {
                assassinStyleRoot
            } else if #available(iOS 18.0, *) {
                systemTabView
            } else {
                standardTabView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(themeManager.accentColor)
        .background(FlatChrome.canvas.ignoresSafeArea())
        .preferredColorScheme(themeManager.liquidGlassEnabled ? nil : .dark)
        .onAppear {
            AnalyticsManager.shared.trackScreen(selectedTab.rawValue)
            updateTabBarAppearance()
        }
        .onReceive(router.$pendingTab) { requested in
            if let requested {
                selectedTab = requested
                router.pendingTab = nil
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            AnalyticsManager.shared.trackScreen(newValue.rawValue)
            UserDefaults.standard.set(newValue.rawValue, forKey: "initialTab")
        }
        .onChange(of: router.pendingTab) { _, newValue in
            if let newValue {
                selectedTab = newValue
                router.pendingTab = nil
            }
        }
        .onChange(of: themeManager.accentColor) { _, _ in
            updateTabBarAppearance()
        }
        .onChange(of: tabBarStyleManager.currentStyle) { _, _ in
            updateTabBarAppearance()
        }
    }

    private var assassinStyleRoot: some View {
        ZStack {
            FlatChrome.canvas.ignoresSafeArea()

            tabPage(for: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(selectedTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // App Store floating top bar lives inside SearchView only — not on repo Browse.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            floatingTabBarContent
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private func tabPage(for tab: TabEnum) -> some View {
        TabEnum.view(for: tab, themeManager: themeManager, tabBarStyleManager: tabBarStyleManager)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var systemTabView: some View {
        standardTabView
    }

    @ViewBuilder
    private var standardTabView: some View {
        if #available(iOS 18.0, *) {
            modernStandardTabView
        } else {
            legacyStandardTabView
        }
    }

    @available(iOS 18.0, *)
    private var modernStandardTabView: some View {
        TabView(selection: $selectedTab) {
            ForEach(tabOrder.order, id: \.self) { tab in
                Tab(value: tab) {
                    tabContent(for: tab)
                } label: {
                    Label(tab.title, systemImage: tab.icon)
                }
            }
        }
    }

    @ViewBuilder
    private var legacyStandardTabView: some View {
        TabView(selection: $selectedTab) {
            ForEach(tabOrder.order, id: \.self) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label {
                            Text(tab.title)
                        } icon: {
                            Image(systemName: tab.icon)
                        }
                    }
                    .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: TabEnum) -> some SwiftUI.View {
        TabEnum.view(for: tab, themeManager: themeManager, tabBarStyleManager: tabBarStyleManager)
            .toolbar(.visible, for: .tabBar)
            .toolbarBackground(.hidden, for: .tabBar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var floatingTabBarContent: some View {
        let config = tabBarStyleManager.floatingConfig
        let tabHeight = max(config.height, 52)

        // Equal SF Symbol tabs — Search sits between Library and Signed (no circle background).
        return HStack(spacing: 0) {
            ForEach(tabOrder.order, id: \.self) { tab in
                tabButton(for: tab, height: tabHeight)
                    .frame(minWidth: Self.floatingTabMinWidth, maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .frame(height: tabHeight)
        .frame(maxWidth: .infinity)
        .background(FlatChrome.tabBar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FlatChrome.hairline)
                .frame(height: 0.5)
        }
    }

    private func tabButton(for tab: TabEnum, height: CGFloat) -> some View {
        let active = selectedTab == tab
        return Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                selectedTab = tab
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(active ? Color.white : Color.white.opacity(0.40))

                Text(tab.title)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(active ? Color.white : Color.white.opacity(0.40))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .contentShape(Rectangle())
            .frame(maxHeight: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func updateTabBarAppearance() {
        let appearance = UITabBarAppearance()
        let style = tabBarStyleManager.currentStyle

        switch style {
        case .systemDefault:
            if themeManager.liquidGlassEnabled {
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = .clear
                appearance.shadowImage = UIImage()
                appearance.backgroundImage = UIImage()
            } else {
                appearance.configureWithOpaqueBackground()
            }
            UITabBar.appearance().isHidden = false
        case .floatingCard:
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.shadowImage = UIImage()
            appearance.backgroundImage = UIImage()
            UITabBar.appearance().isHidden = true
        }

        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(themeManager.accentColor)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(themeManager.accentColor)]

        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }

        let hidden = style == .floatingCard
        DispatchQueue.main.async {
            for bar in Self.liveTabBars() {
                bar.standardAppearance = appearance
                bar.scrollEdgeAppearance = appearance
                bar.isHidden = hidden
                bar.setNeedsLayout()
            }
        }
    }

    private static func liveTabBars() -> [UITabBar] {
        var bars: [UITabBar] = []
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if let bar = findTabBar(in: window.rootViewController), !bars.contains(where: { $0 === bar }) {
                    bars.append(bar)
                }
            }
        }
        return bars
    }

    private static func findTabBar(in controller: UIViewController?) -> UITabBar? {
        guard let controller else { return nil }
        if let tab = controller as? UITabBarController { return tab.tabBar }
        for child in controller.children {
            if let found = findTabBar(in: child) { return found }
        }
        return findTabBar(in: controller.presentedViewController)
    }
}
