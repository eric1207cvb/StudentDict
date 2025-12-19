import SwiftUI
import Speech

// MARK: - 1. Design System
struct AppTheme {
    static let background = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let primary = Color.blue
    static let secondary = Color.orange
    
    static func shadowColor(colorScheme: ColorScheme) -> Color {
        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }
}

// MARK: - 2. Main View
struct ContentView: View {
    @State private var searchText = ""
    @State private var results: [DictItem] = []
    @State private var historyItems: [DictItem] = []
    @State private var showLicense = false
    @StateObject private var speechInput = SpeechInputManager()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    // 搜尋列
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("輸入單字或按麥克風", text: $searchText)
                            .foregroundColor(.primary)
                            .onChange(of: searchText) { oldValue, newValue in performSearch(keyword: newValue) }
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.gray) }
                        }
                        Divider().frame(height: 20)
                        Button(action: {
                            speechInput.toggleRecording()
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }) {
                            Image(systemName: speechInput.isRecording ? "mic.fill" : "mic")
                                .font(.title2)
                                .foregroundColor(speechInput.isRecording ? .red : .blue)
                                .scaleEffect(speechInput.isRecording ? 1.2 : 1.0)
                                .animation(.spring(), value: speechInput.isRecording)
                        }
                    }
                    .padding()
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                    .shadow(color: AppTheme.shadowColor(colorScheme: colorScheme), radius: 5)
                    .padding()
                    
                    if speechInput.isRecording {
                        Text("正在聆聽...").font(.caption).foregroundColor(.red).padding(.bottom, 8)
                    }
                    
                    if !searchText.isEmpty { ResultListView(items: results) }
                    else if !historyItems.isEmpty { HistoryListView(items: historyItems, onClear: { DatabaseManager.shared.clearHistory(); loadHistory() }) }
                    else { EmptyStateView() }
                }
            }
            .navigationTitle("國語辭典簡編本")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showLicense = true }) {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showLicense) {
                LicenseView()
            }
            .onChange(of: speechInput.transcribedText) { oldValue, newValue in
                if !newValue.isEmpty { self.searchText = newValue }
            }
            .onAppear { loadHistory() }
        }
    }
    
    func performSearch(keyword: String) {
        if !keyword.isEmpty { results = DatabaseManager.shared.search(keyword: keyword) } else { results = [] }
    }
    func loadHistory() { historyItems = DatabaseManager.shared.getHistory() }
}

// MARK: - 3. License View (使用原生 Link)
struct LicenseView: View {
    @Environment(\.presentationMode) var presentationMode
    
