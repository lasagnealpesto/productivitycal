import SwiftUI
import Combine
import UserNotifications
import UIKit

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    static let appAccent = Color(hex: 0xFF5C00)
}

/// Storage shared with the (not-yet-added) home screen widget via an App Group.
/// Falls back to `.standard` until the "group.com.productivitycal.productivitycal"
/// App Group is added to this target's entitlements, so this is safe to ship before that.
enum SharedStorage {
    static let appGroupID = "group.com.productivitycal.productivitycal"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

enum Haptics {
    static func light() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var palette: AppPalette {
        switch self {
        case .dark:
            return AppPalette(
                background: Color(hex: 0x333333),
                surface: Color(hex: 0x3D3D3D),
                textPrimary: Color(hex: 0xF3F3F3),
                textSecondary: Color(hex: 0xF3F3F3, alpha: 0.7),
                border: Color(hex: 0xF3F3F3, alpha: 0.18),
                accent: Color(hex: 0xF3F3F3)
            )
        case .light:
            return AppPalette(
                background: Color(hex: 0xF3F3F3),
                surface: Color(hex: 0xE9E9E9),
                textPrimary: Color(hex: 0x333333),
                textSecondary: Color(hex: 0x333333, alpha: 0.7),
                border: Color(hex: 0x333333, alpha: 0.18),
                accent: Color(hex: 0x333333)
            )
        }
    }
}

struct AppPalette {
    let background: Color
    let surface: Color
    let textPrimary: Color
    let textSecondary: Color
    let border: Color
    let accent: Color
}

struct ContentView: View {
    let onLogout: () -> Void
    let onDeleteAccount: () -> Void

    @State private var selectedTab: Tab = .home
    @StateObject private var moodStore = MoodStore()
    @AppStorage("theme.mode.v1") private var themeRaw: String = AppTheme.dark.rawValue

    enum Tab { case home, calendar, set }

    init(
        onLogout: @escaping () -> Void = {},
        onDeleteAccount: @escaping () -> Void = {}
    ) {
        self.onLogout = onLogout
        self.onDeleteAccount = onDeleteAccount
    }

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .dark
    }

    private var palette: AppPalette {
        theme.palette
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                palette: palette,
                onLogout: onLogout,
                onDeleteAccount: onDeleteAccount
            )
                .environmentObject(moodStore)
                .tabItem {
                    Label("home", systemImage: "house")
                }
                .tag(Tab.home)

            CalendarView(themeRaw: $themeRaw, palette: palette)
                .environmentObject(moodStore)
                .tabItem {
                    Label("calendar", systemImage: "calendar")
                }
                .tag(Tab.calendar)

            SetView(themeRaw: $themeRaw, palette: palette)
                .tabItem {
                    Label("set", systemImage: "slider.horizontal.3")
                }
                .tag(Tab.set)
        }
        .tint(palette.accent)
        .toolbarBackground(palette.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(theme == .dark ? .dark : .light)
    }
}

enum Mood: String, CaseIterable, Identifiable, Codable {
    case workProductive = "work_productive"
    case personallyProductive = "personally_productive"
    case notProductive = "not_productive"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workProductive: return "work productive"
        case .personallyProductive: return "personally productive"
        case .notProductive: return "not productive"
        }
    }

    var subtitle: String {
        switch self {
        case .workProductive: return "if you are closer to your goals"
        case .personallyProductive: return "if you dedicated quality time to your personal life"
        case .notProductive: return "if you lost your day scrolling / other"
        }
    }

    var shortLabel: String {
        switch self {
        case .workProductive: return "work"
        case .personallyProductive: return "personal"
        case .notProductive: return "not"
        }
    }

    var tint: Color {
        switch self {
        case .workProductive: return Color(hex: 0x5EBE7D)
        case .personallyProductive: return Color(hex: 0x4D83FF)
        case .notProductive: return Color(hex: 0xEB5757)
        }
    }

    var systemImage: String {
        switch self {
        case .workProductive: return "briefcase.fill"
        case .personallyProductive: return "person.fill"
        case .notProductive: return "xmark"
        }
    }

    static func fromStoredValue(_ rawValue: String) -> Mood? {
        if let mood = Mood(rawValue: rawValue) {
            return mood
        }

        switch rawValue.lowercased() {
        case "productive":
            return .workProductive
        case "mid":
            return .personallyProductive
        case "lazy":
            return .notProductive
        default:
            return nil
        }
    }
}

