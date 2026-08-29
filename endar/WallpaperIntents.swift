import SwiftUI

#if canImport(AppIntents)
import AppIntents
import UniformTypeIdentifiers
#endif

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Guide UI (Set Tab)

struct WallpaperAutomationGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWallpaperSetupStep = 0
    @State private var stepPulse = false

    // A light, airy background (rather than following the user's own theme
    // setting) so each dark tutorial screenshot reads as a floating card.
    private let palette = AppTheme.light.palette

    /// One motivating line per screenshot step, framing the mechanical
    /// instruction baked into the photo as progress toward a bigger goal.
    /// Index-aligned with `WallpaperSetupGuideContent.steps` (the completion
    /// step has no entry, it has its own message already).
    private static let stepCaptions: [String] = [
        "two minutes, and this runs itself from now on.",
        "let's build the routine that keeps you consistent.",
        "pick when it happens, then forget about it.",
        "your daily nudge, set once.",
        "so it runs with zero taps, every time.",
        "now let's connect productivitycal to your lock screen.",
        "this pulls your progress straight from the app.",
        "and this puts it right where you'll see it.",
        "two actions, working together automatically.",
        "this is the part that matters most.",
        "just double check this one detail.",
        "save it, and you're one tap from a life you can see."
    ]

    private var steps: [WallpaperSetupStep] { WallpaperSetupGuideContent.steps }
    private var isOnLastStep: Bool { selectedWallpaperSetupStep == steps.count - 1 }
    private var progress: Double {
        guard steps.count > 1 else { return 1 }
        return Double(selectedWallpaperSetupStep + 1) / Double(steps.count)
    }
    private var currentCaption: String? {
        Self.stepCaptions.indices.contains(selectedWallpaperSetupStep) ? Self.stepCaptions[selectedWallpaperSetupStep] : nil
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("setup instructions")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                WallpaperSetupCarousel(
                    palette: palette,
                    selectedStep: $selectedWallpaperSetupStep,
                    steps: steps
                )
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(
                palette.background
                    .ignoresSafeArea()
            )
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Text("step \(selectedWallpaperSetupStep + 1) of \(steps.count)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .scaleEffect(stepPulse ? 1.06 : 1.0)

                    if let currentCaption {
                        Text(currentCaption)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .id(selectedWallpaperSetupStep)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(palette.border)
                            .frame(height: 6)

                        GeometryReader { proxy in
                            Capsule()
                                .fill(palette.textPrimary)
                                .frame(width: proxy.size.width * progress, height: 6)
                                .animation(.easeOut(duration: 0.2), value: progress)
                        }
                        .frame(height: 6)
                    }

                    if isOnLastStep {
                        Button {
                            dismiss()
                        } label: {
                            Text("done")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(palette.background)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(palette.textPrimary)
                        )
                    } else {
                        Button {
                            openShortcuts()
                        } label: {
                            Text("open shortcuts")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(palette.background)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(palette.textPrimary)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(
                    palette.background
                        .opacity(0.96)
                        .ignoresSafeArea(edges: .bottom)
                )
                .animation(.easeInOut(duration: 0.22), value: selectedWallpaperSetupStep)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("close") { dismiss() }
                        .foregroundColor(palette.textPrimary)
                }
            }
            .onChange(of: selectedWallpaperSetupStep) { _, _ in
                Haptics.light()
                withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
                    stepPulse = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.65)) {
                        stepPulse = false
                    }
                }
            }
        }
    }

    private func openShortcuts() {
        #if canImport(UIKit)
        guard let url = URL(string: "shortcuts://") else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - App Intent (Wallpaper Generator)

#if canImport(AppIntents)

// MARK: AppIntent Enums

enum WallpaperDeviceOption: String, CaseIterable, AppEnum {
    case fromSettings = "From Settings"
    // Pixel presets (scale=1 render) so Shortcuts / Set Wallpaper doesn't treat the image as a tiny thumbnail.
    // NOTE: Avoid using the word "iPhone" in App Intents *metadata strings* (title/description/display reps)
    // to prevent App Store Connect ITMS-90626.
    case iphoneMini = "Mini (1080x2340)"
    case iphoneStandard = "6.1\" (1170x2532)"
    case iphoneStandardNew = "6.1\" (1179x2556)"
    case iphoneProNew = "6.3\" (1206x2622)"
    case iphoneLarge = "6.7\" (1290x2796)"
    case iphoneLargeProNew = "6.9\" (1320x2868)"
    case generic = "Default (1170x2532)"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Device"

    static var caseDisplayRepresentations: [WallpaperDeviceOption: DisplayRepresentation] = [
        .fromSettings: "From Settings",
        .iphoneMini: "Mini (1080x2340)",
        .iphoneStandard: "6.1\" (1170x2532)",
        .iphoneStandardNew: "6.1\" (1179x2556)",
        .iphoneProNew: "6.3\" (1206x2622)",
        .iphoneLarge: "6.7\" (1290x2796)",
        .iphoneLargeProNew: "6.9\" (1320x2868)",
        .generic: "Default (1170x2532)"
    ]
}

// MARK: Generate Wallpaper Intent (writes deterministic file + returns it)

struct GenerateEndarWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "generate wallpaper"
    static var description = IntentDescription("generate wallpaper using app settings.")
    static var isDiscoverable: Bool { PremiumAccess.isPremium }

    static var parameterSummary: some ParameterSummary {
        Summary("generate wallpaper")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        try WallpaperPremiumGate.requirePremiumAccess()

        let resolved = WallpaperResolvedSettings.resolve()

        let calendar = Calendar.current
        let today = Date()
        let summary = WallpaperPeriodSummary.make(period: resolved.period, today: today, calendar: calendar)

        let moodData = WallpaperMoodData.load()
        let uiImage = try WallpaperImageRenderer.render(
            canvasSize: resolved.canvasSize,
            summary: summary,
            includeProgress: true,
            moodData: moodData
        )

        guard let data = uiImage.pngData() else {
            throw NSError(domain: "endar.wallpaper", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
        }

        // Write to deterministic on-device path (visible in Files when UIFileSharingEnabled is true).
        // This also enables Shortcuts to "Get File" from: On My Device -> endar -> endar-wallpaper.png
        _ = try Self.writeDeterministicWallpaperFile(data: data)

        // For Shortcuts chaining (Quick Look / Set Wallpaper), returning in-memory data is the most reliable.
        // A fileURL inside the app sandbox can fail to open in Shortcuts (shows "no such file").
        var file = IntentFile(data: data, filename: "endar-wallpaper.png", type: UTType.png)
        file.removedOnCompletion = false
        return .result(value: file)
    }

    /// Writes: On My Device → endar → endar-wallpaper.png
    /// NOTE: To see this folder in the Files app:
    /// - UIFileSharingEnabled = YES
    /// - LSSupportsOpeningDocumentsInPlace = YES
    @MainActor
    fileprivate static func writeDeterministicWallpaperFile(data: Data) throws -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!

        // Keep it at the root of Documents so the Shortcuts path is stable and simple.
        let url = docs.appendingPathComponent("endar-wallpaper.png", isDirectory: false)
        try data.write(to: url, options: [.atomic])

        // Automations often run while the device is locked; avoid "file not found / can't open" issues caused by
        // full data protection.
        // This makes the file readable after the device has been unlocked at least once since boot.
        try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        return url
    }
}

