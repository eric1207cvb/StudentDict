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
    
    private func openDatabase() {
        guard let dbPath = Bundle.main.path(forResource: "dictionary", ofType: "sqlite") else {
            print("❌ Error: Dictionary database file not found in bundle.")
            return
        }
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("❌ Error: Unable to open database.")
        }
    }
    
    private func createTables() {
        guard let db = db else { return }
        // favorites 表格：使用 word 當主鍵。
        // 注意：SQLite 預設有隱藏的 rowid 欄位，可用來判斷加入順序 (越小越早加入)
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS favorites (word TEXT PRIMARY KEY);", nil, nil, nil)
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS history (word TEXT PRIMARY KEY, timestamp REAL);", nil, nil, nil)
    }
    
    // MARK: - 🔍 主搜尋 (字典邏輯：僅限字首匹配)
        func search(keyword: String) -> [DictItem] {
            var result: [DictItem] = []
            guard let db = db else { return [] }
            
            // SQL 邏輯修正：
            // 1. WHERE word LIKE ? -> 只允許 '關鍵字%' (開頭匹配)，移除包含匹配
            // 2. ORDER BY -> 本字最優先 (0)，其餘為開頭詞 (1)，接著按長度與筆畫排序
            
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
                
                // 綁定參數 (關鍵修改：只用後綴 %)
                
                // 1. 字首搜尋 (如輸入 "生" -> 找 "生%")
                // 這樣 "學生" (生在後面) 就不會出現了
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
        guard let db = db else { return false }
        
        if isFavorite(word: word) {
            // --- 情況 A：已收藏，執行刪除 ---
            let deleteSQL = "DELETE FROM favorites WHERE word = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            return false // 回傳 false 代表現在「未收藏」
            
        } else {
            // --- 情況 B：未收藏，準備加入 ---
            
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
            
            // 2. 如果達到上限，刪除「最舊」的一筆
            // 這裡使用 SQLite 的 rowid 來判斷，rowid 最小的代表最早插入
            if currentCount >= maxFavoritesCount {
                let deleteOldestSQL = "DELETE FROM favorites WHERE rowid = (SELECT min(rowid) FROM favorites);"
                sqlite3_exec(db, deleteOldestSQL, nil, nil, nil)
            }
            
            // 3. 插入新收藏
            let insertSQL = "INSERT INTO favorites (word) VALUES (?);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
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
    
    // [Added] 取得所有收藏列表 (UI 需要此函式)
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