final class MoodStore: ObservableObject {
    @Published private(set) var moods: [String: Mood] = [:]

    private let storageKey = "moodStore.v1"
    private let calendar = Calendar.current

    init() {
        load()
    }

    func mood(for date: Date) -> Mood? {
        moods[key(for: date)]
    }

    func setMood(_ mood: Mood?, for date: Date) {
        let key = key(for: date)
        if let mood {
            moods[key] = mood
        } else {
            moods.removeValue(forKey: key)
        }
        save()
        DailyMoodNotificationScheduler.shared.refreshScheduledNotifications()
    }

    /// Sets every day in `dates` that is today or earlier to `mood`, overwriting
    /// any existing value. For quickly filling in a whole month at once.
    func fillPastDays(_ dates: [Date], with mood: Mood) {
        let today = calendar.startOfDay(for: Date())
        for date in dates {
            let day = calendar.startOfDay(for: date)
            guard day <= today else { continue }
            moods[key(for: day)] = mood
        }
        save()
        DailyMoodNotificationScheduler.shared.refreshScheduledNotifications()
    }

    private func countsTowardStreak(_ date: Date) -> Bool {
        switch mood(for: date) {
        case .workProductive, .personallyProductive: return true
        case .notProductive, .none: return false
        }
    }

    func currentStreak(asOf referenceDate: Date = Date()) -> Int {
        var cursor = calendar.startOfDay(for: referenceDate)

        if !countsTowardStreak(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while countsTowardStreak(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    private func key(for date: Date) -> String {
        Self.keyFormatter.string(from: calendar.startOfDay(for: date))
    }

    private func load() {
        guard let data = SharedStorage.defaults.data(forKey: storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }

        var mapped: [String: Mood] = [:]
        for (key, raw) in decoded {
            if let mood = Mood.fromStoredValue(raw) {
                mapped[key] = mood
            }
        }
        moods = mapped
    }

    private func save() {
        let encoded = moods.mapValues { $0.rawValue }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        SharedStorage.defaults.set(data, forKey: storageKey)
    }

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

final class DailyMoodNotificationScheduler {
    static let shared = DailyMoodNotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let calendar = Calendar.current
    private let bodyText = "how was your day?"
    private let reminderHour = 18
    private let horizonDays = 21
    private let moodStorageKey = "moodStore.v1"
    private let sixPMPrefix = "endar.daily.1800."
    private var hasConfigured = false

    private init() {}

    func configureIfNeeded() {
        guard !hasConfigured else { return }
        hasConfigured = true

        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { return }
                    self.refreshScheduledNotifications()
                }
            case .authorized, .provisional, .ephemeral:
                self.refreshScheduledNotifications()
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    func refreshScheduledNotifications() {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional ||
                settings.authorizationStatus == .ephemeral else {
                return
            }

            self.center.getPendingNotificationRequests { [weak self] requests in
                guard let self else { return }

                let managedIds = requests
                    .map(\.identifier)
                    .filter { $0.hasPrefix(self.sixPMPrefix) }
                if !managedIds.isEmpty {
                    self.center.removePendingNotificationRequests(withIdentifiers: managedIds)
                }

                self.scheduleWindow()
            }
        }
    }

    private func scheduleWindow() {
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)

        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }

            let isToday = calendar.isDate(day, inSameDayAs: now)
            if !isToday || !hasMoodSelected(on: day) {
                scheduleNotification(hour: reminderHour, for: day, prefix: sixPMPrefix)
            }
        }
    }

