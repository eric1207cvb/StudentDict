import SwiftUI
import GoogleMobileAds
import RevenueCat

// 1. 定義 AppDelegate 來控制旋轉方向與初始化 SDK
class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // --- A. RevenueCat 設定 ---
        // ⚠️ 請確認下方的 API Key 是正確的
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: "appl_CHzApfUVTNYBrjzwIOXeIDUBTOU")
        
        // --- B. AdMob 設定 ---
        // [Fix]: 使用最新的 Swift 語法: MobileAds.shared
        let adsConfig = MobileAds.shared.requestConfiguration
        
        // 設定 COPPA (兒童隱私合規)
        adsConfig.tagForChildDirectedTreatment = true
        adsConfig.tagForUnderAgeOfConsent = true
        
        // 啟動 AdMob
        // [Fix]: 使用最新的 Swift 語法: MobileAds.shared
        MobileAds.shared.start(completionHandler: nil)
        
        return true
    }

    // 🌟 核心功能：針對裝置鎖定方向
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        
        // 如果是 iPhone -> 只允許直向 (Portrait)
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .portrait
        }
        
        // 如果是 iPad -> 允許所有方向 (直/橫)
        return .all
    }
}

@main
struct StudentDictApp: App {
    // 連結 AppDelegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
