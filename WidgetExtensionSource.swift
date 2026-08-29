//
//  WidgetExtensionSource.swift
//
//  NOT part of any Xcode target yet — this is source to paste into a new
//  Widget Extension target once you create one. It is intentionally
//  self-contained (no dependency on the main app's files) so it can be
//  dropped in without touching target membership of existing files.
//
//  SETUP (in Xcode, ~5 minutes):
//  1. File > New > Target… > Widget Extension. Name it e.g. "EndarWidget".
//     Uncheck "Include Configuration Intent" (this widget is static, no config).
//  2. Xcode creates a new target with its own boilerplate Swift file
//     (e.g. EndarWidget.swift). Delete its contents and paste this whole
//     file's contents in instead.
//  3. Add the "App Groups" capability to BOTH targets (the main "endar" app
//     target AND the new widget target): select each target > Signing &
//     Capabilities > "+ Capability" > App Groups > add
//     "group.com.productivitycal.productivitycal" (same string on both).
//     This lets the widget read the streak data the main app already
//     writes to that App Group (the main app falls back to standard
//     UserDefaults until this App Group exists, so nothing breaks before
//     you do this step).
//  4. Build the widget scheme once, then long-press your home screen,
//     tap "+", find "productivitycal" and add the "streak" widget (comes
//     in a small size, just the streak, and a medium size that also shows
//     the last 7 days as colored dots).
//
//  Tapping the widget opens the app via the "productivitycal://log" deep
//  link, which jumps straight to the home tab to log today's mood — see
//  `.onOpenURL` in endarApp.swift and the CFBundleURLTypes entry for the
//  "productivitycal" scheme in Info.plist (both already wired up on the
//  main app side, nothing else to do there).
//
//  If Xcode's template already named things differently (kind string,
//  bundle struct name), it's fine to keep this file's names — just make
//  sure only ONE `@main` exists in the widget target.
//

import WidgetKit
import SwiftUI

// MARK: - Shared reader
// Reads the same UserDefaults key ("moodStore.v1") the main app writes to,
// via the same App Group suite. Deliberately duplicated here (not shared
// via target membership) to keep this file paste-and-go.

private enum EndarSharedStorage {
    static let appGroupID = "group.com.productivitycal.productivitycal"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

/// Mirrors `Mood.tint` from the main app's ContentView.swift. Kept as a plain
/// raw-value lookup (rather than importing the real `Mood` enum) so this file
/// has zero dependency on the main app target.
private enum EndarMoodColor {
    static func tint(forRawValue raw: String) -> Color? {
        switch raw {
        case "work_productive":
            return Color(red: 0x5E / 255, green: 0xBE / 255, blue: 0x7D / 255)
        case "personally_productive":
            return Color(red: 0x4D / 255, green: 0x83 / 255, blue: 0xFF / 255)
        case "not_productive":
            return Color(red: 0xEB / 255, green: 0x57 / 255, blue: 0x57 / 255)
        default:
            return nil
        }
    }
}

private enum EndarStreakReader {
    private static let storageKey = "moodStore.v1"

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func loadStoredMoods() -> [String: String] {
        guard let data = EndarSharedStorage.defaults.data(forKey: storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func key(for date: Date) -> String {
        dayFormatter.string(from: Calendar.current.startOfDay(for: date))
    }

    static func isTodayFilled() -> Bool {
        let moods = loadStoredMoods()
        return moods[key(for: Date())] != nil
    }

    static func currentStreak(asOf referenceDate: Date = Date()) -> Int {
        let moods = loadStoredMoods()
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: referenceDate)

        if moods[key(for: cursor)] == nil {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while moods[key(for: cursor)] != nil {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// The last `count` days (oldest first, today last) as raw mood values —
    /// `nil` for a blank/unfilled day. Used for the medium widget's mini-preview.
    static func recentDays(count: Int = 7, endingAt referenceDate: Date = Date()) -> [String?] {
        let moods = loadStoredMoods()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        return stride(from: count - 1, through: 0, by: -1).compactMap { offset -> String? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return moods[key(for: day)]
        }
    }
}

// MARK: - Timeline

struct EndarStreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let isTodayFilled: Bool
    /// Last 7 days, oldest first, today last. `nil` entries are blank days.
    let recentDays: [String?]
}

struct EndarStreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> EndarStreakEntry {
        EndarStreakEntry(
            date: Date(),
            streak: 3,
            isTodayFilled: false,
            recentDays: [nil, "work_productive", "work_productive", "personally_productive", "work_productive", "work_productive", nil]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (EndarStreakEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EndarStreakEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh at the next midnight so the streak / today status stays accurate
        // even if the app itself isn't opened.
        let midnight = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }

    private func currentEntry() -> EndarStreakEntry {
        EndarStreakEntry(
            date: Date(),
            streak: EndarStreakReader.currentStreak(),
            isTodayFilled: EndarStreakReader.isTodayFilled(),
            recentDays: EndarStreakReader.recentDays()
        )
    }
}

// MARK: - View

private struct MoodDotStrip: View {
    let days: [String?]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, raw in
                Circle()
                    .fill(dotColor(for: raw))
                    .frame(width: 10, height: 10)
            }
        }
    }

    private func dotColor(for raw: String?) -> Color {
        guard let raw, let tint = EndarMoodColor.tint(forRawValue: raw) else {
            return Color.secondary.opacity(0.25)
        }
        return tint
    }
}

struct EndarStreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: EndarStreakEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumBody
            default:
                smallBody
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            streakHeader
            Spacer(minLength: 0)
            statusLine
        }
    }

    private var mediumBody: some View {
        HStack(alignment: .center, spacing: 20) {
            streakHeader

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                MoodDotStrip(days: entry.recentDays)
                statusLine
            }
        }
    }

    private var streakHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: entry.streak > 0 ? "flame.fill" : "flame")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(entry.streak > 0 ? Color(red: 1.0, green: 0.36, blue: 0.0) : .secondary)

            Text("\(entry.streak)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("day streak")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var statusLine: some View {
        Text(entry.isTodayFilled ? "today done" : "tap to log today")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(entry.isTodayFilled ? .green : .orange)
    }
}

struct EndarStreakWidget: Widget {
    let kind = "EndarStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EndarStreakProvider()) { entry in
            EndarStreakWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "productivitycal://log"))
        }
        .configurationDisplayName("streak")
        .description("shows your current daily streak, plus the last 7 days at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct EndarWidgetBundle: WidgetBundle {
    var body: some Widget {
        EndarStreakWidget()
    }
}
