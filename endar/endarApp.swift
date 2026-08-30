//
//  endarApp.swift
//  endar
//
//  Created by MC-CLYO on 09/02/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppIntents)
import AppIntents
#endif
import AuthenticationServices
import GoogleSignIn

@main
struct endarApp: App {
    init() {
        #if canImport(UIKit)
        // Make segmented pickers match the floating tab bar vibe: subtle selected pill + accent-colored selected label.
        let control = UISegmentedControl.appearance()
        control.selectedSegmentTintColor = UIColor(white: 1.0, alpha: 0.16)
        control.backgroundColor = .clear
        control.setBackgroundImage(UIImage(), for: .normal, barMetrics: .default)
        control.setBackgroundImage(UIImage(), for: .selected, barMetrics: .default)
        control.setBackgroundImage(UIImage(), for: .highlighted, barMetrics: .default)
        control.setDividerImage(
            UIImage(),
            forLeftSegmentState: .normal,
            rightSegmentState: .normal,
            barMetrics: .default
        )

        let normalAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white.withAlphaComponent(0.72)
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(red: 1.0, green: 92.0/255.0, blue: 0.0, alpha: 1.0) // #FF5C00
        ]
        control.setTitleTextAttributes(normalAttrs, for: .normal)
        control.setTitleTextAttributes(selectedAttrs, for: .selected)

        #endif