    private func scheduleNotification(hour: Int, for day: Date, prefix: String) {
        guard let fireDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return }
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = bodyText
        content.body = ""
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let id = "\(prefix)\(dayKey(for: day))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    private func hasMoodSelected(on day: Date) -> Bool {
        guard let data = SharedStorage.defaults.data(forKey: moodStorageKey) else { return false }
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return false }
        let key = dayKey(for: day)
        guard let raw = decoded[key] else { return false }
        return Mood.fromStoredValue(raw) != nil
    }

    private func dayKey(for day: Date) -> String {
        Self.dayFormatter.string(from: calendar.startOfDay(for: day))
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct HomeView: View {
    @EnvironmentObject private var moodStore: MoodStore

    @AppStorage("theme.mode.v1") private var themeRaw: String = AppTheme.dark.rawValue
    let palette: AppPalette
    let onLogout: () -> Void
    let onDeleteAccount: () -> Void

    private let today = Date()
    @State private var showConfirmAction = false
    @State private var pendingAccountAction: AccountAction?
    @State private var confirmingMood: Mood?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    AccountActionsMenu(palette: palette) { action in
                        pendingAccountAction = action
                        showConfirmAction = true
                    }

                    Spacer()

                    ThemeToggle(themeRaw: $themeRaw, palette: palette)
                }

                Spacer(minLength: 20)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("how was your day?")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)

                        Spacer()

                        let streak = moodStore.currentStreak(asOf: today)
                        if streak > 0 {
                            StreakBadge(streak: streak, palette: palette)
                        }
                    }

                    ForEach(Mood.allCases) { mood in
                        MoodOptionCard(
                            mood: mood,
                            isSelected: moodStore.mood(for: today) == mood,
                            palette: palette,
                            isConfirming: confirmingMood == mood,
                            confirmationMessage: confirmationMessage(for: mood)
                        ) {
                            selectMood(mood)
                        }
                    }
                }
                .frame(maxWidth: 760)

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .background(BackgroundView(palette: palette))
            .alert(
                pendingAccountAction?.confirmTitle ?? "confirm",
                isPresented: $showConfirmAction,
                presenting: pendingAccountAction
            ) { action in
                Button("cancel", role: .cancel) {}
                Button(action.confirmCTA, role: .destructive) {
                    switch action {
                    case .logout:
                        onLogout()
                    case .deleteAccount:
                        onDeleteAccount()
                    }
                }
            } message: { action in
                Text(action.confirmMessage)
            }
        }
    }

    private func selectMood(_ mood: Mood) {
        moodStore.setMood(mood, for: today)
        Haptics.success()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            confirmingMood = mood
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.3)) {
                confirmingMood = nil
            }
        }
    }

    private func confirmationMessage(for mood: Mood) -> String {
        switch mood {
        case .workProductive:
            return "you killed it today"
        case .personallyProductive:
            return "nice job — taking time for yourself does you good"
        case .notProductive:
            return "you'll catch up tomorrow — i believe in you"
        }
    }
}

private struct StreakBadge: View {
    let streak: Int
    let palette: AppPalette
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .foregroundStyle(Color(hex: 0xFF5C00))
            Text("\(streak) day\(streak == 1 ? "" : "s")")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(palette.surface)
        )
        .overlay(
            Capsule()
                .stroke(palette.border, lineWidth: 1)
        )
        .scaleEffect(pulse ? 1.2 : 1.0)
        .accessibilityLabel("\(streak) day streak")
        .onChange(of: streak) { _, _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                pulse = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.25)) {
                    pulse = false
                }
            }
        }
    }
}

private enum AccountAction {
    case logout
    case deleteAccount

    var confirmTitle: String {
        switch self {
        case .logout:
            return "confirm logout"
        case .deleteAccount:
            return "confirm account deletion"
        }
    }

    var confirmMessage: String {
        switch self {
        case .logout:
            return "do you really want to log out of the app?"
        case .deleteAccount:
            return "do you really want to delete the account on this device? this action also removes local data."
        }
    }

    var confirmCTA: String {
        switch self {
        case .logout:
            return "confirm logout"
        case .deleteAccount:
            return "delete account"
        }
    }
}

private struct MoodOptionCard: View {
    let mood: Mood
    let isSelected: Bool
    let palette: AppPalette
    let isConfirming: Bool
    let confirmationMessage: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                normalContent
                    .opacity(isConfirming ? 0 : 1)

