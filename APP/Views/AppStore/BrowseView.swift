import SwiftUI
import UIKit

/// Browse tab root — Sources list (MSIGN-style). Tap a source to open its repo feed.
struct BrowseView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var appStore: AppStore
    @ObservedObject private var store = IPASourceStore.shared

    @State private var isEditing = false
    @State private var showAddSource = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                FlatChrome.canvas.ignoresSafeArea()

                if store.sources.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.sources) { source in
                            Button {
                                path.append(source)
                            } label: {
                                SourceRowView(source: source)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(FlatChrome.canvas)
                            .listRowSeparatorTint(FlatChrome.hairline)
                        }
                        .onDelete(perform: store.remove)
                        .onMove(perform: store.move)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(isEditing ? .active : .inactive))
                }
            }
            .navigationTitle("sources_title".localized)
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: IPASource.self) { source in
                RepoBrowseView(source: source)
                    .environmentObject(themeManager)
                    .environmentObject(appStore)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button(isEditing ? "done".localized : "edit".localized) {
                            withAnimation { isEditing.toggle() }
                        }
                        .foregroundStyle(.secondary)

                        Button {
                            showAddSource = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("sources_add".localized)
                    }
                }
            }
            .sheet(isPresented: $showAddSource) {
                AddSourceSheet { draft in
                    store.add(draft)
                }
                .environmentObject(themeManager)
                .presentationDetents([.medium])
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("sources_empty".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("sources_reset_defaults".localized) {
                store.reset()
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SourceRowView: View {
    let source: IPASource

    var body: some View {
        HStack(spacing: 14) {
            sourceIcon
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(source.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(source.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.85))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let asset = source.iconAsset, UIImage(named: asset) != nil {
            Image(asset)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                source.accentColor
                Text(source.monogram ?? String(source.name.prefix(1)))
                    .font(.system(size: source.monogram == nil ? 20 : 9, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(4)
            }
        }
    }
}

/// Per-source repo browse (DELvEK.NET style header + app cards).
struct RepoBrowseView: View {
    let source: IPASource

    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var appStore: AppStore
    @State private var apps: [iTunesSearchResult] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var selectedApp: iTunesSearchResult?
    @State private var downloadingIds: Set<Int> = []
    @State private var showAppStoreSearch = false

    var body: some View {
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
                    repoToolbarIcon
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(source.name.uppercased().contains("DELVEK") ? "DELvEK.NET" : source.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        showAppStoreSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "line.3.horizontal.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fullScreenCover(isPresented: $showAppStoreSearch) {
            SearchView(showsDismissButton: true)
                .environmentObject(themeManager)
                .environmentObject(appStore)
        }
        .task { await loadFeatured(force: false) }
    }

    @ViewBuilder
    private var repoToolbarIcon: some View {
        if let asset = source.iconAsset, UIImage(named: asset) != nil {
            Image(asset)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                source.accentColor
                Text(String((source.monogram ?? source.name).prefix(1)))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var repoHeader: some View {
        HStack {
            Text(String(format: "browse_apps_count".localized, source.catalogCount.formatted()))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(displayHandle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.23, blue: 0.19))
        }
        .padding(.horizontal, 16)
    }

    private var displayHandle: String {
        if source.handle == "MRZefv" || source.name.uppercased().contains("DELVEK") {
            if let account = appStore.selectedAccount {
                let name = account.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return name }
                let email = account.email
                if let at = email.firstIndex(of: "@") {
                    return String(email[..<at])
                }
                return email
            }
        }
        return source.handle
    }

    private func loadFeatured(force: Bool) async {
        if !force, !apps.isEmpty { return }
        loading = true
        errorText = nil
        defer { loading = false }

        let country = appStore.selectedAccount?.countryCode ?? "US"
        let seeds = source.seedTerms
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

private struct AddSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager

    var onAdd: (IPASource) -> Void

    @State private var name = ""
    @State private var subtitle = ""
    @State private var handle = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("sources_field_name".localized, text: $name)
                    TextField("sources_field_subtitle".localized, text: $subtitle)
                    TextField("sources_field_handle".localized, text: $handle)
                }
            }
            .scrollContentBackground(.hidden)
            .background(FlatChrome.canvas.ignoresSafeArea())
            .navigationTitle("sources_add".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("add".localized) {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let source = IPASource(
                            id: UUID(),
                            name: trimmed,
                            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "sources_default_subtitle".localized
                                : subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
                            iconAsset: nil,
                            monogram: String(trimmed.prefix(2)).uppercased(),
                            accentHex: "3A3A3C",
                            catalogCount: 0,
                            handle: handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? trimmed
                                : handle.trimmingCharacters(in: .whitespacesAndNewlines),
                            seedTerms: [trimmed, "Apps"]
                        )
                        onAdd(source)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
