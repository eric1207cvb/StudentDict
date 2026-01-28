import Foundation

struct BopomofoData {
    static let initials = ["ㄅ", "ㄆ", "ㄇ", "ㄈ", "ㄉ", "ㄊ", "ㄋ", "ㄌ", "ㄍ", "ㄎ", "ㄏ", "ㄐ", "ㄑ", "ㄒ", "ㄓ", "ㄔ", "ㄕ", "ㄖ", "ㄗ", "ㄘ", "ㄙ"]
    static let medials = ["ㄧ", "ㄨ", "ㄩ"]
    static let finals = ["ㄚ", "ㄛ", "ㄜ", "ㄝ", "ㄞ", "ㄟ", "ㄠ", "ㄡ", "ㄢ", "ㄣ", "ㄤ", "ㄥ", "ㄦ"]
    static let tones = ["ˉ", "ˊ", "ˇ", "ˋ", "˙"]
    static var all: Set<String> { return Set(initials + medials + finals + tones) }
    static func isBopomofo(_ char: Character) -> Bool { return all.contains(String(char)) }
}

class BopomofoSplitter {
    static func split(phonetic: String, count: Int) -> [String] {
        let normalized = normalizeForSyllables(phonetic)
        let parts = normalized.components(separatedBy: " ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count == count { return parts }
        if parts.count > count { return Array(parts.prefix(count)) }
        var safeParts = parts
        while safeParts.count < count { safeParts.append("") }
        return safeParts
    }

    static func normalizeForSyllables(_ phonetic: String) -> String {
        var text = phonetic.replacingOccurrences(of: "\u{3000}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop leading variant markers like （一） or （變）
        while text.hasPrefix("（"), let end = text.firstIndex(of: "）") {
            text = String(text[text.index(after: end)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Keep only the first reading before the next marker (if any)
        if let markerIndex = text.firstIndex(of: "（") {
            text = String(text[..<markerIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