// MARK: - Shareable Preview (Set Tab "share my year")

/// Renders the same wallpaper image used by the automation, for the in-app "share my year" button.
@MainActor
func renderShareableWallpaperImage() throws -> UIImage {
    let resolved = WallpaperResolvedSettings.resolve()
    let calendar = Calendar.current
    let today = Date()
    let summary = WallpaperPeriodSummary.make(period: resolved.period, today: today, calendar: calendar)
    let moodData = WallpaperMoodData.load()
    return try WallpaperImageRenderer.render(
        canvasSize: resolved.canvasSize,
        summary: summary,
        includeProgress: true,
        moodData: moodData
    )
}

// MARK: Generate Wallpaper (Save File + Return Path)

/// This variant exists for Shortcuts automations that want to:
/// 1) Generate and save the wallpaper to a stable Files path
/// 2) "Get File" by path
/// 3) Convert to Image
/// 4) Set as wallpaper
struct GenerateEndarWallpaperFilePathIntent: AppIntent {
    static var title: LocalizedStringResource = "generate wallpaper file"
    static var description = IntentDescription("generate and overwrite wallpaper file.")
    static var isDiscoverable: Bool { PremiumAccess.isPremium }

    static var parameterSummary: some ParameterSummary {
        Summary("generate wallpaper file")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try WallpaperPremiumGate.requirePremiumAccess()

        let resolved = WallpaperResolvedSettings.resolve()

        let calendar = Calendar.current
        let today = Date()
        let summary = WallpaperPeriodSummary.make(period: resolved.period, today: today, calendar: calendar)

        let moodData = WallpaperMoodData.load()
        let uiImage = try WallpaperImageRenderer.render(
            canvasSize: resolved.canvasSize,
            summary: summary,
            includeProgress: true,
            moodData: moodData
        )

        guard let data = uiImage.pngData() else {
            throw NSError(domain: "endar.wallpaper", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
        }

        // Same deterministic path as the image-returning intent.
        _ = try GenerateEndarWallpaperIntent.writeDeterministicWallpaperFile(data: data)

        // This is the path expected by Shortcuts "Get File" when "Get File from" is set to "On My Device".
        // It matches what you see under Files: On My Device -> endar -> endar-wallpaper.png
        return .result(value: "endar/endar-wallpaper.png")
    }
}

// MARK: Helpers

private enum WallpaperPremiumGate {
    static func requirePremiumAccess() throws {
        guard PremiumAccess.isPremium else {
            throw NSError(
                domain: "endar.premium",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Premium required for wallpaper automation."]
            )
        }
    }
}

private enum WallpaperResolvedPeriod {
    case year
}

private struct WallpaperResolvedSettings {
    let period: WallpaperResolvedPeriod
    let canvasSize: CGSize

