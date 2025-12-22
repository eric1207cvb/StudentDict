import SwiftUI
import Speech
import AVFoundation
import GoogleMobileAds // AdMob
import RevenueCat      // RevenueCat

// ==========================================
// MARK: - 1. 工具與設定 (Utils)
// ==========================================

struct AppTheme {
    static let background = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let primary = Color.blue
    static let secondary = Color.orange
    
    static func shadowColor(colorScheme: ColorScheme) -> Color {
        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }
    
    static func moeKaiFont(size: CGFloat) -> Font {
        let fontName = "TW-MOE-Std-Kai"
        if UIFont(name: fontName, size: size) != nil {
            return Font.custom(fontName, size: size)
        }
        return Font.system(size: size, weight: .regular, design: .serif)
    }
}

struct BopomofoData {
    static let initials = ["ㄅ", "ㄆ", "ㄇ", "ㄈ", "ㄉ", "ㄊ", "ㄋ", "ㄌ", "ㄍ", "ㄎ", "ㄏ", "ㄐ", "ㄑ", "ㄒ", "ㄓ", "ㄔ", "ㄕ", "ㄖ", "ㄗ", "ㄘ", "ㄙ"]
    static let medials = ["ㄧ", "ㄨ", "ㄩ"]
    static let finals = ["ㄚ", "ㄛ", "ㄜ", "ㄝ", "ㄞ", "ㄟ", "ㄠ", "ㄡ", "ㄢ", "ㄣ", "ㄤ", "ㄥ", "ㄦ"]
    static let tones = ["ˉ", "ˊ", "ˇ", "ˋ", "˙"]
    static var all: Set<String> { return Set(initials + medials + finals + tones) }
    static func isBopomofo(_ char: Character) -> Bool { return all.contains(String(char)) }
}

struct DefinitionItem: Identifiable {
    let id = UUID()
    let number: String?
    let text: String
    let example: String?
}

class DefinitionParser {
    static func parse(_ rawText: String) -> [DefinitionItem] {
        var items: [DefinitionItem] = []
        let pattern = "\\d+\\."
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsString = rawText as NSString
        let results = regex?.matches(in: rawText, range: NSRange(location: 0, length: nsString.length)) ?? []
        
        if !results.isEmpty {
            var lastLocation = 0
            for (index, match) in results.enumerated() {
                let start = match.range.location
                let end = match.range.location + match.range.length
                if index > 0 {
                    let content = nsString.substring(with: NSRange(location: lastLocation, length: start - lastLocation))
                    items.append(createItem(number: "\(index)", fullText: content))
                }
                lastLocation = end
            }
            if lastLocation < nsString.length {
                let content = nsString.substring(from: lastLocation)
                items.append(createItem(number: "\(results.count)", fullText: content))
            }
        } else {
            items.append(createItem(number: nil, fullText: rawText))
        }
        return items
    }
    
    private static func createItem(number: String?, fullText: String) -> DefinitionItem {
        let cleanText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let exampleKeys = ["如：", "例如：", "譬如：", "造句："]
        for key in exampleKeys {
            if let range = cleanText.range(of: key) {
                let definitionPart = String(cleanText[..<range.lowerBound])
                let examplePart = String(cleanText[range.lowerBound...])
                return DefinitionItem(number: number, text: definitionPart, example: examplePart)
            }
        }
        return DefinitionItem(number: number, text: cleanText, example: nil)
    }
}

class BopomofoSplitter {
    static func split(phonetic: String, count: Int) -> [String] {
        let normalized = phonetic.replacingOccurrences(of: "\u{3000}", with: " ")
        let parts = normalized.components(separatedBy: " ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count == count { return parts }
        if parts.count > count { return Array(parts.prefix(count)) }
        var safeParts = parts
        while safeParts.count < count { safeParts.append("") }
        return safeParts
    }
}

struct ZhuyinIME {
    static let shared = ZhuyinIME()
    func getCandidates(for input: String) -> [String] {
        let currentBopomofo = extractLastBopomofo(from: input)
        if currentBopomofo.isEmpty { return [] }
        return DatabaseManager.shared.searchByPhonetic(currentBopomofo)
    }
    private func extractLastBopomofo(from text: String) -> String {
        var result = ""
        for char in text.reversed() {
            if BopomofoData.isBopomofo(char) { result.insert(char, at: result.startIndex) }
            else { break }
        }
        return result
    }
}

// ==========================================
// MARK: - 2. 主視圖 (Main View)
// ==========================================

struct ContentView: View {
    @State private var searchText = ""
    @State private var results: [DictItem] = []
    
