import Foundation
import SQLite3

// MARK: - 1. Data Model
struct DictItem: Identifiable, Hashable {
    let id = UUID()
    let word: String
    let phonetic: String
    let definition: String
    let radical: String
    let strokeCount: Int
}

// MARK: - 2. Database Manager
class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?
    
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
        }
    }
    
    private func createTables() {
        guard let db = db else { return }
        // favorites 表格：使用 word 當主鍵。
        // 注意：SQLite 預設有隱藏的 rowid 欄位，可用來判斷加入順序 (越小越早加入)
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS favorites (word TEXT PRIMARY KEY);", nil, nil, nil)
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS history (word TEXT PRIMARY KEY, timestamp REAL);", nil, nil, nil)
    }
    
    // MARK: - 🔍 主搜尋 (字典邏輯：僅限字首匹配 + 權重排序)
    func search(keyword: String) -> [DictItem] {
        var result: [DictItem] = []
        guard let db = db else { return [] }
        
        let querySQL = """
            SELECT word, phonetic, definition, radical, stroke_count 
            FROM dict_mini 
            WHERE word LIKE ? OR phonetic LIKE ? 
            ORDER BY 
              CASE 
                WHEN word = ? THEN 0 
                ELSE 1 
              END ASC,
              length(word) ASC, 
              stroke_count ASC 
            LIMIT 100;
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
            let nsKeyword = keyword as NSString
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            
            // 1. 字首搜尋 (如輸入 "生" -> 找 "生%")
            let prefixKeyword = "\(keyword)%"
            sqlite3_bind_text(stmt, 1, (prefixKeyword as NSString).utf8String, -1, SQLITE_TRANSIENT)
            
            // 2. 注音開頭搜尋 (如輸入 "ㄕ" -> 找 "ㄕ%")
            sqlite3_bind_text(stmt, 2, (prefixKeyword as NSString).utf8String, -1, SQLITE_TRANSIENT)
            
            // 3. 排序用：完全匹配 (如 "生" 本人)
            sqlite3_bind_text(stmt, 3, nsKeyword.utf8String, -1, SQLITE_TRANSIENT)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(parseRow(stmt: stmt))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    // MARK: - ⌨️ 鍵盤候選字搜尋
    func searchByPhonetic(_ bopomofo: String) -> [String] {
        var rawResults: [String] = []
        guard let db = db else { return [] }
        
        let querySQL = """
            SELECT word 
            FROM dict_mini 
            WHERE phonetic LIKE ? AND length(word) = 1
            ORDER BY length(phonetic) ASC, stroke_count ASC 
            LIMIT 300;
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
            let searchString = "\(bopomofo)%"
            sqlite3_bind_text(stmt, 1, (searchString as NSString).utf8String, -1, nil)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let wordPtr = sqlite3_column_text(stmt, 0) {
                    let word = String(cString: wordPtr)
                    rawResults.append(word)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return NSOrderedSet(array: rawResults).array as? [String] ?? []
    }
    
    // MARK: - History (歷史紀錄)
    func addToHistory(word: String) {
        guard let db = db else { return }
        let timestamp = Date().timeIntervalSince1970
        let insertSQL = "INSERT OR REPLACE INTO history (word, timestamp) VALUES (?, ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, nil)
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
        let sql = "SELECT d.word, d.phonetic, d.definition, d.radical, d.stroke_count FROM history h INNER JOIN dict_mini d ON h.word = d.word ORDER BY h.timestamp DESC"
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
    func toggleFavorite(word: String) -> Bool {
        guard let db = db else {
            print("❌ DB Error: 資料庫未連接")
            return false
        }
        
        if isFavorite(word: word) {
            // --- 情況 A：已收藏，執行刪除 ---
            print("🗑️ 正在從收藏移除: \(word)")
            let deleteSQL = "DELETE FROM favorites WHERE word = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, nil)
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
            print("❤️ 準備加入收藏: \(word)")
            
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
                sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, nil)
                if sqlite3_step(stmt) == SQLITE_DONE {
                    print("✅ 加入收藏成功: \(word)")
                } else {
                    print("❌ 加入失敗 (可能是 SQL 錯誤或約束衝突): \(word)")
                    if let errorPointer = sqlite3_errmsg(db) {
                        print("   SQLite Error: \(String(cString: errorPointer))")
                    }
                }
            }
            sqlite3_finalize(stmt)
            
            return true // 回傳 true 代表現在「已收藏」
        }
    }
    
    func isFavorite(word: String) -> Bool {
        guard let db = db else { return false }
        let sql = "SELECT count(*) FROM favorites WHERE word = ?;"
        var stmt: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, nil)
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
        
        // 聯表查詢：從 favorites 取得單字，再從 dict_mini 取得詳細解釋
        // ORDER BY f.rowid DESC 確保最新加入的顯示在最上面
        let sql = """
            SELECT d.word, d.phonetic, d.definition, d.radical, d.stroke_count 
            FROM favorites f 
            INNER JOIN dict_mini d ON f.word = d.word 
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
        let word = String(cString: sqlite3_column_text(stmt, 0))
        let phonetic = String(cString: sqlite3_column_text(stmt, 1))
        let definition = String(cString: sqlite3_column_text(stmt, 2))
        var radical = ""
        if let radPtr = sqlite3_column_text(stmt, 3) { radical = String(cString: radPtr) }
        let strokeCount = Int(sqlite3_column_int(stmt, 4))
        return DictItem(word: word, phonetic: phonetic, definition: definition, radical: radical, strokeCount: strokeCount)
    }
}