    static func resolve() -> WallpaperResolvedSettings {
        let periodResolved: WallpaperResolvedPeriod = .year
        let deviceResolved: WallpaperDeviceOption = {
            let raw = UserDefaults.standard.string(forKey: "wallpaper.device.v1") ?? "iPhone 17"
            let lowered = raw.lowercased()
            if lowered.contains("mini") { return .iphoneMini }
            if lowered.contains("17 pro max") || lowered.contains("17 max") || lowered.contains("16 pro max") { return .iphoneLargeProNew }
            if lowered.contains("pro max") || lowered.contains("plus") { return .iphoneLarge }
            if lowered.contains("max") { return .iphoneLarge }
            if lowered.contains("17 pro") || lowered == "iphone 17" || lowered.contains("16 pro") { return .iphoneProNew }
            if lowered.contains("16e") { return .iphoneStandard }
            if lowered.contains("1179") || lowered.contains("16") || lowered.contains("15") { return .iphoneStandardNew }
            if lowered.contains("pro") { return .iphoneStandard }
            return .iphoneStandard
        }()

        let canvasSize: CGSize = {
            func upscaledCanvas(for base: CGSize) -> CGSize {
                let targetHeight: CGFloat = 3840
                let scale = targetHeight / max(base.height, 1)
                let width = CGFloat(Int(round(base.width * scale)))
                return CGSize(width: width, height: targetHeight)
            }

            switch deviceResolved {
            case .iphoneMini:
                return upscaledCanvas(for: CGSize(width: 1080, height: 2340))
            case .iphoneLargeProNew:
                return upscaledCanvas(for: CGSize(width: 1320, height: 2868))
            case .iphoneLarge:
                return upscaledCanvas(for: CGSize(width: 1290, height: 2796))
            case .iphoneProNew:
                return upscaledCanvas(for: CGSize(width: 1206, height: 2622))
            case .iphoneStandardNew:
                return upscaledCanvas(for: CGSize(width: 1179, height: 2556))
            case .iphoneStandard:
                return upscaledCanvas(for: CGSize(width: 1170, height: 2532))
            case .generic, .fromSettings:
                return upscaledCanvas(for: CGSize(width: 1170, height: 2532))
            }
        }()

        return WallpaperResolvedSettings(period: periodResolved, canvasSize: canvasSize)
    }
}

private enum WallpaperDotShapeStyle: String {
    case squircle
    case circle