    @State private var historyItems: [DictItem] = []
    @State private var favoriteItems: [DictItem] = []
    
    @State private var selectedTab = 0
    
    @State private var showLicense = false
    @State private var showCustomKeyboard = true
    @State private var isLoading = true
    @StateObject private var speechInput = SpeechInputManager()
    
    @StateObject private var purchaseManager = PurchaseManager.shared
    @State private var isPurchasing = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    @Environment(\.colorScheme) var colorScheme
    
    // [工具] 判斷是否為 iPad
    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    
    var body: some View {
        ZStack {
            if isLoading {
                LaunchScreenView().transition(.opacity).zIndex(2)
            } else {
                NavigationView {
                    ZStack {
                        AppTheme.background.ignoresSafeArea()
                        
                        // [新增] 外層容器，用來居中 iPad 內容
                        VStack(spacing: 0) {
                            VStack(spacing: 0) {
                                // --- 頂部區塊 (搜尋 + 分頁) ---
                                VStack(spacing: 12) {
                                    // 1. 搜尋列
                                    HStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundColor(.gray)
                                            .font(isPad ? .title2 : .body)
                                        
                                        SimulatedTextField(text: searchText, placeholder: "輸入單字或按麥克風")
                                            .onTapGesture { withAnimation(.spring()) { showCustomKeyboard = true } }
                                        
                                        if !searchText.isEmpty {
                                            Button(action: { searchText = ""; results = [] }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.gray)
                                                    .font(isPad ? .title2 : .title3)
                                            }
                                            Button(action: {
                                                if !searchText.isEmpty {
                                                    searchText.removeLast()
                                                    if searchText.isEmpty { results = [] }
                                                    else { performSearch(keyword: searchText) }
                                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                }
                                            }) {
                                                Image(systemName: "delete.left.fill")
                                                    .foregroundColor(.gray)
                                                    .font(isPad ? .title2 : .title3)
                                                    .padding(.leading, 4)
                                            }
                                        }
                                        
                                        Button(action: {
                                            speechInput.toggleRecording()
                                            if speechInput.isRecording { showCustomKeyboard = false }
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }) {
                                            Image(systemName: speechInput.isRecording ? "mic.fill" : "mic")
                                                .font(isPad ? .title : .title2)
                                                .foregroundColor(speechInput.isRecording ? .red : .blue)
                                                .scaleEffect(speechInput.isRecording ? 1.2 : 1.0)
                                        }
                                        
                                        Button(action: { withAnimation(.spring()) { showCustomKeyboard.toggle() } }) {
                                            Image(systemName: showCustomKeyboard ? "keyboard.chevron.compact.down.fill" : "keyboard.fill")
                                                .font(isPad ? .title : .title2)
                                                .foregroundColor(showCustomKeyboard ? .orange : .gray)
                                        }
                                    }
                                    .padding(isPad ? 16 : 12)
                                    .background(AppTheme.cardBackground)
                                    .cornerRadius(12)
                                    .shadow(color: AppTheme.shadowColor(colorScheme: colorScheme), radius: 5)
                                    
                                    // 2. 分頁切換器
                                    if searchText.isEmpty {
                                        Picker("Tab", selection: $selectedTab) {
                                            Text("最近查詢").tag(0)
                                            Text("我的收藏").tag(1)
                                        }
                                        .pickerStyle(SegmentedPickerStyle())
                                        .padding(.horizontal, 4)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                    }
                                }
                                .padding()
                                
                                if speechInput.isRecording { Text("正在聆聽...").font(.caption).foregroundColor(.red).padding(.bottom, 8) }
                                
                                // --- 內容顯示區 ---
                                ZStack {
                                    if !searchText.isEmpty {
                                        if results.isEmpty { VStack { Spacer(); Text("搜尋中 / 查無結果").foregroundColor(.gray); Spacer() } }
                                        else { ResultListView(items: results) }
                                    } else {
                                        if selectedTab == 0 {
                                            if historyItems.isEmpty { EmptyStateView(title: "尚無查詢紀錄") }
                                            else {
                                                HistoryListView(items: historyItems, onClear: {
                                                    DatabaseManager.shared.clearHistory(); loadData()
                                                })
                                            }
                                        } else {
                                            if favoriteItems.isEmpty { EmptyStateView(title: "尚無收藏單字", icon: "heart.slash") }
                                            else {
                                                FavoritesListView(items: favoriteItems) {
                                                    loadData()
                                                }
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                
                                // --- [AdMob] 廣告橫幅 ---
                                if !purchaseManager.isPremium {
                                    AdBannerView()
                                        .frame(height: isPad ? 90 : 60)
                                        .frame(maxWidth: .infinity)
                                        .background(Color(.systemBackground))
                                        .padding(.bottom, 5)
                                }
                                
                                // --- 自訂鍵盤區 ---
                                if showCustomKeyboard {
                                    ZhuyinKeyboardView(text: $searchText, onUpdate: { performSearch(keyword: searchText) })
                                        .frame(height: isPad ? 450 : 400)
                                        .transition(.move(edge: .bottom))
                                        .zIndex(1)
                                }
                            }
                            // [關鍵優化] 限制 iPad 內容最大寬度 720，避免橫式太寬，並置中
                            .frame(maxWidth: isPad ? 720 : .infinity)
                        }
                        .frame(maxWidth: .infinity) // 讓內容在螢幕中間
                    }
                    .navigationTitle("國語辭典簡編本")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                if !purchaseManager.isPremium {
                                    Button(action: { startDirectPurchase() }) {
                                        Label("移除廣告 (NT$60)", systemImage: "heart.fill")
                                    }
                                }
                                Button(action: { restorePurchases() }) {
                                    Label("恢復購買", systemImage: "arrow.clockwise")
                                }
                                Button(action: { showLicense = true }) {
                                    Label("關於本程式", systemImage: "info.circle")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .sheet(isPresented: $showLicense) { LicenseView() }
                    .onChange(of: selectedTab) { _ in loadData() }
                    .onChange(of: speechInput.transcribedText) { _, newValue in
                        if !newValue.isEmpty { self.searchText = newValue; performSearch(keyword: newValue) }
                    }
                    .onChange(of: searchText) { _, newValue in performSearch(keyword: newValue) }
                    .onAppear { loadData() }
                    .alert(isPresented: $showAlert) {
                        Alert(title: Text("提示"), message: Text(alertMessage), dismissButton: .default(Text("好")))
                    }
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation { isLoading = false } }
        }
    }
    
    // MARK: - 邏輯功能
    func startDirectPurchase() {
        isPurchasing = true
        Purchases.shared.getOfferings { offerings, error in
            if let package = offerings?.current?.availablePackages.first {
                Purchases.shared.purchase(package: package) { transaction, customerInfo, error, userCancelled in
                    isPurchasing = false
                    if let error = error {
                        if !userCancelled {
                            alertMessage = "購買發生錯誤：\(error.localizedDescription)"
                            showAlert = true
                        }
                    } else if customerInfo?.entitlements["premium"]?.isActive == true {
                        purchaseManager.isPremium = true
                        alertMessage = "購買成功！廣告已移除。"
                        showAlert = true
                    }
                }
            } else {
                isPurchasing = false
                alertMessage = "無法連接到商店，請檢查網路連線或稍後再試。"
                showAlert = true
            }
        }
    }
    
    func restorePurchases() {
        isPurchasing = true
        Purchases.shared.restorePurchases { customerInfo, error in
            isPurchasing = false
            if let info = customerInfo, info.entitlements["premium"]?.isActive == true {
                purchaseManager.isPremium = true
                alertMessage = "已成功恢復您的購買權益！"
            } else {
                alertMessage = "查無此帳號的購買紀錄。"
            }
            showAlert = true
        }
    }
    
    func performSearch(keyword: String) {
        if !keyword.isEmpty { results = DatabaseManager.shared.search(keyword: keyword) } else { results = [] }
    }
    
    func loadData() {
        historyItems = DatabaseManager.shared.getHistory()
        favoriteItems = DatabaseManager.shared.getFavorites()
    }
}

// ==========================================
// MARK: - 3. 詳情視圖 (Detail View)
// ==========================================

struct DetailView: View {
    let item: DictItem
    @State private var isFav: Bool = false
    @Environment(\.colorScheme) var colorScheme
    var definitions: [DefinitionItem] { DefinitionParser.parse(item.definition) }
    var isSingleChar: Bool { item.word.count == 1 }
    
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 0) {
                        if isSingleChar {
                            HStack(alignment: .top, spacing: 20) {
                                MiZiGeView(char: item.word)
                                    .frame(width: 140, height: 140)
                                    .shadow(radius: 2)
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(item.phonetic)
                                        .font(.system(size: 24, weight: .heavy))
                                        .foregroundColor(.white)
                                        .padding(.vertical, 6).padding(.horizontal, 16)
                                        .background(Capsule().fill(Color.orange))
                                        .shadow(color: .orange.opacity(0.3), radius: 3, x: 0, y: 2)
                                    Divider()
                                    VStack(alignment: .leading, spacing: 8) {
                                        InfoLabel(title: "部首", value: item.radical.isEmpty ? "-" : item.radical, icon: "book.closed")
                                        InfoLabel(title: "筆畫", value: "\(item.strokeCount) 畫", icon: "pencil")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            IdiomBreakdownView(word: item.word, phonetic: item.phonetic)
                                .padding(.vertical, 10)
                        }
                    }
                    .padding(24).background(AppTheme.cardBackground).cornerRadius(24)
                    .shadow(color: AppTheme.shadowColor(colorScheme: colorScheme), radius: 8, x: 0, y: 4)
                    
                    HStack(spacing: 20) {
                        ActionButton(icon: "speaker.wave.3.fill", text: "唸發音", color: .blue) {
                            SpeechManager.shared.speak(item.word)
                        }
                        ActionButton(icon: isFav ? "heart.fill" : "heart", text: isFav ? "已收藏" : "收藏", color: isFav ? .red : .gray) {
                            isFav = DatabaseManager.shared.toggleFavorite(word: item.word)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "text.book.closed.fill").foregroundColor(.green)
                            Text("解釋與造句").font(.headline).foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        
                        ForEach(definitions) { def in
                            DefinitionCard(def: def)
                                .onTapGesture {
                                    SpeechManager.shared.speak(def.text + (def.example ?? ""))
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                        }
                    }
                    .padding(.bottom, 40)
                }
                .padding()
                // [優化] 詳情頁內容也限制寬度，避免 iPad 橫式太難讀
                .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 720 : .infinity)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            isFav = DatabaseManager.shared.isFavorite(word: item.word)
            DatabaseManager.shared.addToHistory(word: item.word)
        }
        .onDisappear { SpeechManager.shared.stop() }
    }
}

// ==========================================
// MARK: - 4. 列表元件 (Lists)
// ==========================================

struct ResultListView: View {
    let items: [DictItem]
    let columns = [GridItem(.adaptive(minimum: 300), spacing: 16)]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    NavigationLink(destination: DetailView(item: item)) { WordCardView(item: item) }.buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal).padding(.bottom, 20)
        }
    }
}

