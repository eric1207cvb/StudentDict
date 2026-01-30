import Foundation
import RevenueCat
import Combine // [新增] 必須加入這行，否則 @Published 會報錯

class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    
    // 這就是控制「是否顯示廣告」的開關
    @Published var isPremium = false
    
    // 請填入您 RevenueCat 後台的 Public API Key
    // ⚠️ 記得要去 RevenueCat 後台複製您的 API Key 填入這裡
    private let apiKey = "appl_ZfXSpiCubLJWENiOHJLaIpZvHfB"
    private let entitlementId = "premium"
    private let removeAdsProductId = "idiomdict.remove_ads"
    
    init() {
            // [刪除] 這兩行刪掉，因為 StudentDictApp.swift 已經做過了
            // Purchases.logLevel = .debug
            // Purchases.configure(withAPIKey: apiKey)
            
            // [保留] 這行一定要留著，用來檢查會員狀態
            checkSubscriptionStatus()
        }
    
    // 檢查使用者是否已經付費
    func checkSubscriptionStatus() {
        Purchases.shared.getCustomerInfo { (customerInfo, error) in
            self.updatePremiumStatus(with: customerInfo)
        }
    }
    
    // 購買功能
    func purchase(package: Package) {
        Purchases.shared.purchase(package: package) { (transaction, customerInfo, error, userCancelled) in
            self.updatePremiumStatus(with: customerInfo)
        }
    }
    
    // 恢復購買 (Restore) - Apple 規定一定要有這個按鈕
    func restorePurchases() {
        Purchases.shared.restorePurchases { (customerInfo, error) in
            self.updatePremiumStatus(with: customerInfo)
        }
    }

    func updatePremiumStatus(with info: CustomerInfo?) {
        guard let info = info else { return }
        let hasEntitlement = info.entitlements[entitlementId]?.isActive == true
        let hasNonConsumable = info.allPurchasedProductIdentifiers.contains(removeAdsProductId)
        DispatchQueue.main.async {
            self.isPremium = hasEntitlement || hasNonConsumable
        }
    }
}
