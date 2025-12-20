import AVFoundation
import UIKit
import Combine  // [Fix] 必須加入這個框架，才能使用 @Published 和 ObservableObject

// [Fix] 加入 @MainActor，確保 UI 更新都在主執行緒，並解決 Sendable 警告
@MainActor
class SpeechManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()
    
    // 用來標記正在說話，可讓 UI 顯示對應圖示
    @Published var isSpeaking = false
    
    override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
    }
    
    /// 設定音訊工作階段 (確保聲音夠大，且不會被靜音鍵切掉)
    private func setupAudioSession() {
        do {
            // .playback 模式可確保在靜音模式下也能發聲
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ AudioSession 設定失敗: \(error)")
        }
    }
    
    /// 朗讀文字
    /// - Parameter text: 要朗讀的文字
    /// - Parameter rate: 語速 (0.0 ~ 1.0)，預設 0.45 (適合教學的稍慢速度)
    func speak(_ text: String, rate: Float = 0.45) {
        // 1. 如果正在講話，先停止
        stop()
        
        // 2. 建立發聲物件
        let utterance = AVSpeechUtterance(string: text)
        
        // 3. [關鍵優化] 強制尋找「台灣 (zh-TW)」的高品質語音
        if let voice = findBestChineseVoice() {
            utterance.voice = voice
        } else {
            // 回退方案
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-TW")
        }
        
        // 4. 設定語速與音調
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0 // 正常音高
        utterance.volume = 1.0
        
        // 5. 開始朗讀
        synthesizer.speak(utterance)
    }
    
    /// 停止朗讀
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    // MARK: - [關鍵優化] 尋找最佳的台灣語音
    private func findBestChineseVoice() -> AVSpeechSynthesisVoice? {
        // 取得所有支援 zh-TW 的語音
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "zh-TW" }
        
        // 優先順序 1: Premium (iOS 16+ 高品質 Siri 語音，最自然)
        if let premiumVoice = voices.first(where: { $0.quality == .premium }) {
            return premiumVoice
        }
        
        // 優先順序 2: Enhanced (增強版語音)
        if let enhancedVoice = voices.first(where: { $0.quality == .enhanced }) {
            return enhancedVoice
        }
        
        // 優先順序 3: Default (標準語音，通常是 Mei-Jia)
        return voices.first
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    // 因為類別已經標記 @MainActor，這裡不需要再包 DispatchQueue.main.async
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
