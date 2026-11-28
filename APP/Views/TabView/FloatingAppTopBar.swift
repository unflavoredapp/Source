import SwiftUI

/// The only floating chrome: centered name + magnifying glass that expands into a search field.
struct FloatingAppTopBar: View {
    let title: String
    @Binding var searchText: String
    @Binding var isSearchExpanded: Bool
    var onSubmitSearch: () -> Void

    @FocusState private var fieldFocused: Bool
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Color.clear.frame(width: 36, height: 36)

                Spacer(minLength: 0)

                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSearchExpanded {
                    // Magnify glass disappears while the search field is open.
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            isSearchExpanded = false
                            searchText = ""
                            fieldFocused = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            isSearchExpanded = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            fieldFocused = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("tab_search".localized)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if isSearchExpanded {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("search_placeholder".localized, text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .foregroundStyle(.primary)
                        .submitLabel(.search)
                        .onSubmit(onSubmitSearch)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FlatChrome.elevated)
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FlatChrome.tabBar.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(FlatChrome.hairline, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        )
        .padding(.horizontal, 12)
    }
}
