import Foundation
import SQLite3

// MARK: - 1. Data Model
struct DictItem: Identifiable, Hashable {
    let id = UUID()
    let idiom: String
    let phonetic: String
    let definition: String
    let source: String
    let example: String
    let synonyms: String
    let antonyms: String
    let characterCount: Int
    let pinyin: String
    let sourceText: String
    let sourceNote: String
    let sourceRef: String
    let story: String
    let citations: String
    let usageSemantic: String
    let usageCategory: String
    let usageExample: String
    let discriminationForm: String
    let discriminationSame: String
    let discriminationDiff: String
    let discriminationExample: String
    let referenceTerms: String
    let entryType: String
}

// MARK: - 2. Database Manager
class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?
    private var hasExtendedColumns = false
    private var hasCharDictTable = false
    
    // 設定最大收藏數量
    private let maxFavoritesCount = 30
    
    private init() {
        openDatabase()
        createTables()
    }
    
    // MARK: - Database Setup (關鍵修正：複製到可寫入目錄)
    
    /// 取得沙盒中 Documents 目錄下的資料庫路徑 (可讀寫)
    private func getWritableDBPath() -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentsDirectory = paths[0]
        return (documentsDirectory as NSString).appendingPathComponent("dictionary.sqlite")
    }
    
    private func openDatabase() {
        let writablePath = getWritableDBPath()
        let fileManager = FileManager.default
        
        // 1. 檢查可寫入目錄是否存在資料庫
        if !fileManager.fileExists(atPath: writablePath) {
            print("📂 初次執行，準備將資料庫從 Bundle 複製到 Documents...")
            // 如果不存在，從 App Bundle 中尋找原始檔案
            guard let bundlePath = Bundle.main.path(forResource: "dictionary", ofType: "sqlite") else {
                print("❌ Fatal Error: 在 Bundle 中找不到 dictionary.sqlite 原始檔！請確認檔案有加入專案。")
                return
            }
            
            // 嘗試複製
            do {
                try fileManager.copyItem(atPath: bundlePath, toPath: writablePath)
                print("✅ 資料庫複製成功！路徑: \(writablePath)")
            } catch {
                print("❌ 資料庫複製失敗: \(error)")
                return
            }
        } else {
            print("📂 資料庫已存在於可寫入目錄，直接使用。")
        }
        
        // 2. 開啟位於可寫入目錄的資料庫
        if sqlite3_open(writablePath, &db) != SQLITE_OK {
            print("❌ Error: 無法開啟資料庫。")
            if let errorPointer = sqlite3_errmsg(db) {
                let errorMessage = String(cString: errorPointer)
                print("   SQLite Error: \(errorMessage)")
            }
        } else {
            print("✅ 資料庫連線成功。")
            detectSchema()
        }
    }
    
    private func createTables() {
        guard let db = db else { return }
        // favorites 表格：使用 word 當主鍵。
        // 注意：SQLite 預設有隱藏的 rowid 欄位，可用來判斷加入順序 (越小越早加入)
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS favorites (word TEXT PRIMARY KEY);", nil, nil, nil)
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS history (word TEXT PRIMARY KEY, timestamp REAL);", nil, nil, nil)
    }
    
    // MARK: - 🔍 主搜尋 (成語：字首匹配 + 定義/近義包含)
    func search(keyword: String) -> [DictItem] {
        var result: [DictItem] = []
        guard let db = db else { return [] }
        let idiomExpr = normalizedIdiomExpr(alias: "d")
        let phoneticExpr = normalizedPhoneticExpr(alias: "d")
        let definitionExpr = normalizedDefinitionExpr(alias: "d")
        let synonymsExpr = normalizedSynonymsExpr(alias: "d")
        let sourceExpr = normalizedSourceExpr(alias: "d")
        let exampleExpr = normalizedExampleExpr(alias: "d")
        let antonymsExpr = normalizedAntonymsExpr(alias: "d")
        let prefixOnly = isCJKPrefixQuery(keyword)

        let querySQL: String
        if prefixOnly {
            querySQL = """
                SELECT \(selectColumns(idiomExpr: idiomExpr, phoneticExpr: phoneticExpr, definitionExpr: definitionExpr, sourceExpr: sourceExpr, exampleExpr: exampleExpr, synonymsExpr: synonymsExpr, antonymsExpr: antonymsExpr, alias: "d"))
                FROM idiom_dict d
                WHERE \(idiomExpr) LIKE ?
                ORDER BY
                  CASE
                    WHEN \(idiomExpr) = ? THEN 0
                    ELSE 1
                  END ASC,
                  length(\(idiomExpr)) ASC
                LIMIT 100;
            """
        } else {
            querySQL = """
                SELECT \(selectColumns(idiomExpr: idiomExpr, phoneticExpr: phoneticExpr, definitionExpr: definitionExpr, sourceExpr: sourceExpr, exampleExpr: exampleExpr, synonymsExpr: synonymsExpr, antonymsExpr: antonymsExpr, alias: "d"))
                FROM idiom_dict d
                WHERE \(idiomExpr) LIKE ?
                   OR \(phoneticExpr) LIKE ?
                   OR \(definitionExpr) LIKE ?
                   OR \(synonymsExpr) LIKE ?
                ORDER BY
                  CASE
                    WHEN \(idiomExpr) = ? THEN 0
                    ELSE 1
                  END ASC,
                  length(\(idiomExpr)) ASC
                LIMIT 100;
            """
        }
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
            let nsKeyword = keyword as NSString
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            
            let prefixKeyword = "\(keyword)%"
            // 1. 成語字首
            sqlite3_bind_text(stmt, 1, (prefixKeyword as NSString).utf8String, -1, SQLITE_TRANSIENT)
            if prefixOnly {
                // 2. 排序用：完全匹配
                sqlite3_bind_text(stmt, 2, nsKeyword.utf8String, -1, SQLITE_TRANSIENT)
            } else {
                let containsKeyword = "%\(keyword)%"
                // 2. 注音字首
                sqlite3_bind_text(stmt, 2, (prefixKeyword as NSString).utf8String, -1, SQLITE_TRANSIENT)
                // 3. 定義/近義包含
                sqlite3_bind_text(stmt, 3, (containsKeyword as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, (containsKeyword as NSString).utf8String, -1, SQLITE_TRANSIENT)
                // 4. 排序用：完全匹配
                sqlite3_bind_text(stmt, 5, nsKeyword.utf8String, -1, SQLITE_TRANSIENT)
            }
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(parseRow(stmt: stmt))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    // MARK: - ⌨️ 鍵盤候選字搜尋
    func searchByPhonetic(_ bopomofo: String, prefix: String) -> [String] {
        var rawResults: [String] = []
        var fallbackResults: [String] = []
        guard let db = db else { return [] }
        if bopomofo.isEmpty { return [] }
        let queryHasTone = parseBopomofoQuery(bopomofo).tone != nil
        
        let idiomExpr = normalizedIdiomExpr(alias: "d")
        let phoneticExpr = normalizedPhoneticExpr(alias: "d")
        
        let querySQL: String
        if prefix.isEmpty {
            querySQL = """
                SELECT \(idiomExpr) AS idiom,
                       \(phoneticExpr) AS phonetic
                FROM idiom_dict d
                WHERE \(phoneticExpr) LIKE ?
                   OR \(phoneticExpr) LIKE ?
                LIMIT 2000;
            """
        } else {
            querySQL = """
                SELECT \(idiomExpr) AS idiom,
                       \(phoneticExpr) AS phonetic
                FROM idiom_dict d
                WHERE \(idiomExpr) LIKE ?
                LIMIT 1200;
            """
        }
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
            let searchString = prefix.isEmpty ? "\(bopomofo)%" : "\(prefix)%"
            sqlite3_bind_text(stmt, 1, (searchString as NSString).utf8String, -1, nil)
            if prefix.isEmpty {
                let variantSearch = "（%\(bopomofo)%"
                sqlite3_bind_text(stmt, 2, (variantSearch as NSString).utf8String, -1, nil)
            }
            
            let prefixCount = prefix.count
            while sqlite3_step(stmt) == SQLITE_ROW {
                let idiom = readColumn(stmt, 0)
                let phonetic = readColumn(stmt, 1)
                if idiom.count <= prefixCount { continue }
                let chars = Array(idiom)
                let syllables = BopomofoSplitter.split(phonetic: phonetic, count: chars.count)
                if prefixCount >= syllables.count { continue }
                let syllable = syllables[prefixCount]
                if matchesBopomofo(syllable, bopomofo) {
                    rawResults.append(String(chars[prefixCount]))
                } else if queryHasTone && matchesBopomofoIgnoringTone(syllable, bopomofo) {
                    fallbackResults.append(String(chars[prefixCount]))
                }
            }
        }
        sqlite3_finalize(stmt)
        
        let primary = NSOrderedSet(array: rawResults).array as? [String] ?? []
        if !primary.isEmpty { return primary }
        return NSOrderedSet(array: fallbackResults).array as? [String] ?? []
    }

    // Fallback: match any position to mimic general IME character lookup
    func searchByPhoneticAnyPosition(_ bopomofo: String) -> [String] {
        var rawResults: [String] = []
        guard let db = db else { return [] }
        if bopomofo.isEmpty { return [] }

        let idiomExpr = normalizedIdiomExpr(alias: "d")
        let phoneticExpr = normalizedPhoneticExpr(alias: "d")
        let querySQL = """
            SELECT \(idiomExpr) AS idiom,
                   \(phoneticExpr) AS phonetic
            FROM idiom_dict d
            WHERE \(phoneticExpr) LIKE ?
               OR \(phoneticExpr) LIKE ?
            LIMIT 2000;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
            let searchString = "%\(bopomofo)%"
            sqlite3_bind_text(stmt, 1, (searchString as NSString).utf8String, -1, nil)
            let variantSearch = "（%\(bopomofo)%"
            sqlite3_bind_text(stmt, 2, (variantSearch as NSString).utf8String, -1, nil)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let idiom = readColumn(stmt, 0)
                let phonetic = readColumn(stmt, 1)
                if idiom.isEmpty { continue }
                let chars = Array(idiom)
                let syllables = BopomofoSplitter.split(phonetic: phonetic, count: chars.count)
                if syllables.isEmpty { continue }
                for index in 0..<min(chars.count, syllables.count) {
                    if matchesBopomofo(syllables[index], bopomofo) {
                        rawResults.append(String(chars[index]))
                    }
                }
            }
        }
        sqlite3_finalize(stmt)

        return NSOrderedSet(array: rawResults).array as? [String] ?? []
    }

    // Character dictionary lookup (single characters)
    func searchCharByPhonetic(_ bopomofo: String) -> [String] {
        var rawResults: [String] = []
        var fallbackResults: [String] = []
        guard let db = db else { return [] }
        if bopomofo.isEmpty || !hasCharDictTable { return [] }

        let query = parseBopomofoQuery(bopomofo)
        if query.base.isEmpty { return [] }
        let queryHasTone = query.tone != nil

        let sql = """
            SELECT word, phonetic, variant_phonetic
            FROM char_dict
            WHERE phonetic LIKE ?
               OR variant_phonetic LIKE ?
            LIMIT 1200;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let likeString = "\(query.base)%"
            sqlite3_bind_text(stmt, 1, (likeString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (likeString as NSString).utf8String, -1, nil)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let word = readColumn(stmt, 0)
                let phonetic = readColumn(stmt, 1)
                let variant = readColumn(stmt, 2)
                if word.isEmpty { continue }
                let primary = BopomofoSplitter.normalizeForSyllables(phonetic)
                if matchesBopomofo(primary, bopomofo) {
                    rawResults.append(word)
                    continue
                } else if queryHasTone && matchesBopomofoIgnoringTone(primary, bopomofo) {
                    fallbackResults.append(word)
                    continue
                }
                if !variant.isEmpty {
                    let alt = BopomofoSplitter.normalizeForSyllables(variant)
                    if matchesBopomofo(alt, bopomofo) {
                        rawResults.append(word)
                        continue
                    } else if queryHasTone && matchesBopomofoIgnoringTone(alt, bopomofo) {
                        fallbackResults.append(word)
                    }
                }
            }
        }
        sqlite3_finalize(stmt)

        let primary = NSOrderedSet(array: rawResults).array as? [String] ?? []
        if !primary.isEmpty { return primary }
        return NSOrderedSet(array: fallbackResults).array as? [String] ?? []
    }
    
    // MARK: - History (歷史紀錄)
    func addToHistory(idiom: String) {
        guard let db = db else { return }
        let timestamp = Date().timeIntervalSince1970
        let insertSQL = "INSERT OR REPLACE INTO history (word, timestamp) VALUES (?, ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (idiom as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 2, timestamp)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        // 保持歷史紀錄最新的 50 筆
        sqlite3_exec(db, "DELETE FROM history WHERE word NOT IN (SELECT word FROM history ORDER BY timestamp DESC LIMIT 50);", nil, nil, nil)
    }
    
    func getHistory() -> [DictItem] {
        var result: [DictItem] = []
        guard let db = db else { return [] }
        let idiomExpr = normalizedIdiomExpr(alias: "d")
        let phoneticExpr = normalizedPhoneticExpr(alias: "d")
        let definitionExpr = normalizedDefinitionExpr(alias: "d")
        let sourceExpr = normalizedSourceExpr(alias: "d")
        let exampleExpr = normalizedExampleExpr(alias: "d")
        let synonymsExpr = normalizedSynonymsExpr(alias: "d")
        let antonymsExpr = normalizedAntonymsExpr(alias: "d")
        let sql = """
            SELECT \(selectColumns(idiomExpr: idiomExpr, phoneticExpr: phoneticExpr, definitionExpr: definitionExpr, sourceExpr: sourceExpr, exampleExpr: exampleExpr, synonymsExpr: synonymsExpr, antonymsExpr: antonymsExpr, alias: "d"))
            FROM history h
            INNER JOIN idiom_dict d ON h.word = \(idiomExpr)
            ORDER BY h.timestamp DESC
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(parseRow(stmt: stmt))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    func clearHistory() {
        guard let db = db else { return }
        sqlite3_exec(db, "DELETE FROM history;", nil, nil, nil)
    }
    
    // MARK: - Favorites (收藏 - 限制 30 筆)
    
    /// 切換收藏狀態：若已收藏則刪除，若未收藏則加入 (若滿 30 筆則刪除最舊的)
    func toggleFavorite(idiom: String) -> Bool {
        guard let db = db else {
            print("❌ DB Error: 資料庫未連接")
            return false
        }
        
        if isFavorite(idiom: idiom) {
            // --- 情況 A：已收藏，執行刪除 ---
            print("🗑️ 正在從收藏移除: \(idiom)")
            let deleteSQL = "DELETE FROM favorites WHERE word = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (idiom as NSString).utf8String, -1, nil)
                if sqlite3_step(stmt) == SQLITE_DONE {
                    print("✅ 移除成功")
                } else {
                    print("❌ 移除失敗 SQL Error")
                }
            }
            sqlite3_finalize(stmt)
            return false // 回傳 false 代表現在「未收藏」
            
        } else {
            // --- 情況 B：未收藏，準備加入 ---
            print("❤️ 準備加入收藏: \(idiom)")
            
            // 1. 檢查目前數量
            var currentCount = 0
            let countSQL = "SELECT count(*) FROM favorites;"
            var countStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, countSQL, -1, &countStmt, nil) == SQLITE_OK {
                if sqlite3_step(countStmt) == SQLITE_ROW {
                    currentCount = Int(sqlite3_column_int(countStmt, 0))
                }
            }
            sqlite3_finalize(countStmt)
            print("📊 目前收藏數量: \(currentCount)")
            
            // 2. 如果達到上限，刪除「最舊」的一筆
            // 這裡使用 SQLite 的 rowid 來判斷，rowid 最小的代表最早插入
            if currentCount >= maxFavoritesCount {
                print("⚠️ 達到收藏上限 (\(maxFavoritesCount))，正在刪除最舊的一筆...")
                let deleteOldestSQL = "DELETE FROM favorites WHERE rowid = (SELECT min(rowid) FROM favorites);"
                if sqlite3_exec(db, deleteOldestSQL, nil, nil, nil) == SQLITE_OK {
                     print("✅ 舊資料刪除成功")
                } else {
                     print("❌ 舊資料刪除失敗")
                }
            }
            
            // 3. 插入新收藏
            let insertSQL = "INSERT INTO favorites (word) VALUES (?);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (idiom as NSString).utf8String, -1, nil)
                if sqlite3_step(stmt) == SQLITE_DONE {
                    print("✅ 加入收藏成功: \(idiom)")
                } else {
                    print("❌ 加入失敗 (可能是 SQL 錯誤或約束衝突): \(idiom)")
                    if let errorPointer = sqlite3_errmsg(db) {
                        print("   SQLite Error: \(String(cString: errorPointer))")
                    }
                }
            }
            sqlite3_finalize(stmt)
            
            return true // 回傳 true 代表現在「已收藏」
        }
    }
    
    func isFavorite(idiom: String) -> Bool {
        guard let db = db else { return false }
        let sql = "SELECT count(*) FROM favorites WHERE word = ?;"
        var stmt: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (idiom as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return count > 0
    }
    
    // 取得所有收藏列表 (UI 需要此函式)
    func getFavorites() -> [DictItem] {
        var result: [DictItem] = []
        guard let db = db else { return [] }
        
        let idiomExpr = normalizedIdiomExpr(alias: "d")
        let phoneticExpr = normalizedPhoneticExpr(alias: "d")
        let definitionExpr = normalizedDefinitionExpr(alias: "d")
        let sourceExpr = normalizedSourceExpr(alias: "d")
        let exampleExpr = normalizedExampleExpr(alias: "d")
        let synonymsExpr = normalizedSynonymsExpr(alias: "d")
        let antonymsExpr = normalizedAntonymsExpr(alias: "d")
        let sql = """
            SELECT \(selectColumns(idiomExpr: idiomExpr, phoneticExpr: phoneticExpr, definitionExpr: definitionExpr, sourceExpr: sourceExpr, exampleExpr: exampleExpr, synonymsExpr: synonymsExpr, antonymsExpr: antonymsExpr, alias: "d"))
            FROM favorites f
            INNER JOIN idiom_dict d ON f.word = \(idiomExpr)
            ORDER BY f.rowid DESC;
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(parseRow(stmt: stmt))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    // MARK: - Helper
    private func parseRow(stmt: OpaquePointer?) -> DictItem {
        let idiom = readColumn(stmt, 0)
        let phonetic = readColumn(stmt, 1)
        let definition = readColumn(stmt, 2)
        let source = readColumn(stmt, 3)
        let example = readColumn(stmt, 4)
        let synonyms = readColumn(stmt, 5)
        let antonyms = readColumn(stmt, 6)
        let characterCount = idiom.count

        var pinyin = ""
        var sourceText = ""
        var sourceNote = ""
        var sourceRef = ""
        var story = ""
        var citations = ""
        var usageSemantic = ""
        var usageCategory = ""
        var usageExample = ""
        var discriminationForm = ""
        var discriminationSame = ""
        var discriminationDiff = ""
        var discriminationExample = ""
        var referenceTerms = ""
        var entryType = ""

        if hasExtendedColumns {
            pinyin = readColumn(stmt, 7)
            sourceText = readColumn(stmt, 8)
            sourceNote = readColumn(stmt, 9)
            sourceRef = readColumn(stmt, 10)
            story = readColumn(stmt, 11)
            citations = readColumn(stmt, 12)
            usageSemantic = readColumn(stmt, 13)
            usageCategory = readColumn(stmt, 14)
            usageExample = readColumn(stmt, 15)
            discriminationForm = readColumn(stmt, 16)
            discriminationSame = readColumn(stmt, 17)
            discriminationDiff = readColumn(stmt, 18)
            discriminationExample = readColumn(stmt, 19)
            referenceTerms = readColumn(stmt, 20)
            entryType = readColumn(stmt, 21)
        }

        return DictItem(
            idiom: idiom,
            phonetic: phonetic,
            definition: definition,
            source: source,
            example: example,
            synonyms: synonyms,
            antonyms: antonyms,
            characterCount: characterCount,
            pinyin: pinyin,
            sourceText: sourceText,
            sourceNote: sourceNote,
            sourceRef: sourceRef,
            story: story,
            citations: citations,
            usageSemantic: usageSemantic,
            usageCategory: usageCategory,
            usageExample: usageExample,
            discriminationForm: discriminationForm,
            discriminationSame: discriminationSame,
            discriminationDiff: discriminationDiff,
            discriminationExample: discriminationExample,
            referenceTerms: referenceTerms,
            entryType: entryType
        )
    }

    private func readColumn(_ stmt: OpaquePointer?, _ index: Int) -> String {
        guard let ptr = sqlite3_column_text(stmt, Int32(index)) else { return "" }
        return String(cString: ptr)
    }

    private func detectSchema() {
        guard let db = db else { return }
        var stmt: OpaquePointer?
        var columns: Set<String> = []
        if sqlite3_prepare_v2(db, "PRAGMA table_info(idiom_dict);", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let name = readColumn(stmt, 1)
                if !name.isEmpty { columns.insert(name) }
            }
        }
        sqlite3_finalize(stmt)
        hasExtendedColumns = columns.contains("pinyin")

        var tableStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='char_dict';", -1, &tableStmt, nil) == SQLITE_OK {
            hasCharDictTable = sqlite3_step(tableStmt) == SQLITE_ROW
        }
        sqlite3_finalize(tableStmt)
    }

    func supportsCharDict() -> Bool {
        return hasCharDictTable
    }

    private func selectColumns(
        idiomExpr: String,
        phoneticExpr: String,
        definitionExpr: String,
        sourceExpr: String,
        exampleExpr: String,
        synonymsExpr: String,
        antonymsExpr: String,
        alias: String
    ) -> String {
        var select = """
            \(idiomExpr) AS idiom,
            \(phoneticExpr) AS phonetic,
            \(definitionExpr) AS definition,
            \(sourceExpr) AS source,
            \(exampleExpr) AS example,
            \(synonymsExpr) AS synonyms,
            \(antonymsExpr) AS antonyms
        """
        if hasExtendedColumns {
            select += """
            , \(alias).pinyin AS pinyin,
              \(alias).source_text AS source_text,
              \(alias).source_note AS source_note,
              \(alias).source_ref AS source_ref,
              \(alias).story AS story,
              \(alias).citations AS citations,
              \(alias).usage_semantic AS usage_semantic,
              \(alias).usage_category AS usage_category,
              \(alias).usage_example AS usage_example,
              \(alias).discrimination_form AS discrimination_form,
              \(alias).discrimination_same AS discrimination_same,
              \(alias).discrimination_diff AS discrimination_diff,
              \(alias).discrimination_example AS discrimination_example,
              \(alias).reference_terms AS reference_terms,
              \(alias).entry_type AS entry_type
            """
        }
        return select
    }

    private func matchesBopomofo(_ syllable: String, _ bopomofo: String) -> Bool {
        let query = parseBopomofoQuery(bopomofo)
        if query.base.isEmpty { return false }
        let parsed = parseBopomofoSyllable(syllable)
        if parsed.base.isEmpty { return false }
        if parsed.base != query.base { return false }
        if let tone = query.tone {
            // Tone sandhi handling for common cases
            if query.base == "ㄅㄨ" && tone == "ˊ" {
                return parsed.tone == "ˊ" || parsed.tone == "ˋ"
            }
            if query.base == "ㄧ" && (tone == "ˊ" || tone == "ˋ") {
                // Allow tone-marked "一" to match base first tone (often unmarked)
                return parsed.tone == nil || parsed.tone == "ˉ"
            }
            if tone == "ˉ" {
                // First tone is often implicit (no mark)
                return parsed.tone == nil || parsed.tone == "ˉ"
            }
            return parsed.tone == tone
        }
        return true
    }

    private func parseBopomofoQuery(_ bopomofo: String) -> (base: String, tone: Character?) {
        var text = bopomofo.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return ("", nil) }
        if let last = text.last, isToneMark(last) {
            text.removeLast()
            return (text, last)
        }
        return (text, nil)
    }

    private func parseBopomofoSyllable(_ syllable: String) -> (base: String, tone: Character?) {
        var text = syllable.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("˙") {
            text.removeFirst()
            return (text, "˙")
        }
        if let last = text.last, isToneMark(last) {
            text.removeLast()
            return (text, last)
        }
        return (text, nil)
    }

    private func isToneMark(_ char: Character) -> Bool {
        return char == "ˉ" || char == "ˊ" || char == "ˇ" || char == "ˋ" || char == "˙"
    }

    private func matchesBopomofoIgnoringTone(_ syllable: String, _ bopomofo: String) -> Bool {
        let base = parseBopomofoSyllable(syllable).base
        let queryBase = parseBopomofoQuery(bopomofo).base
        if base.isEmpty || queryBase.isEmpty { return false }
        return base == queryBase
    }

    private func isCJKPrefixQuery(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count > 4 { return false }
        for scalar in trimmed.unicodeScalars {
            if !isCJKScalar(scalar) { return false }
        }
        return true
    }
    
    private func isCJKScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    // MARK: - Schema Normalization (handles MOE export with leading numeric id)
    private func normalizedIdiomExpr(alias: String) -> String {
        "CASE WHEN \(alias).idiom GLOB '[0-9]*' THEN \(alias).phonetic ELSE \(alias).idiom END"
    }
    private func normalizedPhoneticExpr(alias: String) -> String {
        "CASE WHEN \(alias).idiom GLOB '[0-9]*' THEN \(alias).definition ELSE \(alias).phonetic END"
    }
    private func normalizedDefinitionExpr(alias: String) -> String {
        "CASE WHEN \(alias).idiom GLOB '[0-9]*' THEN \(alias).source ELSE \(alias).definition END"
    }
    private func normalizedSourceExpr(alias: String) -> String {
        "CASE WHEN \(alias).idiom GLOB '[0-9]*' THEN \(alias).example ELSE \(alias).source END"
    }
    private func normalizedExampleExpr(alias: String) -> String {
        "CASE WHEN \(alias).idiom GLOB '[0-9]*' THEN \(alias).synonyms ELSE \(alias).example END"
    }
    private func normalizedSynonymsExpr(alias: String) -> String {
        "CASE WHEN \(alias).idiom GLOB '[0-9]*' THEN \(alias).antonyms ELSE \(alias).synonyms END"
    }
    private func normalizedAntonymsExpr(alias: String) -> String {
        "CASE WHEN \(alias).idiom GLOB '[0-9]*' THEN '' ELSE \(alias).antonyms END"
    }
}
