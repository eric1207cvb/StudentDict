import AVFoundation

// MARK: - [Version Update] 2.1: Advanced TTS
class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()
    
    // 用來記錄現在是否正在講話 (雖然 AVSpeechSynthesizer 有 isSpeaking，但我們需要更精確的控制)
    var isSpeaking: Bool {
        return synthesizer.isSpeaking
    }
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func speak(_ text: String) {
        // 如果正在講話，就強制停止 (達成「再按一次即停止」的效果)
        if synthesizer.isSpeaking {
            stop()
            // 如果原本是在唸同一段文字，使用者可能是想「暫停/停止」，所以這裡可以直接 return
            // 但為了簡單起見，我們策略是：先停，然後馬上唸新的 (或是重新唸這段)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-TW")
        
        // 解釋通常比較長，語速可以稍微調快一點點，或者保持 0.45
        utterance.rate = 0.45
        utterance.pitchMultiplier = 1.0
        
        synthesizer.speak(utterance)
    }
    
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
