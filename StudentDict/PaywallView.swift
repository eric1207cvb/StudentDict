import SwiftUI
import RevenueCat

struct PaywallView: View {
    var offering: Offering? // 從上一頁傳進來的商品資料
    @Binding var isPresented: Bool //用來關閉視窗
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. 標題區：強調「無干擾」的功能利益
                Image(systemName: "book.closed.circle.fill") // 換成書本或學習相關的圖示
                    .resizable()
                    .scaledToFit()
                    .frame(height: 80)
                    .foregroundStyle(.blue) // 換成讓人專注的藍色或綠色
                    .padding(.top, 40)
                
                Text("開啟無干擾的學習模式") // [修改這裡] 大標題
                    .font(.title2) // 稍微縮小一點點，讓文字更精緻
                    .bold()
                    .multilineTextAlignment(.center)
                
                Text("移除所有廣告，專注於知識積累。\n您的支持是我持續維護 App 的最大動力。") // [修改這裡] 副標題：補充情感訴求
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                // ... 中間的功能列表 FeatureRow ...
                
                Spacer()
                
                // 3. 購買按鈕區：強調「支持開發」的行動
                if let package = offering?.availablePackages.first {
                    Button(action: {
                        purchase(package)
                    }) {
                        VStack(spacing: 4) {
                            Text("解鎖完整體驗並支持開發") // [修改這裡] 按鈕主文字
                                .font(.headline)
                                .bold()
                            
                            Text(package.storeProduct.localizedPriceString + " / 永久買斷") // 價格與方案
                                .font(.caption)
                                .opacity(0.9)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue) // 或用您的 App 主色調
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        .shadow(radius: 5) // 加一點陰影讓按鈕更明顯
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // 3. 購買按鈕區
                if let package = offering?.availablePackages.first {
                    Button(action: {
                        purchase(package)
                    }) {
                        VStack {
                            Text("立即升級")
                                .font(.headline)
                            Text(package.storeProduct.localizedPriceString) // 顯示價格 (如 $0.99)
                                .font(.subheadline)
                                .opacity(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                    }
                    .padding(.horizontal)
                } else {
                    Text("正在載入商品...")
                        .font(.caption)
                }
                
                // 4. 必要功能：恢復購買 (Restore)
                Button("恢復購買") {
                    restorePurchases()
                }
                .font(.footnote)
                .padding(.top, 10)
                
                // 5. 必要文字：法律聲明
                Text("此為一次性購買。退款請求請直接聯繫 Apple 支援。\n購買後即表示您同意我們的隱私權政策與使用條款。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }
    
    // 自定義的小勾勾元件
    func FeatureRow(text: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.body)
            Spacer()
        }
    }
    
    // 購買邏輯
    func purchase(_ package: Package) {
        Purchases.shared.purchase(package: package) { (transaction, customerInfo, error, userCancelled) in
            if let error = error {
                print("購買失敗: \(error.localizedDescription)")
            } else if !userCancelled {
                print("購買成功！")
                isPresented = false // 關閉視窗
            }
        }
    }
    
    // 恢復購買邏輯
    func restorePurchases() {
        Purchases.shared.restorePurchases { (customerInfo, error) in
            if let info = customerInfo, info.entitlements["premium"]?.isActive == true {
                print("恢復成功！")
                isPresented = false
            } else {
                print("查無購買紀錄")
            }
        }
    }
}
