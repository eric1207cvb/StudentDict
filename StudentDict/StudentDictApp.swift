import SwiftUI
import GoogleMobileAds // AdMob
import RevenueCat      // RevenueCat

@main
struct StudentDictApp: App {
    
    init() {
        // ==========================================
        // 1. Google AdMob 設定
        // ==========================================
        
        // [修正] 使用 MobileAds.shared (這是新版 SDK 的 Swift 標準寫法)
        let adsConfig = MobileAds.shared.requestConfiguration
        
        // 保護兒童隱私設定
        adsConfig.tagForChildDirectedTreatment = true
        adsConfig.tagForUnderAgeOfConsent = true
        
        // 設定測試裝置 ID (請填入您在 Console 看到的 ID)
        // 例如： ["2077ef9a63d2b398840261c8221a0c9b"]
        adsConfig.testDeviceIdentifiers = ["ca-app-pub-8563333250584395/7527216704"]
        
        // [修正] 啟動廣告
        MobileAds.shared.start(completionHandler: nil)
        
        // ==========================================
        // 2. RevenueCat 設定 (內購功能)
        // ==========================================
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: "appl_LpAgOPSlVbDmfUlhZkmhOBlWtTb")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
