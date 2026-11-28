import UIKit

/// Renders FastDecrypt-style “sharp cards” for Telegram photo replies, branded UNlicense / DELvEK.NET.
enum TelegramSharpCard {
    static let brandHandle = "unlicense.cc"
    static let madeBy = "Made by UNlicense.cc"
    static let delvekName = "DELvEK"
    static let patchURL = URL(string: "https://delvek.net")!
    static let vipURL = URL(string: "https://delvek.net")!

    struct ProgressModel {
        var appName: String
        var version: String
        var icon: UIImage?
        var percent: Int
        var lines: [String]
        /// Lifetime / catalog count shown as “4,303 apps” on the DELvEK header.
        var appsCount: Int = 0
        var accent: UIColor = UIColor(red: 0.18, green: 0.92, blue: 0.55, alpha: 1)
        var failed: Bool = false
    }

    struct ReadyModel {
        var appName: String
        var version: String
        var icon: UIImage?
        var tagline: String = "IPA ready. Sideloading skill: zero."
    }

    /// Progress app card — left console + right ring (3rd-screenshot layout, UNlicense branding).
    static func renderProgress(_ model: ProgressModel) -> Data? {
        let size = CGSize(width: 1024, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            let midX = size.width * 0.5
            drawConsolePanel(
                in: CGRect(x: 0, y: 0, width: midX, height: size.height),
                lines: model.lines,
                appsCount: model.appsCount,
                accent: model.failed ? UIColor.systemRed : model.accent,
                context: cg
            )
            drawProgressPanel(
                in: CGRect(x: midX, y: 0, width: midX, height: size.height),
                model: model,
                context: cg
            )
        }
        return image.jpegData(compressionQuality: 0.88)
    }

    /// Final delivery card — left brand/app copy + right download visual (screenshot-2 layout).
    static func renderReady(_ model: ReadyModel) -> Data? {
        let size = CGSize(width: 1024, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let midX = size.width * 0.5

            // Left — black brand panel
            UIColor.black.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: midX, height: size.height))

            drawDelvekHeader(
                in: CGRect(x: 28, y: 28, width: midX - 56, height: 28),
                appsCount: TelegramWorkerConfig.displayedAppsCount
            )

            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 42, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let name = model.appName as NSString
            let nameSize = name.size(withAttributes: nameAttrs)
            name.draw(at: CGPoint(x: 32, y: 88), withAttributes: nameAttrs)

