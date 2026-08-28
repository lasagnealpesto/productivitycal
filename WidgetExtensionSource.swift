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
//     tap "+", find "productivitycal" and add the "streak" widget.
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

    private static func isFilled(_ date: Date) -> Bool {
        guard let data = EndarSharedStorage.defaults.data(forKey: storageKey) else { return false }
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return false }
        let key = dayFormatter.string(from: Calendar.current.startOfDay(for: date))
        return decoded[key] != nil
    }

    static func isTodayFilled() -> Bool {
        isFilled(Date())
    }

    static func currentStreak(asOf referenceDate: Date = Date()) -> Int {
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: referenceDate)

        if !isFilled(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while isFilled(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}

// MARK: - Timeline

struct EndarStreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let isTodayFilled: Bool
}

struct EndarStreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> EndarStreakEntry {
        EndarStreakEntry(date: Date(), streak: 3, isTodayFilled: false)
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
            isTodayFilled: EndarStreakReader.isTodayFilled()
        )
    }
}

// MARK: - View

struct EndarStreakWidgetView: View {
    var entry: EndarStreakEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(entry.streak > 0 ? Color(red: 1.0, green: 0.36, blue: 0.0) : .secondary)

            Text("\(entry.streak)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("day streak")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(entry.isTodayFilled ? "today done" : "tap to log today")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(entry.isTodayFilled ? .green : .orange)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct EndarStreakWidget: Widget {
    let kind = "EndarStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EndarStreakProvider()) { entry in
            EndarStreakWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("streak")
        .description("shows your current daily streak.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct EndarWidgetBundle: WidgetBundle {
    var body: some Widget {
        EndarStreakWidget()
    }
}