        #if canImport(AppIntents)
        if #available(iOS 17.0, *) {
            Task {
                EndarAppShortcuts.updateAppShortcutParameters()
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .onOpenURL { url in
                    if url.scheme == "productivitycal" {
                        if url.host == "log" {
                            NotificationCenter.default.post(name: .productivitycalOpenLog, object: nil)
                        }
                        return
                    }
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

private struct AppRootView: View {
    private enum SessionAuthProvider: String {
        case apple
        case google
        case email
    }

    @State private var showLaunchSplash = true
    @State private var hasAuthenticated = false
    @State private var hasAttemptedGoogleRestore = false
    @State private var hasAttemptedAppleRestore = false
    @State private var isAppleSigningIn = false
    @State private var isGoogleSigningIn = false
    @State private var appleSignInCoordinator: AppleSignInCoordinator?
    @State private var appleLogoutCoordinator: AppleLogoutCoordinator?
    @AppStorage("auth.apple.user.id.v1") private var storedAppleUserID: String = ""
    @AppStorage("auth.provider.v1") private var authProviderRaw: String = ""
    // Each restore path flips its own flag when it's done (success or not),
    // so the splash never hands off to LoginView/ContentView before we
    // actually know which one is correct — that race is what used to flash
    // the login screen for a frame on an already-logged-in launch.
    @State private var googleCheckDone = false
    @State private var appleCheckDone = false
    #if canImport(Supabase)
    @State private var isEmailSigningIn = false
    @State private var emailAuthError: String?
    @State private var hasAttemptedEmailRestore = false
    @State private var emailCheckDone = false
    #endif

    private var isAuthBypassedOnSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private var isSessionAuthenticated: Bool {
        hasAuthenticated || isAuthBypassedOnSimulator
    }

    private var isSessionCheckComplete: Bool {
        guard !isAuthBypassedOnSimulator else { return true }
        #if canImport(Supabase)
        return googleCheckDone && appleCheckDone && emailCheckDone
        #else
        return googleCheckDone && appleCheckDone
        #endif
    }

    var body: some View {
        ZStack {
            if isSessionAuthenticated {
                ContentView(
                    onLogout: handleLogout,
                    onDeleteAccount: handleDeleteAccount
                )
                    .transition(.opacity)
            } else {
                #if canImport(Supabase)
                LoginView(
                    onAppleSignIn: signInWithApple,
                    onGoogleSignIn: signInWithGoogle,
                    isAppleSigningIn: isAppleSigningIn,
                    isGoogleSigningIn: isGoogleSigningIn,
                    onEmailSignIn: signInWithEmail,
                    onEmailSignUp: signUpWithEmail,
                    isEmailSigningIn: isEmailSigningIn,
                    emailAuthError: emailAuthError
                )
                .transition(.opacity)
                .allowsHitTesting(!showLaunchSplash)
                #else
                LoginView(
                    onAppleSignIn: signInWithApple,
                    onGoogleSignIn: signInWithGoogle,
                    isAppleSigningIn: isAppleSigningIn,
                    isGoogleSigningIn: isGoogleSigningIn
                )
                .transition(.opacity)
                .allowsHitTesting(!showLaunchSplash)
                #endif
            }

            if showLaunchSplash {
                // A plain Bool parameter would freeze at whatever value was
                // true when .task first launched inside LaunchSplashView (a
                // value-type struct); a Binding reads the live value from
                // AppRootView's own @State on every check, which is what
                // lets the splash actually wait for the restore to finish.
                LaunchSplashView(isSessionCheckComplete: Binding(get: { isSessionCheckComplete }, set: { _ in })) {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        showLaunchSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: isSessionAuthenticated)
        .onAppear {
            DailyMoodNotificationScheduler.shared.configureIfNeeded()
            guard !isAuthBypassedOnSimulator else { return }
            restorePreviousGoogleSessionIfNeeded()
            restorePreviousAppleSessionIfNeeded()
            #if canImport(Supabase)
            restorePreviousEmailSessionIfNeeded()
            #endif
        }
    }

    private func completeLogin() {
        withAnimation(.easeInOut(duration: 0.28)) {
            hasAuthenticated = true
        }
        DailyMoodNotificationScheduler.shared.configureIfNeeded()
    }

    #if canImport(Supabase)
    private func signInWithEmail(email: String, password: String) {
        guard !isEmailSigningIn else { return }
        isEmailSigningIn = true
        emailAuthError = nil

        Task {
            do {
                try await MoodSyncService.signInWithPassword(email: email, password: password)
                await MainActor.run {
                    isEmailSigningIn = false
                    authProviderRaw = SessionAuthProvider.email.rawValue
                    storedAppleUserID = ""
                    completeLogin()
                }
            } catch {
                await MainActor.run {
                    isEmailSigningIn = false
                    emailAuthError = error.localizedDescription
                }
            }
        }
    }

    private func signUpWithEmail(email: String, password: String) {
        guard !isEmailSigningIn else { return }
        isEmailSigningIn = true
        emailAuthError = nil

        Task {
            do {
                let hasSession = try await MoodSyncService.signUpWithPassword(email: email, password: password)
                await MainActor.run {
                    isEmailSigningIn = false
                    guard hasSession else {
                        // The project's auth settings require confirming the
                        // email first — there's no session yet, so signing
                        // the device in now would show the app with nothing
                        // actually synced.
                        emailAuthError = "check your inbox to confirm your email, then sign in."
                        return
                    }
                    authProviderRaw = SessionAuthProvider.email.rawValue
                    storedAppleUserID = ""
                    completeLogin()
                }
            } catch {
                await MainActor.run {
                    isEmailSigningIn = false
                    emailAuthError = error.localizedDescription
                }
            }
        }
    }
    #endif

    private func handleLogout() {
        GIDSignIn.sharedInstance.signOut()
        performAppleLogoutIfNeeded {
            finishSession(resetAllLocalData: false)
        }
    }

    private func handleDeleteAccount() {
        let finalizeDeletion = {
            // For now "delete account" means revoking OAuth sessions and wiping local app data.
            finishSession(resetAllLocalData: true)
        }

        revokeGoogleSessionIfNeeded {
            performAppleLogoutIfNeeded {
                finalizeDeletion()
            }
        }
    }

    private func restorePreviousGoogleSessionIfNeeded() {
        guard !hasAttemptedGoogleRestore else { return }
        hasAttemptedGoogleRestore = true

        GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
            defer { googleCheckDone = true }
            guard user != nil else { return }
            authProviderRaw = SessionAuthProvider.google.rawValue
            storedAppleUserID = ""
            completeLogin()
        }
    }

    private func restorePreviousAppleSessionIfNeeded() {
        guard !hasAttemptedAppleRestore else { return }
        hasAttemptedAppleRestore = true
        guard !storedAppleUserID.isEmpty else {
            appleCheckDone = true
            return
        }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: storedAppleUserID) { state, _ in
            DispatchQueue.main.async {
                defer { appleCheckDone = true }
                guard state == .authorized else { return }
                authProviderRaw = SessionAuthProvider.apple.rawValue
                completeLogin()
            }
        }
    }

    #if canImport(Supabase)
    /// Apple/Google restore their own native session and separately drive
    /// `hasAuthenticated`; a plain email account has no such native restore,
    /// so without this it had to log in again on every single launch. Any
    /// persisted, still-valid Supabase session — from any provider — is
    /// proof enough to skip the login screen.
    private func restorePreviousEmailSessionIfNeeded() {
        guard !hasAttemptedEmailRestore else { return }
        hasAttemptedEmailRestore = true

        Task {
            let hasPersistedSession = await MoodSyncService.hasPersistedSession()
            await MainActor.run {
                emailCheckDone = true
                guard hasPersistedSession, !hasAuthenticated else { return }
                completeLogin()
            }
        }
    }
    #endif

    private func signInWithApple() {
        guard !isAuthBypassedOnSimulator else {
            completeLogin()
            return
        }
        guard !isAppleSigningIn else { return }
        guard let window = activeWindow else { return }

        isAppleSigningIn = true

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let coordinator = AppleSignInCoordinator(
            request: request,
            presentationWindow: window,
            onCompletion: { result in
                isAppleSigningIn = false
                switch result {
                case .success(let credential):
                    storedAppleUserID = credential.user
                    authProviderRaw = SessionAuthProvider.apple.rawValue
                    GIDSignIn.sharedInstance.signOut()
                    #if canImport(Supabase)
                    if let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8) {
                        Task { await MoodSyncService.signIn(idToken: idToken, provider: .apple) }
                    }
                    #endif
                    completeLogin()
                case .failure:
                    break
                }
                appleSignInCoordinator = nil
            }
        )

        appleSignInCoordinator = coordinator
        coordinator.start()
    }

    private func signInWithGoogle() {
        guard !isAuthBypassedOnSimulator else {
            completeLogin()
            return
        }
        guard !isGoogleSigningIn else { return }
        guard let rootViewController = activeRootViewController else { return }

        isGoogleSigningIn = true
        let configuration = GIDConfiguration(clientID: GoogleAuthConfig.clientID)
        GIDSignIn.sharedInstance.configuration = configuration
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, _ in
            isGoogleSigningIn = false
            guard let result else { return }
            authProviderRaw = SessionAuthProvider.google.rawValue
            storedAppleUserID = ""
            #if canImport(Supabase)
            if let idToken = result.user.idToken?.tokenString {
                Task { await MoodSyncService.signIn(idToken: idToken, provider: .google) }
            }
            #endif
            completeLogin()
        }
    }

    private func revokeGoogleSessionIfNeeded(completion: @escaping () -> Void) {
        guard GIDSignIn.sharedInstance.currentUser != nil else {
            completion()
            return
        }
        GIDSignIn.sharedInstance.disconnect { _ in
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private func performAppleLogoutIfNeeded(completion: @escaping () -> Void) {
        guard authProviderRaw == SessionAuthProvider.apple.rawValue else {
            completion()
            return
        }
        guard !storedAppleUserID.isEmpty else {
            completion()
            return
        }
        guard let window = activeWindow else {
            completion()
            return
        }

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedOperation = .operationLogout

        let coordinator = AppleLogoutCoordinator(
            request: request,
            presentationWindow: window,
            onCompletion: { _ in
                appleLogoutCoordinator = nil
                completion()
            }
        )
        appleLogoutCoordinator = coordinator
        coordinator.start()
    }

    private func finishSession(resetAllLocalData: Bool) {
        storedAppleUserID = ""
        authProviderRaw = ""
        isAppleSigningIn = false
        isGoogleSigningIn = false

        #if canImport(Supabase)
        Task { await MoodSyncService.signOut() }
        #endif

        if resetAllLocalData {
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
            UserDefaults.standard.synchronize()

            if let sharedSuite = UserDefaults(suiteName: SharedStorage.appGroupID) {
                for key in sharedSuite.dictionaryRepresentation().keys {
                    sharedSuite.removeObject(forKey: key)
                }
                sharedSuite.synchronize()
            }
        }

        withAnimation(.easeInOut(duration: 0.28)) {
            hasAuthenticated = false
        }
    }

    private var activeWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private var activeRootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

private struct LaunchSplashView: View {
    @Binding var isSessionCheckComplete: Bool
    let onFinished: () -> Void

    @State private var hasStarted = false
    @State private var containerOpacity: CGFloat = 1.0
    @State private var logoBaseOpacity: CGFloat = 0.0
    @State private var logoScale: CGFloat = 0.985
    @State private var logoGlow: CGFloat = 0.0
    @State private var logoBloomOpacity: CGFloat = 0.0
    @State private var logoBloomBlur: CGFloat = 6.0
    @State private var logoBloomScale: CGFloat = 1.0
    @State private var logoSpecularOpacity: CGFloat = 0.0

    private let logoName = "splash-logo"

    private var customLogoImage: UIImage? {
        if let named = UIImage(named: logoName) {
            return named
        }
        guard let path = Bundle.main.path(forResource: logoName, ofType: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: path)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                splashLogo(maxWidth: min(proxy.size.width * 0.44, 220))
                    .opacity(logoBloomOpacity)
                    .scaleEffect(logoBloomScale)
                    .blur(radius: logoBloomBlur)
                    .blendMode(.screen)

                splashLogo(maxWidth: min(proxy.size.width * 0.44, 220))
                    .opacity(logoSpecularOpacity)
                    .scaleEffect(logoScale * 1.004)
                    .blur(radius: 0.8)
                    .blendMode(.screen)

                splashLogo(maxWidth: min(proxy.size.width * 0.44, 220))
                    .opacity(logoBaseOpacity)
                    .scaleEffect(logoScale)
                    .shadow(color: .white.opacity(logoGlow), radius: 18, x: 0, y: 0)
            }
            .opacity(containerOpacity)
            .task {
                await runAnimationIfNeeded()
            }
        }
    }

    @ViewBuilder
    private func splashLogo(maxWidth: CGFloat) -> some View {
        if let image = customLogoImage {
            Image(uiImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(.white)
                .frame(maxWidth: maxWidth)
        } else {
            Text("productivitycal")
                .font(.system(size: 54, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .tracking(1.2)
        }
    }

    /// Shown once in full the first time the app is opened each day; every
    /// later same-day launch gets a quick fade instead so a multiple-times-
    /// a-day habit app doesn't pay a ~2s animation tax on every open.
    private static let lastShownDayKey = "launchSplash.lastShownDay.v1"

    @MainActor
    private func runAnimationIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

        let defaults = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: Date())
        let alreadyShownToday: Bool = {
            guard let stored = defaults.object(forKey: Self.lastShownDayKey) as? Date else { return false }
            return Calendar.current.isDate(stored, inSameDayAs: today)
        }()

        guard !alreadyShownToday else {
            withAnimation(.easeOut(duration: 0.2)) {
                logoBaseOpacity = 1.0
                logoScale = 1.0
            }
            try? await Task.sleep(nanoseconds: 220_000_000)
            withAnimation(.easeInOut(duration: 0.18)) {
                containerOpacity = 0.0
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            await waitForSessionCheck()
            onFinished()
            return
        }

        defaults.set(today, forKey: Self.lastShownDayKey)

        // 1) Pure black hold
        try? await Task.sleep(nanoseconds: 150_000_000)

        // 2) Logo emerges from black
        withAnimation(.easeOut(duration: 0.55)) {
            logoBaseOpacity = 1.0
            logoScale = 1.0
        }

        // 3) Start glow earlier while logo fade-in is still progressing
        try? await Task.sleep(nanoseconds: 380_000_000)
        withAnimation(.easeInOut(duration: 0.5)) {
            logoGlow = 0.34
            logoBloomOpacity = 0.64
            logoBloomBlur = 14.0
            logoBloomScale = 1.04
            logoSpecularOpacity = 0.24
        }

        try? await Task.sleep(nanoseconds: 380_000_000)

        // 4) Dissolve to home
        withAnimation(.easeInOut(duration: 0.22)) {
            containerOpacity = 0.0
        }

        try? await Task.sleep(nanoseconds: 220_000_000)
        await waitForSessionCheck()
        onFinished()
    }

    /// Blocks the splash's hand-off until the Apple/Google/email restore
    /// checks in AppRootView have all reported in — otherwise the fixed
    /// animation timer above could finish first and reveal LoginView for a
    /// frame before the real "already logged in" answer comes back. Capped
    /// so a stuck check (no network, a hung SDK callback) can't strand the
    /// splash on screen forever.
    private func waitForSessionCheck() async {
        let deadline = Date().addingTimeInterval(2.5)
        while !isSessionCheckComplete && Date() < deadline {
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
    }
}

private struct LoginView: View {
    let onAppleSignIn: () -> Void
    let onGoogleSignIn: () -> Void
    let isAppleSigningIn: Bool
    let isGoogleSigningIn: Bool
    #if canImport(Supabase)
    let onEmailSignIn: (String, String) -> Void
    let onEmailSignUp: (String, String) -> Void
    let isEmailSigningIn: Bool
    let emailAuthError: String?

    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    #endif

    private let backgroundColor = Color(hex: 0x333333)
    private let logoName = "splash-logo"

    private var brandLogoImage: UIImage? {
        if let named = UIImage(named: logoName) {
            return named
        }
        guard let path = Bundle.main.path(forResource: logoName, ofType: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: path)
    }

    var body: some View {
        GeometryReader { proxy in
            let maxContentWidth = min(proxy.size.width - 32, 440)
            let topSpacing = max(proxy.size.height * 0.12, 72)
            let bottomSpacing = max(proxy.size.height * 0.14, 84)

            ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: topSpacing)

                VStack(spacing: 12) {
                    Group {
                        if let brandLogoImage {
                            Image(uiImage: brandLogoImage)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                        } else {
                            Text("productivitycal")
                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                                .tracking(0.6)
                        }
                    }

                    Text("your days, tracked. your life, under control.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: maxContentWidth)
                .padding(.horizontal, 16)
                .padding(.bottom, 36)

                VStack(spacing: 14) {
                    LiquidGlassSSOButton(
                        title: isAppleSigningIn ? "connecting..." : "Sign in with Apple",
                        action: onAppleSignIn
                    ) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .disabled(isAppleSigningIn)

                    LiquidGlassSSOButton(
                        title: isGoogleSigningIn ? "connecting..." : "Sign in with Google",
                        action: onGoogleSignIn
                    ) {
                        GoogleLogoIcon()
                            .frame(width: 20, height: 20)
                    }
                    .disabled(isGoogleSigningIn)

                    #if canImport(Supabase)
                    emailAuthSection
                    #endif

                    Link("privacy policy", destination: URL(string: "https://lasagnealpesto.github.io/productivitycal/privacy-policy.html")!)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 6)
                }
                .frame(maxWidth: maxContentWidth)
                .padding(.horizontal, 16)

                Spacer(minLength: bottomSpacing)
            }
            .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundColor.ignoresSafeArea())
        }
    }

    #if canImport(Supabase)
    private var emailAuthSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
                Text("or")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
            }
            .padding(.vertical, 4)

            TextField("", text: $email, prompt: Text("email").foregroundStyle(.white.opacity(0.4)))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(emailFieldBackground)

            ZStack(alignment: .trailing) {
                Group {
                    if isPasswordVisible {
                        TextField("", text: $password, prompt: Text("password").foregroundStyle(.white.opacity(0.4)))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("", text: $password, prompt: Text("password").foregroundStyle(.white.opacity(0.4)))
                    }
                }
                .textContentType(.password)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.trailing, 32)
                .frame(height: 46)

                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 32, height: 46)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }
            .background(emailFieldBackground)