    static func loadFromSettings() -> WallpaperDotShapeStyle {
        let raw = (UserDefaults.standard.string(forKey: "wallpaper.dotShape.v1") ?? "squircle").lowercased()
        if raw == "circle" || raw == "round" {
            return .circle
        }
        return .squircle
    }
}

private struct WallpaperPeriodSummary {
    let columns: Int
    let spacingRatio: CGFloat
    let startDate: Date
    let totalDays: Int
    let daysLeft: Int
    let progress: Double

    static func make(period _: WallpaperResolvedPeriod, today: Date, calendar: Calendar) -> WallpaperPeriodSummary {
        let todayStart = calendar.startOfDay(for: today)
        let startDate = calendar.dateInterval(of: .year, for: today)?.start ?? todayStart
        let totalDays = calendar.range(of: .day, in: .year, for: today)?.count ?? 365
        let columns = 19
        let spacingRatio: CGFloat = 0.50

        let elapsedDays = max(0, (calendar.dateComponents([.day], from: startDate, to: todayStart).day ?? 0) + 1)
        let clampedElapsed = min(elapsedDays, totalDays)
        let daysLeft = max(totalDays - clampedElapsed, 0)
        let progress = totalDays > 0 ? Double(clampedElapsed) / Double(totalDays) : 0

        return WallpaperPeriodSummary(
            columns: columns,
            spacingRatio: spacingRatio,
            startDate: startDate,
            totalDays: totalDays,
            daysLeft: daysLeft,
            progress: progress
        )
    }
}

private struct WallpaperMoodData {
    private let moods: [String: Mood]

    static func load() -> WallpaperMoodData {
        let key = "moodStore.v1"
        guard let data = SharedStorage.defaults.data(forKey: key) else {
            return WallpaperMoodData(moods: [:])
        }
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return WallpaperMoodData(moods: [:])
        }
        var mapped: [String: Mood] = [:]
        for (k, v) in decoded {
            if let mood = Mood.fromStoredValue(v) {
                mapped[k] = mood
            }
        }
        return WallpaperMoodData(moods: mapped)
    }

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func mood(for date: Date) -> Mood? {
        moods[Self.keyFormatter.string(from: date)]
    }
}

private enum WallpaperImageRenderer {
    @MainActor
    static func render(
        canvasSize: CGSize,
        summary: WallpaperPeriodSummary,
        includeProgress _: Bool,
        moodData: WallpaperMoodData
    ) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        return renderer.image { ctx in
            let cg = ctx.cgContext
            let w = canvasSize.width
            let h = canvasSize.height
            let dotShapeStyle = WallpaperDotShapeStyle.loadFromSettings()

            let backgroundColor = UIColor(red: 0x33 / 255.0, green: 0x33 / 255.0, blue: 0x33 / 255.0, alpha: 1.0)
            cg.setFillColor(backgroundColor.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))

            // Keep dots under the lock-screen clock and clear of the progress block below.
            let clockReferenceWidth = w * 0.70
            let gridWidth = min(w * 0.82, clockReferenceWidth)
            let gridHeight = h * 0.39
            let gridX = (w - gridWidth) / 2
            let gridY = h * 0.248

            let baseRows = Int(ceil(Double(summary.totalDays) / Double(summary.columns)))
            let rows = baseRows

            let denomW = CGFloat(summary.columns) + CGFloat(max(0, summary.columns - 1)) * summary.spacingRatio
            let denomH = CGFloat(rows) + CGFloat(max(0, rows - 1)) * summary.spacingRatio
            let dotW = gridWidth / max(denomW, 1)
            let dotH = gridHeight / max(denomH, 1)
            let dot = min(dotW, dotH)
            let spacing = dot * summary.spacingRatio

            let totalW = CGFloat(summary.columns) * dot + CGFloat(max(0, summary.columns - 1)) * spacing
            let totalH = CGFloat(rows) * dot + CGFloat(max(0, rows - 1)) * spacing
            let xOffset = max((gridWidth - totalW) / 2, 0)
            let yOffset = max((gridHeight - totalH) / 2, 0)

