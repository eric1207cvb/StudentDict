import Foundation
import Speech
import Combine
import AVFoundation

// MARK: - [Final Fix] Speech Input Manager with Engine Reset
class SpeechInputManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    @Published var transcribedText: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?
    
    private var silenceTimer: Timer?
    
    override init() {
        super.init()
        speechRecognizer?.delegate = self
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        // 1. 先把發音停掉，避免衝突
        SpeechManager.shared.stop()
        
        // 2. 清理舊的錄音狀態
        cleanupSpeechSession()
        
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async { self.errorMessage = "請至設定開啟語音權限" }
                return
            }
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // 設定為錄音模式
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio Session Error: \(error)")
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            var isFinal = false
            
            if let result = result {
                DispatchQueue.main.async {
                    self.transcribedText = result.bestTranscription.formattedString
                }
                isFinal = result.isFinal
                self.resetSilenceTimer()
            }
            
            if error != nil || isFinal {
                self.stopRecording()
            }
        }
        
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.transcribedText = ""
                self.isRecording = true
            }
        } catch {
            print("Audio Engine Start Error: \(error)")
        }
    }
    
    func stopRecording() {
        cleanupSpeechSession()
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
    
    private func cleanupSpeechSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            // [關鍵修復] 重置引擎，徹底釋放硬體資源
            audioEngine.reset()
        }
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // 釋放 Session，歸還控制權
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.stopRecording()
            }
        }
    }
}