            if let emailAuthError {
                Text(emailAuthError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }

            HStack(spacing: 10) {
                Button {
                    onEmailSignIn(email, password)
                } label: {
                    Text(isEmailSigningIn ? "..." : "sign in")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(NeutralGlassButtonStyle())
                .background(emailFieldBackground)
                .disabled(isEmailSigningIn || email.isEmpty || password.isEmpty)

                Button {
                    onEmailSignUp(email, password)
                } label: {
                    Text(isEmailSigningIn ? "..." : "sign up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(NeutralGlassButtonStyle())
                .background(emailFieldBackground)
                .disabled(isEmailSigningIn || email.isEmpty || password.isEmpty)
            }
            .padding(.top, 2)
        }
        .padding(.top, 8)
    }

    private var emailFieldBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
    }
    #endif
}

private struct LiquidGlassSSOButton<Icon: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon()
                    .frame(width: 22, height: 22)

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .background {
                Group {
                    if #available(iOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white.opacity(0.06))
                            .overlay {
                                Color.clear
                                    .glassEffect(
                                        .regular.tint(.white.opacity(0.04)),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    )
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.black.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            )
        }
        .buttonStyle(NeutralGlassButtonStyle())
    }
}

private struct NeutralGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.988 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct GoogleLogoIcon: View {
    private let logoName = "google-g-logo"