struct FavoritesListView: View {
    let items: [DictItem]; let onRefresh: () -> Void
    let columns = [GridItem(.adaptive(minimum: 300), spacing: 16)]
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label("我的收藏", systemImage: "heart.fill").font(.headline).foregroundColor(.red)
                Spacer()
                Text("\(items.count) 個單字").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal).padding(.top, 8)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        NavigationLink(destination: DetailView(item: item).onDisappear(perform: onRefresh)) {
                            WordCardView(item: item)
                                .overlay(Image(systemName: "heart.fill").foregroundColor(.red).padding(12), alignment: .topTrailing)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal).padding(.bottom, 20)
            }
        }
    }
}

struct HistoryListView: View {
    let items: [DictItem]; let onClear: () -> Void
    let columns = [GridItem(.adaptive(minimum: 300), spacing: 16)]
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label("最近查詢", systemImage: "clock.arrow.circlepath").font(.headline).foregroundColor(.secondary)
                Spacer()
                Button(action: onClear) { Text("清除").font(.caption).foregroundColor(.blue) }
            }
            .padding(.horizontal).padding(.top, 8)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        NavigationLink(destination: DetailView(item: item)) { WordCardView(item: item) }.buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal).padding(.bottom, 20)
            }
        }
    }
}

// ==========================================
// MARK: - 5. 通用元件 (Common Components)
// ==========================================

