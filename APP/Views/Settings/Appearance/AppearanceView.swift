import SwiftUI
import UIKit

struct AppearanceView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @AppStorage("APP.userTintColor") private var selectedColorHex: String = "#007AFF"
    @State private var selectedColor = Color(hex: "#007AFF")
    @State private var showingColorPicker = false

    private let presetColorHexes: [String] = [
        "#B496DC", "#848ef9", "#ff7a83", "#4161F1", "#FF00FF",
        "#4CD964", "#FF2D55", "#FF9500", "#4860e8", "#5394F7",
        "#e18aab", "#00CED1", "#228B22", "#FF6347", "#191970",
        "#FFB6C1", "#98FB98", "#E6E6FA", "#FF7F50", "#50C878"
    ]

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Button(action: {
                            let impactMed = UIImpactFeedbackGenerator(style: .light)
                            impactMed.impactOccurred()
                            themeManager.selectedTheme = theme
                        }) {
                            Text(theme.displayName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(themeManager.selectedTheme == theme ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(themeManager.selectedTheme == theme ? themeManager.accentColor : Color(.systemGray5))
                                )
                        }
                        .buttonStyle(PlainButtonStyle(), sound: .tick)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                Text("appearance".localized)
            }

            Section {
                Button {
                    showingColorPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(selectedColor)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("color".localized)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                            Text(selectedColorHex)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                .buttonStyle(.plain, sound: .tick)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(presetColorHexes.enumerated()), id: \.offset) { _, hex in
                            let color = Color(hex: hex)
                            let isSelected = selectedColorHex
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .lowercased() == hex.lowercased()
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 2.5)
                                )
                                .overlay {
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedColor = color
                                        selectedColorHex = hex
                                        themeManager.accentColor = color
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("color".localized)
            }
        }
        .navigationTitle("settings_appearance_color".localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedColor = Color(hex: selectedColorHex)
        }
        .onChange(of: selectedColor) { _, newColor in
            selectedColorHex = newColor.toHex()
            themeManager.accentColor = newColor
        }
        .onChange(of: selectedColorHex) { _, newValue in
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                for window in windowScene.windows {
                    window.tintColor = UIColor(Color(hex: newValue))
                }
            }
            themeManager.objectWillChange.send()
        }
        .sheet(isPresented: $showingColorPicker) {
            NavigationView {
                ColorPickerView(selectedColor: $selectedColor)
                    .navigationTitle("color".localized)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("ok".localized) {
                                showingColorPicker = false
                            }
                            .fontWeight(.semibold)
                        }
                    }
            }
        }
    }
}