    #if canImport(UIKit)
    private var logoImage: UIImage? {
        if let named = UIImage(named: logoName) {
            return named
        }
        guard let path = Bundle.main.path(forResource: logoName, ofType: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: path)
    }
    #endif

    var body: some View {
        #if canImport(UIKit)
        if let image = logoImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            fallbackIcon
        }
        #else
        fallbackIcon
        #endif
    }

    private var fallbackIcon: some View {
        Text("G")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
    }
}

private enum GoogleAuthConfig {
    static let fallbackClientID = "12610556593-uguka7hb3jv24d5qoldke13bf9estdqd.apps.googleusercontent.com"

    static var clientID: String {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let data = NSDictionary(contentsOfFile: path) as? [String: Any],
              let plistClientID = data["CLIENT_ID"] as? String,
              !plistClientID.isEmpty else {
            return fallbackClientID
        }
        return plistClientID
    }
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let request: ASAuthorizationAppleIDRequest
    private weak var presentationWindow: UIWindow?
    private let onCompletion: (Result<ASAuthorizationAppleIDCredential, Error>) -> Void

    init(
        request: ASAuthorizationAppleIDRequest,
        presentationWindow: UIWindow,
        onCompletion: @escaping (Result<ASAuthorizationAppleIDCredential, Error>) -> Void
    ) {
        self.request = request
        self.presentationWindow = presentationWindow
        self.onCompletion = onCompletion
    }

    func start() {
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presentationWindow ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            onCompletion(.failure(AppleSignInError.missingCredential))
            return
        }
        onCompletion(.success(credential))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onCompletion(.failure(error))
    }
}

private final class AppleLogoutCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let request: ASAuthorizationAppleIDRequest
    private weak var presentationWindow: UIWindow?
    private let onCompletion: (Result<Void, Error>) -> Void

    init(
        request: ASAuthorizationAppleIDRequest,
        presentationWindow: UIWindow,
        onCompletion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.request = request
        self.presentationWindow = presentationWindow
        self.onCompletion = onCompletion
    }

    func start() {
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presentationWindow ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        onCompletion(.success(()))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onCompletion(.failure(error))
    }
}

private enum AppleSignInError: Error {
    case missingCredential
}
