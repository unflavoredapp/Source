import UIKit

/// Renders FastDecrypt-style “sharp cards” for Telegram photo replies, branded UNlicense.
enum TelegramSharpCard {
    struct ProgressModel {
        var appName: String
        var version: String
        var icon: UIImage?
        var percent: Int
        var lines: [String]
        var accent: UIColor = UIColor(red: 0.18, green: 0.78, blue: 0.42, alpha: 1)
        var failed: Bool = false
    }

    /// Split card: left console log + right app icon with circular progress.
    static func renderProgress(_ model: ProgressModel) -> Data? {
        let size = CGSize(width: 1024, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            let midX = size.width * 0.5
            drawConsolePanel(
                in: CGRect(x: 0, y: 0, width: midX, height: size.height),
                lines: model.lines,
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

            drawBrandHeader(in: CGRect(x: 28, y: 24, width: size.width - 56, height: 36), trailing: "phone worker")

            let title = "UNlicense status"
            (title as NSString).draw(
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

            ("Made by UNlicense" as NSString).draw(
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
        accent: UIColor,
        context: CGContext
    ) {
        drawBrandHeader(in: CGRect(x: rect.minX + 24, y: rect.minY + 22, width: rect.width - 48, height: 28), trailing: nil)

        let box = CGRect(x: rect.minX + 28, y: rect.minY + 70, width: rect.width - 56, height: rect.height - 150)
        let path = UIBezierPath(roundedRect: box, cornerRadius: 18)
        UIColor(white: 0.08, alpha: 1).setFill()
        path.fill()
        UIColor(white: 1, alpha: 0.08).setStroke()
        path.lineWidth = 1
        path.stroke()

        var y = box.minY + 18
        let visible = Array(lines.suffix(8))
        for (idx, line) in visible.enumerated() {
            let isLast = idx == visible.count - 1
            let color: UIColor = isLast ? accent : UIColor(white: 0.78, alpha: 1)
            let text = "> \(line)" as NSString
            text.draw(
                at: CGPoint(x: box.minX + 18, y: y),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium),
                    .foregroundColor: color,
                ]
            )
            y += 28
            if y > box.maxY - 24 { break }
        }

        if let logo = UIImage(named: "AppLogo") {
            let logoSize: CGFloat = 44
            let logoRect = CGRect(
                x: rect.midX - logoSize / 2,
                y: rect.maxY - 72,
                width: logoSize,
                height: logoSize
            )
            let clip = UIBezierPath(roundedRect: logoRect, cornerRadius: 10)
            context.saveGState()
            clip.addClip()
            logo.draw(in: logoRect)
            context.restoreGState()
        }

        ("Made by UNlicense" as NSString).draw(
            at: CGPoint(x: rect.minX + 28, y: rect.maxY - 28),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: UIColor(white: 0.4, alpha: 1),
            ]
        )
    }

    private static func drawProgressPanel(in rect: CGRect, model: ProgressModel, context: CGContext) {
        // Soft gradient-ish fill
        UIColor(red: 0.10, green: 0.14, blue: 0.22, alpha: 1).setFill()
        context.fill(rect)

        (model.appName as NSString).draw(
            at: CGPoint(x: rect.minX + 28, y: rect.minY + 28),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 26, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
        )

        let iconSide: CGFloat = 220
        let iconRect = CGRect(
            x: rect.midX - iconSide / 2,
            y: rect.midY - iconSide / 2 - 10,
            width: iconSide,
            height: iconSide
        )
        let iconPath = UIBezierPath(roundedRect: iconRect, cornerRadius: 48)
        context.saveGState()
        iconPath.addClip()
        if let icon = model.icon {
            icon.draw(in: iconRect)
        } else {
            UIColor(white: 0.2, alpha: 1).setFill()
            context.fill(iconRect)
            UIImage(systemName: "app.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                .draw(in: iconRect.insetBy(dx: 60, dy: 60))
        }
        context.restoreGState()

        // Progress ring
        let ringRect = iconRect.insetBy(dx: -10, dy: -10)
        let center = CGPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = min(ringRect.width, ringRect.height) / 2
        context.setLineWidth(10)
        context.setLineCap(.round)
        UIColor(white: 1, alpha: 0.18).setStroke()
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()

        let pct = max(0, min(100, model.percent))
        let start = -CGFloat.pi / 2
        let end = start + CGFloat(pct) / 100 * .pi * 2
        (model.failed ? UIColor.systemRed : UIColor.white).setStroke()
        context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        context.strokePath()

        let percentText = "\(pct)%" as NSString
        let font = UIFont.systemFont(ofSize: 44, weight: .bold)
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

        ("@UNlicense" as NSString).draw(
            at: CGPoint(x: rect.maxX - 120, y: rect.maxY - 40),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: UIColor(white: 0.55, alpha: 1),
            ]
        )
    }

    private static func drawBrandHeader(in rect: CGRect, trailing: String?) {
        if let logo = UIImage(named: "AppLogo") {
            let side: CGFloat = 22
            let logoRect = CGRect(x: rect.minX, y: rect.midY - side / 2, width: side, height: side)
            let path = UIBezierPath(roundedRect: logoRect, cornerRadius: 5)
            UIGraphicsGetCurrentContext()?.saveGState()
            path.addClip()
            logo.draw(in: logoRect)
            UIGraphicsGetCurrentContext()?.restoreGState()
        }
        ("UNlicense" as NSString).draw(
            at: CGPoint(x: rect.minX + 30, y: rect.midY - 9),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
        )
        if let trailing {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: UIColor(white: 0.55, alpha: 1),
            ]
            let size = (trailing as NSString).size(withAttributes: attrs)
            (trailing as NSString).draw(
                at: CGPoint(x: rect.maxX - size.width, y: rect.midY - size.height / 2),
                withAttributes: attrs
            )
        }
    }
}