                Text(confirmationMessage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity(isConfirming ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 112, alignment: .center)
            .padding(16)
            .background(
                ZStack {
                    Group {
                        if #available(iOS 26.0, *) {
                            Color.clear
                                .glassEffect(
                                    .regular.tint(palette.background.opacity(0.08)),
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                    }

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(mood.tint.opacity(isConfirming ? 1 : (isSelected ? 0.20 : 0.08)))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected || isConfirming ? mood.tint.opacity(0.95) : palette.border, lineWidth: isSelected || isConfirming ? 1.6 : 1)
            )
            .scaleEffect(isConfirming ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private var normalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                MoodIconPill(mood: mood, palette: palette)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(isSelected ? mood.tint : palette.textSecondary.opacity(0.7))
                    .frame(width: 26, height: 26)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(mood.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)

                Text(mood.subtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(1.2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.leading, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MoodIconPill: View {
    let mood: Mood
    let palette: AppPalette

    var body: some View {
        Image(systemName: mood.systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(mood.tint)
            .frame(width: 50, height: 30)
            .background(
                Group {
                    if #available(iOS 26.0, *) {
                        Color.clear
                            .glassEffect(
                                .regular.tint(palette.background.opacity(0.06)),
                                in: Capsule()
                            )
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }
                }
            )
            .overlay(
                Capsule()
                    .stroke(palette.border, lineWidth: 0.9)
            )
    }
}

private struct CalendarView: View {
    @EnvironmentObject private var moodStore: MoodStore

    @Binding var themeRaw: String
    let palette: AppPalette

    @State private var selectedYear: Int
    @State private var selectedMonth: Int
    @State private var isShowingQuickFill = false
    @State private var dragOffset: CGFloat = 0

    private let calendar = Calendar.current

    init(themeRaw: Binding<String>, palette: AppPalette) {
        let today = Date()
        let cal = Calendar.current
        _themeRaw = themeRaw
        _selectedYear = State(initialValue: cal.component(.year, from: today))
        _selectedMonth = State(initialValue: cal.component(.month, from: today))
        self.palette = palette
    }

    private var monthStart: Date {
        calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)) ?? Date()
    }

    private var yearOptions: [Int] {
        let current = calendar.component(.year, from: Date())
        return Array((current - 5)...(current + 1)).reversed()
    }

    private var selectedMonthName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let names = formatter.monthSymbols ?? []
        guard selectedMonth >= 1, selectedMonth <= names.count else { return "" }
        return names[selectedMonth - 1].lowercased()
    }

    private func stepMonth(by delta: Int) {
        var newMonth = selectedMonth + delta
        var newYear = selectedYear

        if newMonth > 12 {
            newMonth = 1
            newYear += 1
        } else if newMonth < 1 {
            newMonth = 12
            newYear -= 1
        }

        selectedMonth = newMonth
        selectedYear = newYear
    }

    /// Slides the current month out — continuing smoothly from wherever `dragOffset`
    /// already is (e.g. mid-drag) — then swaps to the new month and slides it in
    /// from the opposite side.
    private func swipeToMonth(delta: Int) {
        let exitDistance: CGFloat = 500
        let exitOffset: CGFloat = delta > 0 ? -exitDistance : exitDistance

        withAnimation(.easeIn(duration: 0.16)) {
            dragOffset = exitOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            stepMonth(by: delta)
            dragOffset = -exitOffset
            withAnimation(.easeOut(duration: 0.24)) {
                dragOffset = 0
            }
        }
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let base = formatter.veryShortWeekdaySymbols.map { $0.lowercased() }
        guard !base.isEmpty else { return ["m", "t", "w", "t", "f", "s", "s"] }
        let shift = max(calendar.firstWeekday - 1, 0)
        return Array(base[shift...] + base[..<shift])
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()

                        ThemeToggle(themeRaw: $themeRaw, palette: palette)
                    }

                    Menu {
                        ForEach(yearOptions, id: \.self) { year in
                            Button {
                                selectedYear = year
                            } label: {
                                if year == selectedYear {
                                    Label(String(year), systemImage: "checkmark")
                                } else {
                                    Text(String(year))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(verbatim: String(selectedYear))
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(palette.surface)
                        )
                    }
                    .accessibilityLabel("select year")

                    HStack(spacing: 16) {
                        Button {
                            swipeToMonth(delta: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(palette.surface)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("previous month")

                        Text(selectedMonthName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .frame(minWidth: 110)
                            .multilineTextAlignment(.center)

                        Button {
                            swipeToMonth(delta: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(palette.surface)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("next month")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    calendarGrid
                        .offset(x: dragOffset)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    dragOffset = value.translation.width
                                }
                                .onEnded { value in
                                    let threshold: CGFloat = 50
                                    if value.translation.width < -threshold {
                                        swipeToMonth(delta: 1)
                                    } else if value.translation.width > threshold {
                                        swipeToMonth(delta: -1)
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            dragOffset = 0
                                        }
                                    }
                                }
                        )

                    legendRow

                    Text("fell behind? catch up on your year — tap any day to fill it in, or leave it blank.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(palette.textSecondary)

                    Button {
                        isShowingQuickFill = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                            Text("quick fill this month")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(palette.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(palette.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isShowingQuickFill) {
                        MoodColorPicker(palette: palette, includeBlank: false) { picked in
                            if let picked {
                                Haptics.light()
                                moodStore.fillPastDays(monthDates, with: picked)
                            }
                            isShowingQuickFill = false
                        }
                        .presentationCompactAdaptation(.popover)
                    }

                    Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .background(BackgroundView(palette: palette))
        }
    }

    private var monthDates: [Date] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        return dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }
    }

    private var monthCells: [Date?] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingSlots = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingSlots)
        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                cells.append(date)
            }
        }

        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        return cells
    }

    private var calendarGrid: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        CalendarDayCell(
                            date: date,
                            mood: moodStore.mood(for: date),
                            palette: palette,
                            isDisabled: isFutureDate(date)
                        ) { newMood in
                            if !isFutureDate(date) {
                                moodStore.setMood(newMood, for: date)
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.clear)
                            .frame(height: 42)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    private var legendRow: some View {
        HStack(spacing: 10) {
            LegendDot(label: "work", color: Mood.workProductive.tint, palette: palette)
            LegendDot(label: "personal", color: Mood.personallyProductive.tint, palette: palette)
            LegendDot(label: "not", color: Mood.notProductive.tint, palette: palette)
            LegendDot(label: "blank", color: .clear, palette: palette, outlined: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isFutureDate(_ date: Date) -> Bool {
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        return start > today
    }
}

private struct CalendarDayCell: View {
    let date: Date
    let mood: Mood?
    let palette: AppPalette
    let isDisabled: Bool
    let onSelect: (Mood?) -> Void

    @State private var isShowingPicker = false

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: date))
    }

    var body: some View {
        Button {
            isShowingPicker = true
        } label: {
            Text(dayNumber)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary.opacity(isDisabled ? 0.35 : 1))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((mood?.tint ?? Color.clear).opacity(mood == nil ? 0 : 0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(mood == nil ? palette.border : (mood?.tint ?? palette.border), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("day \(dayNumber)")
        .accessibilityValue(mood?.title ?? "blank")
        .popover(isPresented: $isShowingPicker) {
            MoodColorPicker(palette: palette) { picked in
                Haptics.light()
                onSelect(picked)
                isShowingPicker = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// A row of colored swatches for picking a mood, so the color is visible
/// before you choose it (used by the calendar day picker and quick fill).
private struct MoodColorPicker: View {
    let palette: AppPalette
    var includeBlank = true
    let onPick: (Mood?) -> Void

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Mood.allCases) { option in
                swatch(color: option.tint, label: option.shortLabel) {
                    onPick(option)
                }
            }

            if includeBlank {
                swatch(color: nil, label: "blank") {
                    onPick(nil)
                }
            }
        }
        .padding(18)
    }

    private func swatch(color: Color?, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(color ?? Color.clear)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle().stroke(color ?? palette.border, lineWidth: color == nil ? 1.5 : 0)
                    )

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct LegendDot: View {
    let label: String
    let color: Color
    let palette: AppPalette
    var outlined = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(outlined ? Color.clear : color)
                .overlay(
                    Circle()
                        .stroke(outlined ? palette.border : color, lineWidth: 1)
                )
                .frame(width: 10, height: 10)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textSecondary)
        }
    }
}

private struct ThemeToggle: View {
    @Binding var themeRaw: String
    let palette: AppPalette

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .dark
    }

    var body: some View {
        Button {
            themeRaw = (theme == .dark ? AppTheme.light : AppTheme.dark).rawValue
        } label: {
            HeaderGlassIcon(
                systemName: theme == .dark ? "sun.max.fill" : "moon.fill",
                palette: palette
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme == .dark ? "switch to light mode" : "switch to dark mode")
    }
}

private struct AccountActionsMenu: View {
    let palette: AppPalette
    let onSelect: (AccountAction) -> Void

    var body: some View {
        Menu {
            Button("logout") {
                onSelect(.logout)
            }
            Button("delete account", role: .destructive) {
                onSelect(.deleteAccount)
            }
        } label: {
            HeaderGlassIcon(
                systemName: "person.crop.circle",
                palette: palette
            )
        }
        .accessibilityLabel("account options")
    }
}

private struct HeaderGlassIcon: View {
    let systemName: String
    let palette: AppPalette

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(palette.textPrimary)
            .frame(width: 40, height: 40)
            .background(
                Group {
                    if #available(iOS 26.0, *) {
                        Color.clear
                            .glassEffect(
                                .regular.tint(palette.background.opacity(0.08)),
                                in: Capsule()
                            )
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }
                }
            )
            .overlay(
                Capsule()
                    .stroke(palette.border, lineWidth: 1)
            )
    }
}

private enum WallpaperDotShapeOption: String, CaseIterable, Identifiable {
    case squircle
    case circle

    var id: String { rawValue }

    static func fromStorage(_ raw: String) -> WallpaperDotShapeOption {
        let lowered = raw.lowercased()
        if lowered == "circle" || lowered == "round" {
            return .circle
        }
        return .squircle
    }
}

enum WallpaperSetupStepContent {
    case screenshot(imageName: String)
    case completion
}

struct WallpaperSetupStep: Identifiable {
    let id: Int
    let content: WallpaperSetupStepContent
}

enum WallpaperSetupGuideContent {
    /// Drop the 12 annotated screenshot files into endar/screenshots with these exact
    /// names (in this order) to complete the tutorial — no other code change needed.
    static let steps: [WallpaperSetupStep] = {
        let imageNames = [
            "wallpaper-setup-01.png",
            "wallpaper-setup-02.png",
            "wallpaper-setup-03.png",
            "wallpaper-setup-04.png",
            "wallpaper-setup-05.png",
            "wallpaper-setup-06.png",
            "wallpaper-setup-07.png",
            "wallpaper-setup-08.png",
            "wallpaper-setup-09.png",
            "wallpaper-setup-10.png",
            "wallpaper-setup-11.png",
            "wallpaper-setup-12.png"
        ]

        var steps = imageNames.enumerated().map { index, name in
            WallpaperSetupStep(id: index, content: .screenshot(imageName: name))
        }
        steps.append(WallpaperSetupStep(id: imageNames.count, content: .completion))
        return steps
    }()
}

private struct SetView: View {
    enum iPhoneModel: String, CaseIterable, Identifiable {
        case iphone11 = "iphone 11"
        case iphone11Pro = "iphone 11 pro"
        case iphone11ProMax = "iphone 11 pro max"
        case iphone12Mini = "iphone 12 mini"
        case iphone12 = "iphone 12"
        case iphone12Pro = "iphone 12 pro"
        case iphone12ProMax = "iphone 12 pro max"
        case iphone13Mini = "iphone 13 mini"
        case iphone13 = "iphone 13"
        case iphone13Pro = "iphone 13 pro"
        case iphone13ProMax = "iphone 13 pro max"
        case iphone14 = "iphone 14"
        case iphone14Plus = "iphone 14 plus"
        case iphone14Pro = "iphone 14 pro"
        case iphone14ProMax = "iphone 14 pro max"
        case iphone15 = "iphone 15"
        case iphone15Plus = "iphone 15 plus"
        case iphone15Pro = "iphone 15 pro"
        case iphone15ProMax = "iphone 15 pro max"
        case iphone16 = "iphone 16"
        case iphone16e = "iphone 16e"
        case iphone16Plus = "iphone 16 plus"
        case iphone16Pro = "iphone 16 pro"
        case iphone16ProMax = "iphone 16 pro max"
        case iphone17 = "iphone 17"
        case iphone17Pro = "iphone 17 pro"
        case iphone17Max = "iphone 17 max"
        case iphone17ProMax = "iphone 17 pro max"

        var id: String { rawValue }

        var storageValue: String {
            rawValue.replacingOccurrences(of: "iphone", with: "iPhone")
        }

        static func fromStorage(_ raw: String) -> iPhoneModel? {
            let lowered = raw.replacingOccurrences(of: "iPhone", with: "iphone").lowercased()
            return iPhoneModel(rawValue: lowered)
        }

        static func detectCurrentDeviceBestEffort() -> iPhoneModel? {
            guard UIDevice.current.userInterfaceIdiom == .phone else { return nil }

            let screenBounds: CGSize = {
                if let sceneScreen = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })?
                    .screen.nativeBounds.size {
                    return sceneScreen
                }
                if let anySceneScreen = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first?
                    .screen.nativeBounds.size {
                    return anySceneScreen
                }
                return .zero
            }()

            guard screenBounds != .zero else { return nil }

            let bounds = screenBounds
            let shortEdge = Int(min(bounds.width, bounds.height))
            let longEdge = Int(max(bounds.width, bounds.height))

            switch (shortEdge, longEdge) {
            case (1080, 2340):
                return .iphone13Mini
            case (1170, 2532):
                return .iphone16e
            case (1179, 2556):
                return .iphone16
            case (1206, 2622):
                return .iphone17
            case (1290, 2796):
                return .iphone16Plus
            case (1320, 2868):
                return .iphone17ProMax
            default:
                return nil
            }
        }
    }

    @AppStorage("wallpaper.period.v1") private var wallpaperPeriodRaw: String = "Year"
    @AppStorage("wallpaper.device.v1") private var wallpaperDeviceRaw: String = iPhoneModel.iphone17.storageValue
    @AppStorage("wallpaper.device.userSelected.v1") private var wallpaperDeviceUserSelected = false
    @AppStorage("wallpaper.dotShape.v1") private var wallpaperDotShapeRaw: String = WallpaperDotShapeOption.squircle.rawValue
    @Binding var themeRaw: String

    let palette: AppPalette

    @State private var model: iPhoneModel = .iphone17
    @State private var dotShape: WallpaperDotShapeOption = .squircle
    @State private var showWallpaperGuide = false
    @State private var shareURL: URL?
    @State private var shareImage: UIImage?

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .dark
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()

                    ThemeToggle(themeRaw: $themeRaw, palette: palette)
                }

                wallpaperModelSelection
                wallpaperControls

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .background(BackgroundView(palette: palette))
        }
        .onAppear {
            wallpaperPeriodRaw = "Year"
            if wallpaperDeviceUserSelected, let restored = iPhoneModel.fromStorage(wallpaperDeviceRaw) {
                model = restored
            } else if let detected = iPhoneModel.detectCurrentDeviceBestEffort() {
                model = detected
                wallpaperDeviceRaw = detected.storageValue
            } else if let restored = iPhoneModel.fromStorage(wallpaperDeviceRaw) {
                model = restored
            }

            dotShape = WallpaperDotShapeOption.fromStorage(wallpaperDotShapeRaw)
            refreshShareImage()
        }
        .onChange(of: model) { _, newValue in
            wallpaperDeviceRaw = newValue.storageValue
            refreshShareImage()
        }
        .onChange(of: dotShape) { _, newValue in
            wallpaperDotShapeRaw = newValue.rawValue
            refreshShareImage()
        }
        .sheet(isPresented: $showWallpaperGuide) {
            WallpaperAutomationGuideView()
        }
    }

    private func refreshShareImage() {
        guard let image = try? renderShareableWallpaperImage(), let data = image.pngData() else {
            shareURL = nil
            shareImage = nil
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("my-year.png")
        do {
            try data.write(to: url, options: [.atomic])
            shareURL = url
            shareImage = image
        } catch {
            shareURL = nil
            shareImage = nil
        }
    }

    private var wallpaperModelSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iphone model")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textSecondary)

            Menu {
                ForEach(iPhoneModel.allCases) { option in
                    Button(option.rawValue) {
                        wallpaperDeviceUserSelected = true
                        model = option
                    }
                }
            } label: {
                HStack {
                    Text(model.rawValue)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var wallpaperControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("dot style")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textSecondary)

            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 22) {
                    HStack(spacing: 12) {
                        ForEach(WallpaperDotShapeOption.allCases) { option in
                            Button {
                                dotShape = option
                            } label: {
                                DotStyleChip(
                                    option: option,
                                    isSelected: dotShape == option,
                                    palette: palette,
                                    isLightTheme: theme == .light
                                )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    ForEach(WallpaperDotShapeOption.allCases) { option in
                        Button {
                            dotShape = option
                        } label: {
                            DotStyleChip(
                                option: option,
                                isSelected: dotShape == option,
                                palette: palette,
                                isLightTheme: theme == .light
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
            }
        }

        Button {
            Haptics.light()
            showWallpaperGuide = true
        } label: {
            Text("set wallpaper")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(palette.textPrimary)
                )
        }
        .buttonStyle(.plain)

        if let shareURL, let shareImage {
            ShareLink(
                item: shareURL,
                preview: SharePreview("my year", image: Image(uiImage: shareImage))
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("share my year")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
        }
    }
}

private struct WallpaperSetupStepCard: View {
    let step: WallpaperSetupStep
    let palette: AppPalette

    var body: some View {
        switch step.content {
        case .screenshot(let imageName):
            WallpaperSetupScreenshot(imageName: imageName, palette: palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 4)
        case .completion:
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(palette.textPrimary)

                Text("you're all set — now you can start having your life under control.")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct WallpaperSetupCarousel: View {
    let palette: AppPalette
    @Binding var selectedStep: Int
    let steps: [WallpaperSetupStep]

    var body: some View {
        TabView(selection: $selectedStep) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                WallpaperSetupStepCard(step: step, palette: palette)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WallpaperSetupScreenshot: View {
    let imageName: String
    let palette: AppPalette
    private let cornerRadius: CGFloat = 22

    var body: some View {
        Group {
            if let image = bundledImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.system(size: 24, weight: .semibold))
                            Text("screenshot unavailable")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.white.opacity(0.85))
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(screenshotBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(palette.border.opacity(0.9), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var screenshotBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .regular.tint(palette.surface.opacity(0.22)),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var bundledImage: UIImage? {
        if let directPath = Bundle.main.path(forResource: imageName, ofType: nil) {
            return UIImage(contentsOfFile: directPath)
        }

        if let nestedPath = Bundle.main.path(forResource: imageName, ofType: nil, inDirectory: "screenshots") {
            return UIImage(contentsOfFile: nestedPath)
        }

        return nil
    }
}

private struct DotStyleChip: View {
    let option: WallpaperDotShapeOption
    let isSelected: Bool
    let palette: AppPalette
    let isLightTheme: Bool

    var body: some View {
        let selectedStroke = isLightTheme ? Color.black.opacity(0.52) : Color.white.opacity(0.82)
        let unselectedStroke = isLightTheme ? Color.black.opacity(0.20) : palette.border.opacity(0.95)
        let selectedTint = isLightTheme ? Color.black.opacity(0.07) : Color.white.opacity(0.08)
        let unselectedTint = isLightTheme ? Color.black.opacity(0.025) : Color.white.opacity(0.03)

        let base = VStack(spacing: 7) {
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { _ in
                    dotSample
                }
            }
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { _ in
                    dotSample
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .overlay(
            Capsule()
                .stroke(
                    isSelected ? selectedStroke : unselectedStroke,
                    lineWidth: isSelected ? 1.8 : 1.1
                )
        )

        if #available(iOS 26.0, *) {
            base
                .glassEffect(
                    .regular.tint(isSelected ? selectedTint : unselectedTint),
                    in: Capsule()
                )
        } else {
            base
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
        }
    }

    private var dotSample: some View {
        let dotFill = isLightTheme
            ? Color.black.opacity(isSelected ? 0.84 : 0.70)
            : Color.white.opacity(isSelected ? 0.97 : 0.88)
        let dotStroke = isLightTheme
            ? Color.white.opacity(0.36)
            : Color.black.opacity(0.20)

        return Group {
            if option == .circle {
                Circle()
                    .fill(dotFill)
                    .overlay(
                        Circle()
                            .stroke(dotStroke, lineWidth: 0.7)
                    )
            } else {
                RoundedRectangle(cornerRadius: 3.0, style: .continuous)
                    .fill(dotFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.0, style: .continuous)
                            .stroke(dotStroke, lineWidth: 0.7)
                    )
            }
        }
        .frame(width: 12, height: 12)
    }
}

private struct BackgroundView: View {
    let palette: AppPalette

    var body: some View {
        palette.background
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
