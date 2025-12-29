import AVFoundation
import UIKit
import Combine

// [Fix] 加入 @MainActor，確保 UI 更新都在主執行緒
@MainActor
class SpeechManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()
    
    // 用來標記正在說話，可讓 UI 顯示對應圖示
    @Published var isSpeaking = false
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    /// 朗讀文字
    /// - Parameter text: 要朗讀的文字
    /// - Parameter rate: 語速 (0.0 ~ 1.0)，預設 0.45
    func speak(_ text: String, rate: Float = 0.45) {
        // 1. 如果正在講話，先停止
        stop()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // [關鍵修正]
            // 步驟 A: 先解除目前的 Session (這會釋放麥克風鎖定)
            try? audioSession.setActive(false)
            
            // 步驟 B: 設定為 "純播放模式" (.playback)
            // 這裡不需要 overrideOutputAudioPort(.speaker)，因為 .playback 預設就是喇叭
            // 如果加了 override... 會導致 Error -50 錯誤
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            
            // 步驟 C: 啟用 Session
            try audioSession.setActive(true)
        } catch {
            print("⚠️ 發音前置設定失敗: \(error.localizedDescription)")
        }
        
        // 2. 建立發聲物件
        let utterance = AVSpeechUtterance(string: text)
        
        // 3. 尋找最佳台灣語音
        if let voice = findBestChineseVoice() {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-TW")
        }
        
        // 4. 設定參數
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0 // 確保最大音量
        
        // 5. 開始朗讀
        synthesizer.speak(utterance)
    }
    
    /// 停止朗讀
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    // MARK: - 尋找最佳的台灣語音
    private func findBestChineseVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "zh-TW" }
        // 優先順序: Premium -> Enhanced -> Default
        if let premium = voices.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) { return enhanced }
        return voices.first
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