    // 預先定義網址，確保正確
    let privacyURL = URL(string: "https://eric1207cvb.github.io/StudentDict/")!
    let eulaURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    let moeURL = URL(string: "https://dict.concised.moe.edu.tw/")!
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // 1. 開發者資訊
                    VStack(alignment: .leading, spacing: 8) {
                        Text("App 設計與開發")
                            .font(.headline)
                        
                        HStack(spacing: 16) {
                            Image("DeveloperAvatar")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                .shadow(radius: 3)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("HSUEH YI AN")
                                    .font(.title3).bold()
                                    .foregroundColor(.primary)
                                Text("Independent Developer")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    
                    Divider()
                    
                    // 2. 法律與條款 (改用原生 Link)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("法律與條款")
                            .font(.headline)
                        
                        // 隱私權政策 - 原生 Link
                        Link(destination: privacyURL) {
                            HStack {
                                Label("隱私權政策 (Privacy Policy)", systemImage: "hand.raised.fill")
                                    .foregroundColor(.blue)
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.05))
                            .cornerRadius(10)
                        }
                        
                        // EULA - 原生 Link
                        Link(destination: eulaURL) {
                            HStack {
                                Label("使用者授權合約 (EULA)", systemImage: "doc.text.fill")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    
                    Divider()
                    
                    // 3. 資料授權
                    VStack(alignment: .leading, spacing: 12) {
                        Text("資料來源授權")
                            .font(.headline)
                        
                        Text("本應用程式使用之資料來源為中華民國教育部《國語辭典簡編本》。")
                            .font(.body)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("授權條款：")
                                .font(.subheadline).bold()
                            Text("創用CC-姓名標示-禁止改作 臺灣 3.0 版")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("原始資料出處 (Attribution)：")
                                .font(.subheadline).bold()
                            
                            Text("中華民國教育部（Ministry of Education, R.O.C.）。")
                                .font(.caption)
                            
                            // 教育部官網 - 原生 Link
                            Link(destination: moeURL) {
                                HStack {
                                    Text("開啟教育部《國語辭典簡編本》官網")
                                    Spacer()
                                    Image(systemName: "globe")
                                }
                                .font(.caption).bold()
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.blue)
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    Spacer(minLength: 20)
                    
                    Text("本應用程式為第三方開發，非教育部官方 App。\n僅提供查詢介面，未對原始資料內容進行任何改作。")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("關於本程式")
            .navigationBarItems(trailing: Button("關閉") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

// MARK: - 4. Subviews
struct ResultListView: View {
    let items: [DictItem]
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(items) { item in
                    NavigationLink(destination: DetailView(item: item)) { WordCardView(item: item) }
                        .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal).padding(.bottom, 20)
        }
    }
}

struct HistoryListView: View {
    let items: [DictItem]
    let onClear: () -> Void
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label("最近查詢", systemImage: "clock.arrow.circlepath").font(.headline).foregroundColor(.secondary)
                Spacer()
                Button(action: onClear) { Text("清除").font(.caption).foregroundColor(.blue) }
            }
            .padding(.horizontal).padding(.top, 8)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(destination: DetailView(item: item)) { WordCardView(item: item) }
                            .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal).padding(.bottom, 20)
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "book.closed.circle.fill").font(.system(size: 80)).foregroundColor(.gray.opacity(0.2))
            Text("輸入單字開始查詢").font(.headline).foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - 5. Word Card
struct WordCardView: View {
    let item: DictItem
    @Environment(\.colorScheme) var colorScheme
    var isSingleChar: Bool { item.word.count == 1 }
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            if isSingleChar {
                VStack(alignment: .center, spacing: 6) {
                    Text(item.word)
                        .font(.system(size: 32, weight: .heavy, design: .serif))
                        .foregroundColor(AppTheme.primary)
                    Text(item.phonetic)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.secondary)
                }
                .frame(minWidth: 80)
                .padding(.vertical, 12).padding(.horizontal, 4)
                .background(Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.05))
                .cornerRadius(12)
            } else {
                MiniIdiomView(word: item.word, phonetic: item.phonetic)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if !item.radical.isEmpty && isSingleChar {
                    HStack(spacing: 8) {
                        Text("部首: \(item.radical)")
                        Text("筆畫: \(item.strokeCount)")
                    }
                    .font(.caption2).foregroundColor(.gray).padding(.bottom, 2)
                }
                Text(item.definition)
                    .font(.system(size: 16)).foregroundColor(.primary)
                    .lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.gray.opacity(0.5)).font(.system(size: 14, weight: .bold)).padding(.top, 12)
        }
        .padding(16).background(AppTheme.cardBackground).cornerRadius(20)
        .shadow(color: AppTheme.shadowColor(colorScheme: colorScheme), radius: 5, x: 0, y: 2)
    }
}

