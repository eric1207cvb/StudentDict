import Foundation
import SQLite3

// MARK: - 1. Data Model (資料模型定義在這裡)
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
    
    private init() {
        openDatabase()
        createTables()
    }
    
    private func openDatabase() {
        guard let dbPath = Bundle.main.path(forResource: "dictionary", ofType: "sqlite") else { return }
        sqlite3_open(dbPath, &db)
    }
    
    private func createTables() {
        guard let db = db else { return }
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS favorites (word TEXT PRIMARY KEY);", nil, nil, nil)
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS history (word TEXT PRIMARY KEY, timestamp REAL);", nil, nil, nil)
    }
    
    func search(keyword: String) -> [DictItem] {
        var result: [DictItem] = []
        guard let db = db else { return [] }
        let querySQL = "SELECT word, phonetic, definition, radical, stroke_count FROM dict_mini WHERE word LIKE ? OR phonetic LIKE ? LIMIT 50;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
            let searchString = "%\(keyword)%"
            sqlite3_bind_text(stmt, 1, (searchString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (searchString as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(parseRow(stmt: stmt))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
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
    
    func toggleFavorite(word: String) -> Bool {
        guard let db = db else { return false }
        if isFavorite(word: word) {
            sqlite3_exec(db, "DELETE FROM favorites WHERE word = '\(word)';", nil, nil, nil)
            return false
        } else {
            sqlite3_exec(db, "INSERT INTO favorites (word) VALUES ('\(word)');", nil, nil, nil)
            return true
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