struct EmptyStateView: View {
    var title: String = "輸入單字開始查詢"
    var icon: String = "book.closed.circle.fill"
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon).font(.system(size: 80)).foregroundColor(.gray.opacity(0.2))
            Text(title).font(.headline).foregroundColor(.secondary)
            Spacer()
        }
    }
}

struct MiZiGeView: View {
    let char: String
    var body: some View {
        ZStack {
            Rectangle().stroke(Color.red, lineWidth: 3).background(Color.white)
            GeometryReader { geo in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height/2))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height/2))
                    path.move(to: CGPoint(x: geo.size.width/2, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width/2, y: geo.size.height))
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.move(to: CGPoint(x: geo.size.width, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                }
                .stroke(Color.red.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5]))
            }
            Text(char)
                .font(AppTheme.moeKaiFont(size: 90))
                .foregroundColor(.black)
        }
    }
}

struct IdiomBreakdownView: View {
    let word: String; let phonetic: String
    var body: some View {
        let chars = Array(word); let phonetics = BopomofoSplitter.split(phonetic: phonetic, count: chars.count)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<chars.count, id: \.self) { index in
                    VStack(spacing: 8) {
                        Text(String(chars[index]))
                            .font(AppTheme.moeKaiFont(size: 48))
                            .foregroundColor(AppTheme.primary)
                            .frame(width: 50, height: 50)
                        Text(index < phonetics.count ? phonetics[index] : "")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.secondary)
                            .multilineTextAlignment(.center).fixedSize()
                    }
                    .padding(8).background(Color.gray.opacity(0.05)).cornerRadius(8)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct WordCardView: View {
    let item: DictItem
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            if item.word.count == 1 {
                VStack(alignment: .center, spacing: 6) {
                    Text(item.word)
                        .font(AppTheme.moeKaiFont(size: 34))
                        .foregroundColor(AppTheme.primary)
                    Text(item.phonetic).font(.system(size: 14, weight: .medium)).foregroundColor(AppTheme.secondary)
                }
                .frame(minWidth: 80).padding(.vertical, 12).padding(.horizontal, 4)
                .background(Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.05)).cornerRadius(12)
            } else {
                MiniIdiomView(word: item.word, phonetic: item.phonetic)
            }
            VStack(alignment: .leading, spacing: 4) {
                if !item.radical.isEmpty && item.word.count == 1 {
                    HStack(spacing: 8) {
                        Text("部首: \(item.radical)").font(.caption2).foregroundColor(.gray)
                        Text("筆畫: \(item.strokeCount)").font(.caption2).foregroundColor(.gray)
                    }
                    .padding(.bottom, 2)
                }
                Text(item.definition).font(.system(size: 16)).foregroundColor(.primary).lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.gray.opacity(0.5)).font(.system(size: 14, weight: .bold)).padding(.top, 12)
        }
        .padding(16).background(AppTheme.cardBackground).cornerRadius(20)
        .shadow(color: AppTheme.shadowColor(colorScheme: colorScheme), radius: 5, x: 0, y: 2)
    }
}

