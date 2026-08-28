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
                await EndarAppShortcuts.updateAppShortcutParameters()
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

private struct AppRootView: View {
    private enum SessionAuthProvider: String {
        case apple
        case google
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

    var body: some View {
        ZStack {
            if isSessionAuthenticated {
                ContentView(
                    onLogout: handleLogout,
                    onDeleteAccount: handleDeleteAccount
                )
                    .transition(.opacity)
            } else {
                LoginView(
                    onAppleSignIn: signInWithApple,
                    onGoogleSignIn: signInWithGoogle,
                    isAppleSigningIn: isAppleSigningIn,
                    isGoogleSigningIn: isGoogleSigningIn
                )
                .transition(.opacity)
                .allowsHitTesting(!showLaunchSplash)
            }

            if showLaunchSplash {
                LaunchSplashView {
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
            guard !isAuthBypassedOnSimulator else { return }
            restorePreviousGoogleSessionIfNeeded()
            restorePreviousAppleSessionIfNeeded()
        }
    }

    private func completeLogin() {
        withAnimation(.easeInOut(duration: 0.28)) {
            hasAuthenticated = true
        }
        DailyMoodNotificationScheduler.shared.configureIfNeeded()
    }

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
            guard user != nil else { return }
            authProviderRaw = SessionAuthProvider.google.rawValue
            storedAppleUserID = ""
            completeLogin()
        }
    }

    private func restorePreviousAppleSessionIfNeeded() {
        guard !hasAttemptedAppleRestore else { return }
        hasAttemptedAppleRestore = true
        guard !storedAppleUserID.isEmpty else { return }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: storedAppleUserID) { state, _ in
            guard state == .authorized else { return }
            DispatchQueue.main.async {
                authProviderRaw = SessionAuthProvider.apple.rawValue
                completeLogin()
            }
        }
    }

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
            guard result != nil else { return }
            authProviderRaw = SessionAuthProvider.google.rawValue
            storedAppleUserID = ""
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

    @MainActor
    private func runAnimationIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

        // 1) Pure black hold
        try? await Task.sleep(nanoseconds: 260_000_000)

        // 2) Logo emerges from black (opacity 0 -> 1 in ~1s)
        withAnimation(.easeOut(duration: 1.0)) {
            logoBaseOpacity = 1.0
            logoScale = 1.0
        }

        // 3) Start glow earlier while logo fade-in is still progressing
        try? await Task.sleep(nanoseconds: 700_000_000)
        withAnimation(.easeInOut(duration: 0.90)) {
            logoGlow = 0.34
            logoBloomOpacity = 0.64
            logoBloomBlur = 14.0
            logoBloomScale = 1.04
            logoSpecularOpacity = 0.24
        }

        try? await Task.sleep(nanoseconds: 700_000_000)

        // 4) Dissolve to home
        withAnimation(.easeInOut(duration: 0.28)) {
            containerOpacity = 0.0
        }

        try? await Task.sleep(nanoseconds: 280_000_000)
        onFinished()
    }
}

private struct LoginView: View {
    let onAppleSignIn: () -> Void
    let onGoogleSignIn: () -> Void
    let isAppleSigningIn: Bool
    let isGoogleSigningIn: Bool

    private let backgroundColor = Color(hex: 0x333333)

    var body: some View {
        GeometryReader { proxy in
            let maxContentWidth = min(proxy.size.width - 32, 440)
            let topSpacing = max(proxy.size.height * 0.18, 110)
            let bottomSpacing = max(proxy.size.height * 0.14, 84)

            VStack(spacing: 0) {
                Spacer(minLength: topSpacing)

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

                    Link("privacy policy", destination: URL(string: "https://lasagnealpesto.github.io/productivitycal/privacy-policy.html")!)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 6)
                }
                .frame(maxWidth: maxContentWidth)
                .padding(.horizontal, 16)

                Spacer(minLength: bottomSpacing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundColor.ignoresSafeArea())
        }
    }
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
