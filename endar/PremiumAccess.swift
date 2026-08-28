import Foundation

enum PremiumAccess {
    static let storageKey = "account.isPremium.v1"
    static let productID = "prod_id_cal"

    static var isPremium: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }

    static func configureLocalTestingAccessIfNeeded() {
        #if targetEnvironment(simulator)
        if !UserDefaults.standard.bool(forKey: storageKey) {
            UserDefaults.standard.set(true, forKey: storageKey)
        }
        #endif
    }
}