struct MiniIdiomView: View {
    let word: String; let phonetic: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let chars = Array(word)
        let phonetics = BopomofoSplitter.split(phonetic: phonetic, count: chars.count)
        
        let availableWidth: CGFloat = 220
        let calculatedWidth = availableWidth / CGFloat(max(1, chars.count))
        let itemSize = min(34, max(20, calculatedWidth))
        let fontSize = itemSize * 0.7
        
        HStack(spacing: 2) {
            ForEach(0..<chars.count, id: \.self) { index in
                VStack(spacing: 0) {
                    Text(String(chars[index]))
                        .font(AppTheme.moeKaiFont(size: fontSize))
                        .foregroundColor(AppTheme.primary)
                        .frame(height: itemSize)
                    
                    Text(index < phonetics.count ? phonetics[index] : "")
                        .font(.system(size: max(9, fontSize * 0.45), weight: .medium))
                        .foregroundColor(AppTheme.secondary)
                        .lineLimit(1).fixedSize()
                }
                .frame(width: itemSize)
            }
        }
        .padding(6)
        .background(Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.05))
        .cornerRadius(8)
    }
}

// MARK: - 6. 其他 UI 元件 (Extensions & Components)

struct DefinitionCard: View {
    let def: DefinitionItem
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let num = def.number {
                Text(num).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                    .frame(width: 32, height: 32).background(Circle().fill(Color.blue.opacity(0.8))).shadow(radius: 2)
            } else {
                Circle().fill(Color.blue.opacity(0.5)).frame(width: 12, height: 12).padding(.top, 10).padding(.leading, 8)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(def.text).font(.system(size: 20, weight: .medium)).foregroundColor(.primary).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                if let example = def.example {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "quote.opening").foregroundColor(.green.opacity(0.7)).font(.caption).padding(.top, 2)
                        Text(example).font(.system(size: 18)).foregroundColor(colorScheme == .dark ? .green.opacity(0.8) : .green.opacity(0.9)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12).background(Color.green.opacity(0.05)).cornerRadius(12)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(AppTheme.cardBackground)
        .cornerRadius(20).shadow(color: AppTheme.shadowColor(colorScheme: colorScheme), radius: 4, x: 0, y: 2)
        .overlay(Image(systemName: "speaker.wave.2.circle").foregroundColor(.gray.opacity(0.3)).padding(12), alignment: .topTrailing)
    }
}

