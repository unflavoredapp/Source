import SwiftUI

/// DELvEK **repo** browse — separate from App Store Search (`SearchView` + floating top bar).
struct BrowseView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var appStore: AppStore
    @State private var apps: [iTunesSearchResult] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var selectedApp: iTunesSearchResult?
    @State private var downloadingIds: Set<Int> = []
    @State private var showAppStoreSearch = false

    private let catalogCount = 1776

    var body: some View {
        NavigationStack {
            ZStack {
                FlatChrome.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        repoHeader

                        if loading && apps.isEmpty {
                            ProgressView()
                                .padding(.top, 40)
                        } else if let errorText, apps.isEmpty {
                            Text(errorText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 24)
                        } else {
                            LazyVStack(spacing: 18) {
                                ForEach(apps, id: \.trackId) { app in
                                    AppSearchResultCardView(
                                        app: app,
                                        onTap: { selectedApp = app },
                                        onGetAction: { startGet(app) },
                                        isDownloading: downloadingIds.contains(app.trackId)
                                    )
                                    .environmentObject(themeManager)
                                }
                            }
                            .padding(.bottom, 120)
                        }
                    }
                    .padding(.top, 8)
                }
                .refreshable { await loadFeatured(force: true) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                        Text("DELvEK.NET")
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Opens App Store Search — not repo search.
                    Button {
                        showAppStoreSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("tab_search".localized)
                }
            }
            .fullScreenCover(isPresented: $showAppStoreSearch) {
                SearchView(showsDismissButton: true)
                    .environmentObject(themeManager)
                    .environmentObject(appStore)
            }
            .task { await loadFeatured(force: false) }
        }
    }

    private var repoHeader: some View {
        HStack {
            Text(String(format: "browse_apps_count".localized, catalogCount.formatted()))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("browse_repo_label".localized)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(themeManager.accentColor)
        }
        .padding(.horizontal, 16)
    }

    private func loadFeatured(force: Bool) async {
        if !force, !apps.isEmpty { return }
        loading = true
        errorText = nil
        defer { loading = false }

        let country = appStore.selectedAccount?.countryCode ?? "US"
        let seeds = ["Netflix", "YouTube", "Spotify", "Instagram", "TikTok", "Disney", "Prime Video", "Hulu"]
        var collected: [iTunesSearchResult] = []
        var seen = Set<Int>()

        for term in seeds {
            do {
                if let batch = try await iTunesClient.shared.search(
                    term: term,
                    limit: 3,
                    countryCode: country,
                    deviceFamily: .phone
                ) {
                    for app in batch where !seen.contains(app.trackId) {
                        seen.insert(app.trackId)
                        collected.append(app)
                    }
                }
            } catch {
                if collected.isEmpty {
                    errorText = error.localizedDescription
                }
            }
            if collected.count >= 12 { break }
        }

        if !collected.isEmpty {
            apps = Array(collected.prefix(16))
            errorText = nil
        } else if errorText == nil {
            errorText = "browse_load_failed".localized
        }
    }

    private func startGet(_ app: iTunesSearchResult) {
        downloadingIds.insert(app.trackId)
        showAppStoreSearch = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(
                name: Notification.Name("BrowseOpenAppStoreSearch"),
                object: nil,
                userInfo: ["term": app.name]
            )
            downloadingIds.remove(app.trackId)
        }
    }
}
