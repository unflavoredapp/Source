import SwiftUI

struct TelegramWorkerSettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject private var worker = TelegramWorker.shared

    @State private var enabled = TelegramWorkerConfig.isEnabled
    @State private var token = TelegramWorkerConfig.botToken
    @State private var chatIDs = TelegramWorkerConfig.allowedChatIDsRaw

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("telegram_worker_title".localized)
                    .font(.title2.weight(.bold))

                Text("telegram_worker_intro".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $enabled) {
                    Text("telegram_worker_enabled".localized)
                }
                .tint(themeManager.accentColor)
                .onChange(of: enabled) { _, value in
                    TelegramWorkerConfig.isEnabled = value
                    worker.reconcile()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("telegram_worker_token".localized)
                        .font(.subheadline.weight(.semibold))
                    SecureField("123456:ABC…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .liquidGlassSurface(cornerRadius: 12)
                    Text("telegram_worker_token_hint".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("telegram_worker_chats".localized)
                        .font(.subheadline.weight(.semibold))
                    TextField("123456789", text: $chatIDs)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .liquidGlassSurface(cornerRadius: 12)
                    Text("telegram_worker_chats_hint".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("telegram_worker_save".localized) {
                    TelegramWorkerConfig.botToken = TelegramBotClient.normalizedToken(token)
                    token = TelegramWorkerConfig.botToken
                    TelegramWorkerConfig.allowedChatIDsRaw = chatIDs
                    TelegramWorkerConfig.isEnabled = enabled
                    worker.reconcile()
                }
                .buttonStyle(.borderedProminent)
                .tint(themeManager.accentColor)

                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        worker.isRunning ? "telegram_worker_running".localized : "telegram_worker_stopped".localized,
                        systemImage: worker.isRunning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
                    )
                    .foregroundStyle(worker.isRunning ? themeManager.accentColor : .secondary)
                    Text(worker.lastStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let err = worker.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlassSurface(cornerRadius: 16)

                Text("telegram_worker_commands".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(themeManager.backgroundColor.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            enabled = TelegramWorkerConfig.isEnabled
            token = TelegramWorkerConfig.botToken
            chatIDs = TelegramWorkerConfig.allowedChatIDsRaw
        }
    }
}