struct ActionButton: View {
    let icon: String; let text: String; let color: Color; let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(color.opacity(colorScheme == .dark ? 0.2 : 0.1)).frame(width: 60, height: 60)
                    Image(systemName: icon).font(.title2).foregroundColor(color)
                }
                Text(text).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}

struct InfoLabel: View {
    let title: String; let value: String; let icon: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(.gray).font(.footnote).frame(width: 20)
            Text(title).font(.callout).foregroundColor(.secondary)
            Text(value).font(.title3).fontWeight(.semibold).foregroundColor(.primary)
        }
    }
}

struct SimulatedTextField: View {
    let text: String; let placeholder: String
    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    
    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.gray.opacity(0.6))
                    .font(.system(size: isPad ? 22 : 17))
            }
            HStack(spacing: 0) {
                Text(text)
                    .foregroundColor(.primary)
                    .font(.system(size: isPad ? 22 : 17))
                
                if !text.isEmpty { BlinkingCursor() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: isPad ? 44 : 30)
        .contentShape(Rectangle())
    }
}

struct BlinkingCursor: View {
    @State private var isVisible = true
    var body: some View {
        Rectangle().fill(Color.blue).frame(width: 2, height: 20).opacity(isVisible ? 1 : 0)
            .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever()) { isVisible.toggle() } }
    }
}

struct LaunchScreenView: View {
    @State private var isBouncing = false
    var body: some View {
        ZStack {
            Color.blue.opacity(0.1).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "book.fill").font(.system(size: 80)).foregroundColor(.blue)
                    .offset(y: isBouncing ? -20 : 0)
                    .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isBouncing)
                Text("字典準備中...").font(.headline).foregroundColor(.secondary)
            }
        }
        .onAppear { isBouncing = true }
    }
}

struct LicenseView: View {
    @Environment(\.presentationMode) var presentationMode
    
    let privacyURL = URL(string: "https://eric1207cvb.github.io/StudentDict/")!
    let eulaURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    let moeURL = URL(string: "https://dict.concised.moe.edu.tw/")!
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("App 設計與開發").font(.headline)
                        HStack(spacing: 16) {
                            Image("DeveloperAvatar")
                                .resizable().scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                .shadow(radius: 3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("HSUEH YI AN").font(.title3).bold().foregroundColor(.primary)
                                Text("Independent Developer").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground)).cornerRadius(12)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("法律與條款").font(.headline)
                        Link(destination: privacyURL) {
                            HStack {
                                Label("隱私權政策 (Privacy Policy)", systemImage: "hand.raised.fill").foregroundColor(.blue)
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundColor(.gray)
                            }
                            .padding().background(Color.blue.opacity(0.05)).cornerRadius(10)
                        }
                        Link(destination: eulaURL) {
                            HStack {
                                Label("使用者授權合約 (EULA)", systemImage: "doc.text.fill").foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundColor(.gray)
                            }
                            .padding().background(Color.gray.opacity(0.1)).cornerRadius(10)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("資料來源授權").font(.headline)
                        Text("本應用程式使用之資料來源為中華民國教育部《國語辭典簡編本》。").font(.body)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("授權條款：").font(.subheadline).bold()
                            Text("創用CC-姓名標示-禁止改作 臺灣 3.0 版").font(.caption).foregroundColor(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("原始資料出處 (Attribution)：").font(.subheadline).bold()
                            Text("中華民國教育部（Ministry of Education, R.O.C.）。").font(.caption)
                            Link(destination: moeURL) {
                                HStack {
                                    Text("開啟教育部《國語辭典簡編本》官網")
                                    Spacer()
                                    Image(systemName: "globe")
                                }
                                .font(.caption).bold().foregroundColor(.white)
                                .padding(10).background(Color.blue).cornerRadius(8)
                            }
                        }
                    }
                    Spacer(minLength: 20)
                    Text("本應用程式為第三方開發，非教育部官方 App。\n僅提供查詢介面，未對原始資料內容進行任何改作。")
                        .font(.caption).foregroundColor(.gray).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("關於本程式")
            .navigationBarItems(trailing: Button("關閉") { presentationMode.wrappedValue.dismiss() })
        }
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// MARK: - 8. 鍵盤與廣告元件 (iPad 優化版)