            let tagColor = UIColor(red: 0.98, green: 0.42, blue: 0.48, alpha: 1)
            (model.tagline as NSString).draw(
                at: CGPoint(x: 32, y: 88 + nameSize.height + 10),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                    .foregroundColor: tagColor,
                ]
            )

            let logoSide: CGFloat = 88
            let logoRect = CGRect(
                x: midX / 2 - logoSide / 2,
                y: size.height - 150,
                width: logoSide,
                height: logoSide
            )
            drawRoundedImage(model.icon ?? UIImage(named: "AppLogo"), in: logoRect, cornerRadius: 20, context: cg)

            let credit = madeBy as NSString
            let creditAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: UIColor(white: 0.75, alpha: 1),
            ]
            let creditSize = credit.size(withAttributes: creditAttrs)
            credit.draw(
                at: CGPoint(x: midX / 2 - creditSize.width / 2, y: logoRect.maxY + 10),
                withAttributes: creditAttrs
            )

            // Right — soft wash + large download glyph over app icon
            let right = CGRect(x: midX, y: 0, width: midX, height: size.height)
            let colors = [
                UIColor(red: 0.55, green: 0.72, blue: 0.82, alpha: 1).cgColor,
                UIColor(red: 0.72, green: 0.78, blue: 0.84, alpha: 1).cgColor,
                UIColor(red: 0.45, green: 0.55, blue: 0.62, alpha: 1).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: right.minX, y: right.minY),
                    end: CGPoint(x: right.maxX, y: right.maxY),
                    options: []
                )
            } else {
                UIColor(white: 0.7, alpha: 1).setFill()
                cg.fill(right)
            }

            let badgeSide: CGFloat = 220
            let badge = CGRect(
                x: right.midX - badgeSide / 2,
                y: right.midY - badgeSide / 2 - 8,
                width: badgeSide,
                height: badgeSide
            )
            UIColor(white: 1, alpha: 0.55).setFill()
            UIBezierPath(roundedRect: badge, cornerRadius: 48).fill()

            if let icon = model.icon {
                cg.saveGState()
                UIBezierPath(roundedRect: badge.insetBy(dx: 28, dy: 28), cornerRadius: 36).addClip()
                icon.draw(in: badge.insetBy(dx: 28, dy: 28))
                cg.restoreGState()
            }

            // Download chevron overlay
            let arrow = UIImage(systemName: "arrow.down")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 72, weight: .bold))
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            if let arrow {
                let aSize = arrow.size
                arrow.draw(at: CGPoint(x: right.midX - aSize.width / 2, y: right.midY - aSize.height / 2 - 4))
            }

            let handle = brandHandle as NSString
            let handleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: UIColor(white: 0.35, alpha: 1),
            ]
            let handleSize = handle.size(withAttributes: handleAttrs)
            handle.draw(
                at: CGPoint(x: right.maxX - handleSize.width - 24, y: right.maxY - 36),
                withAttributes: handleAttrs
            )
        }
        return image.jpegData(compressionQuality: 0.9)
    }

    /// HTML caption under the final ready card (📁 / ⚙️ / 🔗).
    static func readyCaptionHTML(
        bundleId: String,
        version: String,
        minimumOS: String?,
        storeURL: String?,
        sizeBytes: Int64?
    ) -> String {
        var lines: [String] = []
        if !bundleId.isEmpty {
            lines.append("📁 <code>\(escapeHTML(bundleId))</code>")
        }
        var versionLine = "⚙️ Version: \(escapeHTML(version.isEmpty ? "—" : version))"
        if let minimumOS, !minimumOS.isEmpty {
            versionLine += " · \(escapeHTML(minimumOS))+"
        }
        lines.append(versionLine)
        if let storeURL, let url = URL(string: storeURL), url.scheme?.hasPrefix("http") == true {
            lines.append("🔗 <a href=\"\(escapeHTML(storeURL))\">App Store Link</a>")
        }
        if let sizeBytes, sizeBytes > 0 {
            let mb = Double(sizeBytes) / 1_048_576
            lines.append(String(format: "📦 %.1f MB", mb))
        }
        return lines.joined(separator: "\n")
    }

    /// Inline keyboard: Download (full width) + Patch | Get VIP.
    static func readyReplyMarkup(downloadURL: URL?) -> [String: Any] {
        var rows: [[ [String: String] ]] = []
        let download = downloadURL ?? patchURL
        rows.append([[
            "text": "⬇️ Download",
            "url": download.absoluteString,
        ]])
        rows.append([
            ["text": "🧩 Patch", "url": patchURL.absoluteString],
            ["text": "⭐ Get VIP", "url": vipURL.absoluteString],
        ])
        return ["inline_keyboard": rows]
    }

    /// Status card for /status.
    static func renderStatus(
        running: Bool,
        busy: Bool,
        account: String,
        lastStatus: String,
        lastError: String?
    ) -> Data? {
        let size = CGSize(width: 900, height: 420)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1).setFill()
            ctx.cgContext.fill(rect)

            drawDelvekHeader(
                in: CGRect(x: 28, y: 24, width: size.width - 56, height: 36),
                appsCount: TelegramWorkerConfig.displayedAppsCount
            )

            ("UNlicense status" as NSString).draw(
                at: CGPoint(x: 32, y: 78),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                    .foregroundColor: UIColor.white,
                ]
            )

            let rows: [(String, String)] = [
                ("Worker", running ? (busy ? "busy" : "idle / polling") : "stopped"),
                ("Account", account),
                ("Decrypt", FairPlayDecryptor.isAvailable ? "ready" : "unavailable"),
                ("Last", lastStatus),
            ] + (lastError.map { [("Error", $0)] } ?? [])

            var y: CGFloat = 130
            for (label, value) in rows {
                let line = "\(label):  \(value)" as NSString
                line.draw(
                    at: CGPoint(x: 32, y: y),
                    withAttributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                        .foregroundColor: label == "Error" ? UIColor.systemRed : UIColor(white: 0.85, alpha: 1),
                    ]
                )
                y += 34
            }

            (madeBy as NSString).draw(
                at: CGPoint(x: 32, y: size.height - 42),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: UIColor(white: 0.45, alpha: 1),
                ]
            )
        }
        return image.jpegData(compressionQuality: 0.9)
    }

    // MARK: - Panels

    private static func drawConsolePanel(
        in rect: CGRect,
        lines: [String],
        appsCount: Int,
        accent: UIColor,
        context: CGContext
    ) {
        drawDelvekHeader(
            in: CGRect(x: rect.minX + 24, y: rect.minY + 22, width: rect.width - 48, height: 28),
            appsCount: appsCount
        )

        let box = CGRect(x: rect.minX + 28, y: rect.minY + 70, width: rect.width - 56, height: rect.height - 200)
        let path = UIBezierPath(roundedRect: box, cornerRadius: 16)
        UIColor(white: 0.07, alpha: 1).setFill()
        path.fill()
        UIColor(white: 1, alpha: 0.10).setStroke()
        path.lineWidth = 1
        path.stroke()

        var consoleLines: [String] = ["$ job start"]
        consoleLines.append(contentsOf: lines.suffix(6).map { "> \($0)" })

        var y = box.minY + 18
        for (idx, line) in consoleLines.enumerated() {
            let isLast = idx == consoleLines.count - 1
            let color: UIColor = isLast ? accent : UIColor(white: 0.88, alpha: 1)
            let text = line as NSString
            // Highlight the last token of the active line in accent (FastDecrypt style).
            if isLast, let space = line.lastIndex(of: " "), line.hasPrefix(">") {
                let prefix = String(line[..<space]) as NSString
                let suffix = String(line[space...]) as NSString
                let baseAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium),
                    .foregroundColor: UIColor(white: 0.88, alpha: 1),
                ]
                let accentAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium),
                    .foregroundColor: color,
                ]
                prefix.draw(at: CGPoint(x: box.minX + 18, y: y), withAttributes: baseAttrs)
                let prefixW = prefix.size(withAttributes: baseAttrs).width
                suffix.draw(at: CGPoint(x: box.minX + 18 + prefixW, y: y), withAttributes: accentAttrs)
            } else {
                text.draw(
                    at: CGPoint(x: box.minX + 18, y: y),
                    withAttributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium),
                        .foregroundColor: color,
                    ]
                )
            }
            y += 28
            if y > box.maxY - 24 { break }
        }

        let logoSide: CGFloat = 72
        let logoRect = CGRect(
            x: rect.midX - logoSide / 2,
            y: rect.maxY - 118,
            width: logoSide,
            height: logoSide
        )
        drawRoundedImage(UIImage(named: "AppLogo"), in: logoRect, cornerRadius: 16, context: context)

        let credit = madeBy as NSString
        let creditAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor(white: 0.7, alpha: 1),
        ]
        let creditSize = credit.size(withAttributes: creditAttrs)
        credit.draw(
            at: CGPoint(x: rect.midX - creditSize.width / 2, y: logoRect.maxY + 8),
            withAttributes: creditAttrs
        )
    }

    private static func drawProgressPanel(in rect: CGRect, model: ProgressModel, context: CGContext) {
        UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1).setFill()
        context.fill(rect)

        // Soft icon wash behind the ring (3rd-screenshot glow).
        if let icon = model.icon {
            let wash = CGRect(
                x: rect.midX - 160,
                y: rect.midY - 140,
                width: 320,
                height: 320
            )
            icon.draw(in: wash, blendMode: .normal, alpha: 0.28)
        }

        let name = model.appName as NSString
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let nameSize = name.size(withAttributes: nameAttrs)
        name.draw(
            at: CGPoint(x: rect.midX - nameSize.width / 2, y: rect.minY + 36),
            withAttributes: nameAttrs
        )

        let ringSide: CGFloat = 260
        let ringRect = CGRect(
            x: rect.midX - ringSide / 2,
            y: rect.midY - ringSide / 2 + 8,
            width: ringSide,
            height: ringSide
        )
        let center = CGPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = ringSide / 2 - 10
        let pct = max(0, min(100, model.percent))
        let start = -CGFloat.pi / 2
        let end = start + CGFloat(pct) / 100 * .pi * 2

        context.setLineWidth(16)
        context.setLineCap(.round)
        UIColor(white: 1, alpha: 0.18).setStroke()
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()

        let ringColor = model.failed ? UIColor.systemRed : UIColor.white
        ringColor.setStroke()
        context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        context.strokePath()

        let percentText = "\(pct)%" as NSString
        let font = UIFont.systemFont(ofSize: 56, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
        ]
        let textSize = percentText.size(withAttributes: attrs)
        percentText.draw(
            at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2),
            withAttributes: attrs
        )

        let version = model.version.isEmpty ? "" : "v\(model.version)"
        (version as NSString).draw(
            at: CGPoint(x: rect.minX + 28, y: rect.maxY - 40),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor(white: 0.85, alpha: 1),
            ]
        )

        let handle = brandHandle as NSString
        let handleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: UIColor(white: 0.55, alpha: 1),
        ]
        let handleSize = handle.size(withAttributes: handleAttrs)
        handle.draw(
            at: CGPoint(x: rect.maxX - handleSize.width - 28, y: rect.maxY - 40),
            withAttributes: handleAttrs
        )
    }

    /// Left header: DELvEK circular icon + name + “N apps” (FastDecrypt-style).
    private static func drawDelvekHeader(in rect: CGRect, appsCount: Int?) {
        let side: CGFloat = 24
        let logoRect = CGRect(x: rect.minX, y: rect.midY - side / 2, width: side, height: side)
        let logo = UIImage(named: "DelvekIcon") ?? UIImage(named: "AppLogo")
        if let logo {
            let path = UIBezierPath(ovalIn: logoRect)
            UIGraphicsGetCurrentContext()?.saveGState()
            path.addClip()
            logo.draw(in: logoRect)
            UIGraphicsGetCurrentContext()?.restoreGState()
        }

        (delvekName as NSString).draw(
            at: CGPoint(x: rect.minX + side + 8, y: rect.midY - 9),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
        )

        if let appsCount {
            let trailing = formattedAppsCount(appsCount)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: UIColor(white: 0.62, alpha: 1),
            ]
            let size = (trailing as NSString).size(withAttributes: attrs)
            (trailing as NSString).draw(
                at: CGPoint(x: rect.maxX - size.width, y: rect.midY - size.height / 2),
                withAttributes: attrs
            )
        }
    }

    static func formattedAppsCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let n = formatter.string(from: NSNumber(value: max(0, count))) ?? "\(count)"
        return "\(n) apps"
    }

    private static func drawRoundedImage(_ image: UIImage?, in rect: CGRect, cornerRadius: CGFloat, context: CGContext) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        context.saveGState()
        path.addClip()
        if let image {
            image.draw(in: rect)
        } else {
            UIColor(white: 0.2, alpha: 1).setFill()
            context.fill(rect)
        }
        context.restoreGState()
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
