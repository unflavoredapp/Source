import SwiftUI

struct SigningHistoryRow: View {
    let options: SigningHistoryRowOptions

    private var signedBadge: String {
        let date = options.record.date.formatted(date: .numeric, time: .omitted)
        return String(format: "sign_history_signed_badge".localized, date)
    }

    var body: some View {
        Button(action: options.onSelect) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "app.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(options.accentColor)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(options.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(options.record.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(metaLine)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(signedBadge)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: options.onToggleHidden) {
                Label(
                    options.record.isHidden == true ? "sign_history_unhide".localized : "sign_history_hide".localized,
                    systemImage: options.record.isHidden == true ? "eye" : "eye.slash"
                )
            }
            Button(role: .destructive, action: options.onDelete) {
                Label("sign_delete".localized, systemImage: "trash")
            }
        }
    }

    private var metaLine: String {
        let version = options.record.version.isEmpty ? nil : options.record.version
        let bundle = options.record.bundleId.isEmpty ? options.record.outputName : options.record.bundleId
        if let version, !bundle.isEmpty {
            return "\(version) · \(bundle)"
        }
        return bundle.isEmpty ? (version ?? "—") : bundle
    }
}