struct ExpandedCandidatePanel: View {
    let candidates: [String]
    @Binding var isPresented: Bool
    let onSelect: (String) -> Void
    let gridColumns = [GridItem(.adaptive(minimum: UIDevice.current.userInterfaceIdiom == .pad ? 80 : 50), spacing: 10)]
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea().onTapGesture { withAnimation { isPresented = false } }
            VStack(spacing: 0) {
                HStack {
                    Text("請選擇國字").font(.headline).foregroundColor(.primary)
                    Spacer()
                    Button(action: { withAnimation { isPresented = false } }) {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.gray)
                    }
                }
                .padding().background(Color(.secondarySystemGroupedBackground))
                Divider()
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(candidates, id: \.self) { char in
                            Button(action: { onSelect(char) }) {
                                Text(char)
                                    .font(AppTheme.moeKaiFont(size: UIDevice.current.userInterfaceIdiom == .pad ? 36 : 28))
                                    .foregroundColor(.primary)
                                    .frame(minWidth: UIDevice.current.userInterfaceIdiom == .pad ? 80 : 60, minHeight: UIDevice.current.userInterfaceIdiom == .pad ? 80 : 60)
                                    .background(Color.blue.opacity(0.05))
                                    .cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.1), lineWidth: 1))
                            }
                        }
                    }
                    .padding().padding(.bottom, 20)
                }
                .frame(maxHeight: UIDevice.current.userInterfaceIdiom == .pad ? 450 : 320)
            }
            .background(Color(.systemBackground)).cornerRadius(16, corners: [.topLeft, .topRight])
            .shadow(radius: 10).padding(.horizontal, 10).padding(.bottom, 10).frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct ZhuyinKeyboardView: View {
    @Binding var text: String
    var onUpdate: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @State private var showExpandedCandidates = false
    @State private var candidates: [String] = []
    
    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    
    var gridBopomofo: [String] { BopomofoData.initials + BopomofoData.medials + BopomofoData.finals }
    
    struct ToneItem { let symbol: String; let name: String }
    let toneItems = [
        ToneItem(symbol: "ˉ", name: "一聲"), ToneItem(symbol: "ˊ", name: "二聲"),
        ToneItem(symbol: "ˇ", name: "三聲"), ToneItem(symbol: "ˋ", name: "四聲"),
        ToneItem(symbol: "˙", name: "輕聲")
    ]
    
    var columns: [GridItem] {
        [GridItem(.adaptive(minimum: isPad ? 55 : 36), spacing: isPad ? 10 : 5)]
    }
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(UIColor.systemGray6) : Color(UIColor.systemGray6)).ignoresSafeArea()
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(AppTheme.cardBackground)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 2)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                    
                    if candidates.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil.and.outline").foregroundColor(.orange).font(.title3)
                            if text.isEmpty || !BopomofoData.isBopomofo(text.last ?? " ") {
                                Text("點擊下方按鍵開始拼音...").font(.system(size: 16, weight: .medium)).foregroundColor(.gray)
                            } else {
                                Text("找不到這個拼音喔！").font(.system(size: 16, weight: .medium)).foregroundColor(.red.opacity(0.6))
                            }
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(candidates.prefix(15), id: \.self) { char in
                                    Button(action: { selectChar(char) }) {
                                        Text(char)
                                            .font(AppTheme.moeKaiFont(size: 24))
                                            .foregroundColor(.primary)
                                            .frame(width: 50, height: 44).background(Color.blue.opacity(0.1)).cornerRadius(10)
                                    }
                                }
                                if candidates.count > 15 {
                                    Button(action: {
                                        withAnimation(.spring()) { showExpandedCandidates = true }
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }) {
                                        VStack(spacing: 2) {
                                            Image(systemName: "chevron.down.circle.fill").font(.title2)
                                            Text("更多").font(.caption2).fontWeight(.bold)
                                        }
                                        .foregroundColor(.white).frame(width: 50, height: 44).background(Color.orange).cornerRadius(10)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .frame(height: 60).padding(.horizontal, 8).padding(.top, 8)
                
                // 聲調列
                HStack(spacing: 6) {
                    ForEach(toneItems, id: \.symbol) { item in
                        Button(action: {
                            if item.symbol != "ˉ" { text += item.symbol }
                            onUpdate()
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        }) {
                            VStack(spacing: 0) {
                                Text(item.symbol).font(.system(size: isPad ? 28 : 20, weight: .bold)).frame(height: isPad ? 32 : 24)
                                Text(item.name).font(.system(size: isPad ? 14 : 10, weight: .regular)).padding(.bottom, 4)
                            }
                            .foregroundColor(.purple).frame(maxWidth: .infinity).frame(height: isPad ? 55 : 50)
                            .background(Color.purple.opacity(0.1)).cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.2), lineWidth: 1))
                        }
                    }
                    Button(action: {
                        if !text.isEmpty { text.removeLast(); onUpdate() }
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    }) {
                        Image(systemName: "delete.left.fill").font(.system(size: isPad ? 30 : 22)).foregroundColor(.white)
                            .frame(width: isPad ? 70 : 54, height: isPad ? 55 : 50).background(Color.gray.opacity(0.8)).cornerRadius(8)
                    }
                }
                .padding(.horizontal, 8)
                
                // 注音鍵盤區
                LazyVGrid(columns: columns, spacing: isPad ? 10 : 8) {
                    ForEach(gridBopomofo, id: \.self) { char in
                        Button(action: {
                            text += char
                            onUpdate()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }) {
                            Text(char).font(.system(size: isPad ? 34 : 20, weight: .semibold)).foregroundColor(getTextColor(for: char))
                                .frame(minWidth: isPad ? 64 : 32, minHeight: isPad ? 55 : 46).frame(maxWidth: .infinity)
                                .background(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white).cornerRadius(6)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.1), radius: 1, x: 0, y: 1)
                        }
                    }
                }
                .padding(.horizontal, isPad ? 20 : 8)
                // [修改] 這裡的 padding 縮小，把空間留給下面的連結
                .padding(.bottom, 0)
                
                // [新增] 隱私權與 EULA 連結 (致中、小字)
                HStack(spacing: 16) {
                    Link("隱私權政策", destination: URL(string: "https://eric1207cvb.github.io/StudentDict/")!)
                    Text("|").foregroundColor(.gray.opacity(0.5))
                    Link("使用者授權合約 (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.bottom, isPad ? 20 : 10) // 底部安全距離移到這裡
            }
            if showExpandedCandidates {
                ExpandedCandidatePanel(candidates: candidates, isPresented: $showExpandedCandidates, onSelect: selectChar)
                    .transition(.move(edge: .bottom).combined(with: .opacity)).zIndex(100)
            }
        }
        .frame(height: isPad ? 450 : 400)
        .onChange(of: text) { _, _ in updateCandidates() }
        .onAppear { updateCandidates() }
    }
    
    private func updateCandidates() {
        let new = ZhuyinIME.shared.getCandidates(for: text)
        self.candidates = new
        if new.isEmpty { withAnimation(.spring()) { showExpandedCandidates = false } }
    }
    private func selectChar(_ char: String) {
        while let last = text.last, BopomofoData.isBopomofo(last) { text.removeLast() }
        text += char
        onUpdate()
        withAnimation { showExpandedCandidates = false }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
    private func getTextColor(for char: String) -> Color {
        if BopomofoData.initials.contains(char) { return .primary }
        if BopomofoData.medials.contains(char) { return Color.green }
        if BopomofoData.finals.contains(char) { return Color.orange }
        return .primary
    }
}

struct AdBannerView: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let adSize = UIDevice.current.userInterfaceIdiom == .pad ? AdSizeLeaderboard : AdSizeBanner
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = "ca-app-pub-8563333250584395/7527216704"
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            banner.rootViewController = rootVC
        }
        banner.load(Request())
        return banner
    }
    func updateUIView(_ uiView: BannerView, context: Context) {}
}