            func moodUIColor(_ mood: Mood) -> UIColor {
                switch mood {
                case .workProductive: return UIColor(red: 0x5E / 255.0, green: 0xBE / 255.0, blue: 0x7D / 255.0, alpha: 1)
                case .personallyProductive: return UIColor(red: 0x4D / 255.0, green: 0x83 / 255.0, blue: 0xFF / 255.0, alpha: 1)
                case .notProductive: return UIColor(red: 0xEB / 255.0, green: 0x57 / 255.0, blue: 0x57 / 255.0, alpha: 1)
                }
            }

            let totalCells = rows * summary.columns
            for index in 0..<totalCells {
                let date: Date? = {
                    guard index < summary.totalDays else { return nil }
                    return calendar.date(byAdding: .day, value: index, to: summary.startDate)
                }()
                let col = index % summary.columns
                let row = index / summary.columns

                let x = gridX + xOffset + CGFloat(col) * (dot + spacing)
                let y = gridY + yOffset + CGFloat(row) * (dot + spacing)
                let rect = CGRect(x: x, y: y, width: dot, height: dot)

                let fill: UIColor = {
                    guard let date else { return UIColor.white.withAlphaComponent(0.08) }
                    if let mood = moodData.mood(for: date) { return moodUIColor(mood) }
                    if date < todayStart { return UIColor.white.withAlphaComponent(0.88) }
                    return UIColor.white.withAlphaComponent(0.26)
                }()

                cg.setFillColor(fill.cgColor)
                let path: UIBezierPath = {
                    switch dotShapeStyle {
                    case .circle:
                        return UIBezierPath(ovalIn: rect)
                    case .squircle:
                        return UIBezierPath(
                            roundedRect: rect,
                            cornerRadius: max(dot * 0.22, 2)
                        )
                    }
                }()
                cg.addPath(path.cgPath)
                cg.fillPath()
            }

            let accent = UIColor(red: 1.0, green: 92.0 / 255.0, blue: 0.0, alpha: 1.0)
            let percentText = "· \(Int(round(summary.progress * 100)))%"
            let leftText = "\(summary.daysLeft)d left"
            let lineY = gridY + gridHeight + h * 0.03

            let fontSize = min(w * 0.07, 64)
            let leftAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: accent
            ]
            let rightAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.62)
            ]

            let leftSize = (leftText as NSString).size(withAttributes: leftAttr)
            let rightSize = (percentText as NSString).size(withAttributes: rightAttr)
            let totalTextW = leftSize.width + 14 + rightSize.width
            let textX = (w - totalTextW) / 2

            (leftText as NSString).draw(at: CGPoint(x: textX, y: lineY), withAttributes: leftAttr)
            (percentText as NSString).draw(at: CGPoint(x: textX + leftSize.width + 14, y: lineY), withAttributes: rightAttr)

            let barW = min(w * 0.56, 560)
            let barH = max(h * 0.0042, 10)
            let barX = (w - barW) / 2
            let barY = lineY + fontSize + h * 0.018

            let bgRect = CGRect(x: barX, y: barY, width: barW, height: barH)
            let fgRect = CGRect(x: barX, y: barY, width: max(barH * 1.4, barW * summary.progress), height: barH)

            cg.setFillColor(UIColor.white.withAlphaComponent(0.22).cgColor)
            cg.addPath(UIBezierPath(roundedRect: bgRect, cornerRadius: barH / 2).cgPath)
            cg.fillPath()

            cg.setFillColor(UIColor.white.withAlphaComponent(0.92).cgColor)
            cg.addPath(UIBezierPath(roundedRect: fgRect, cornerRadius: barH / 2).cgPath)
            cg.fillPath()
        }
    }
}

#endif

// MARK: - Optional App Shortcut Phrases

#if canImport(AppIntents)
@available(iOS 17.0, *)
struct EndarAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        guard PremiumAccess.isPremium else { return [] }

        return [
            AppShortcut(
                intent: GenerateEndarWallpaperIntent(),
                phrases: [
                    "generate wallpaper in \(.applicationName)",
                    "update my wallpaper in \(.applicationName)"
                ],
                shortTitle: "generate wallpaper",
                systemImageName: "calendar"
            )
        ]
    }

    static var shortcutTileColor: ShortcutTileColor { .grayBlue }
}
#endif