// MARK: - 6. Detail View
struct DetailView: View {
    let item: DictItem
    @State private var isFav: Bool = false
    @Environment(\.colorScheme) var colorScheme
    var isSingleChar: Bool { item.word.count == 1 }
    
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 0) {
                        if isSingleChar {
                            HStack(alignment: .top, spacing: 20) {
                                MiZiGeView(char: item.word)
                                    .frame(width: 120, height: 120)
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(item.phonetic)
                                        .font(.title3).fontWeight(.bold).foregroundColor(AppTheme.secondary)
                                        .padding(.vertical, 4).padding(.horizontal, 12)
                                        .background(AppTheme.secondary.opacity(0.1)).cornerRadius(8)
                                    Divider()
                                    InfoRow(title: "部首", value: item.radical.isEmpty ? "-" : item.radical)
                                    InfoRow(title: "總筆畫", value: "\(item.strokeCount)")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            IdiomBreakdownView(word: item.word, phonetic: item.phonetic)
                                .padding(.vertical, 10)
                        }
                    }
                    .padding(24)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(20)
                    .shadow(color: AppTheme.shadowColor(colorScheme: colorScheme), radius: 5)
                    
                    HStack(spacing: 40) {
                        ActionButton(icon: "speaker.wave.2.fill", text: "唸單字", color: .blue) {
                            SpeechManager.shared.speak(item.word)
                        }
                        ActionButton(icon: isFav ? "heart.fill" : "heart", text: isFav ? "已收藏" : "收藏", color: isFav ? .red : .gray) {
                            isFav = DatabaseManager.shared.toggleFavorite(word: item.word)
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("釋義", systemImage: "text.book.closed.fill").font(.headline).foregroundColor(.secondary)
                            Spacer()
                            Button(action: { SpeechManager.shared.speak(item.definition) }) {
                                HStack(spacing: 4) { Image(systemName: "speaker.wave.2"); Text("朗讀解釋") }
                                .font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.blue.opacity(0.1)).foregroundColor(.blue).cornerRadius(20)
                            }
                        }
                        Divider()
                        Text(item.definition)
                            .font(.system(size: 20)).lineSpacing(10).foregroundColor(.primary)
                            .onTapGesture { SpeechManager.shared.speak(item.definition) }
                    }
                    .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground).cornerRadius(24)
                    .shadow(color: AppTheme.shadowColor(colorScheme: colorScheme), radius: 5)
                }
                .padding()
            }
        }
        .onAppear {
            isFav = DatabaseManager.shared.isFavorite(word: item.word)
            DatabaseManager.shared.addToHistory(word: item.word)
        }
        .onDisappear { SpeechManager.shared.stop() }
    }
}

// MARK: - 7. Helper Components
struct IdiomBreakdownView: View {
    let word: String
    let phonetic: String
    
    var body: some View {
        let chars = Array(word)
        let phonetics = BopomofoSplitter.split(phonetic: phonetic, count: chars.count)
        
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<chars.count, id: \.self) { index in
                    VStack(spacing: 8) {
                        Text(String(chars[index]))
                            .font(.system(size: 44, weight: .black, design: .serif))
                            .foregroundColor(AppTheme.primary)
                            .frame(width: 50, height: 50)
                        
                        Text(index < phonetics.count ? phonetics[index] : "")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize()
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct MiniIdiomView: View {
    let word: String
    let phonetic: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let chars = Array(word)
        let phonetics = BopomofoSplitter.split(phonetic: phonetic, count: chars.count)
        let displayCount = min(chars.count, 4)
        
        HStack(spacing: 4) {
            ForEach(0..<displayCount, id: \.self) { index in
                VStack(spacing: 0) {
                    Text(String(chars[index]))
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundColor(AppTheme.primary)
                    
                    Text(index < phonetics.count ? phonetics[index] : "")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(width: 30)
            }
        }
        .padding(8)
        .background(Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.05))
        .cornerRadius(8)
    }
}

class BopomofoSplitter {
    static func split(phonetic: String, count: Int) -> [String] {
        let normalized = phonetic.replacingOccurrences(of: "\u{3000}", with: " ")
        var parts = normalized.components(separatedBy: " ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if parts.count == count { return parts }
        if parts.count > count { return Array(parts.prefix(count)) }
        var safeParts = parts
        while safeParts.count < count { safeParts.append("") }
        return safeParts
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
            Text(char).font(.system(size: 80, weight: .regular, design: .serif)).foregroundColor(.black)
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).font(.callout).foregroundColor(.gray).frame(width: 50, alignment: .leading)
            Text(value).font(.title3).fontWeight(.semibold).foregroundColor(.primary)
        }
    }
}

struct ActionButton: View {
    let icon: String
    let text: String
    let color: Color
    let action: () -> Void
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}git add .
