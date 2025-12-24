import SwiftUI
import GoogleMobileAds
import RevenueCat

@main
struct StudentDictApp: App {
    init() {
        // 1. RevenueCat 設定 (處理買斷廣告內購)
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: "appl_LpAgOPSlVbDmfUlhZkmhOBlWtTb")
        
        // 2. AdMob 設定與兒童隱私合規 (解決 Guideline 5.1.2)
        let adsConfig = MobileAds.shared.requestConfiguration
        adsConfig.tagForChildDirectedTreatment = true // 標示為面向兒童
        adsConfig.tagForUnderAgeOfConsent = true
        
        MobileAds.shared.start(completionHandler: nil)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
