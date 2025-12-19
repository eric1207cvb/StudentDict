import Foundation
import Speech
import Combine
import AVFoundation

// MARK: - [Fix] Robust Speech Manager
// 修復重點：加強資源釋放邏輯，防止第二次錄音時 Audio Engine 卡死
class SpeechInputManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // 發布給 UI 的狀態
    @Published var transcribedText: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?
    
    // 用來偵測停頓的計時器
    private var silenceTimer: Timer?
    
    override init() {
        super.init()
        speechRecognizer?.delegate = self
    }
    
    // 開始/停止錄音的開關
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        // 0. 強制清理舊狀態 (防禦性程式設計)
        cleanupSpeechSession()
        
        // 1. 檢查權限
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async { self.errorMessage = "請至設定開啟語音權限" }
                return
            }
        }
        
        // 2. 設定 Audio Session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // 設定為錄音模式，並縮小其他聲音 (duckOthers)
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio Session Error: \(error)")
            return
        }
        
        // 3. 建立辨識請求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        // 不需要等到講完一句才回傳，要即時回傳
        recognitionRequest.shouldReportPartialResults = true
        
        // 4. 設定輸入源 (麥克風)
        let inputNode = audioEngine.inputNode
        
        // 5. 開始辨識任務
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                // 更新文字到 UI
                DispatchQueue.main.async {
                    self.transcribedText = result.bestTranscription.formattedString
                }
                isFinal = result.isFinal
                
                // 🔥 收到新文字後，重置停頓計時器
                self.resetSilenceTimer()
            }
            
            if error != nil || isFinal {
                // 發生錯誤或已經結束時，執行清理
                self.stopRecording()
            }
        }
        
        // 6. 安裝 Tap (監聽麥克風數據)
        // ⚠️ 關鍵修正：先移除可能殘留的 Tap，再安裝新的
        inputNode.removeTap(onBus: 0)
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        // 7. 啟動引擎
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
        // 停止錄音時，執行完整清理
        cleanupSpeechSession()
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
    
    // MARK: - Helper: 深度清理資源
    private func cleanupSpeechSession() {
        // 1. 停止 Audio Engine
        if audioEngine.isRunning {
            audioEngine.stop()
            // ⚠️ 關鍵：一定要移除 Tap，否則下次 start 會崩潰
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // 2. 結束請求
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // 3. 取消任務
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // 4. 停止計時器
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // 5. 釋放 Audio Session (讓喇叭可以恢復播放聲音)
        // 注意：這裡使用 try? 忽略錯誤，避免影響流程
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    // 重置停頓計時器
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        // 設定 1.5 秒後自動停止
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                // 時間到，自動停止
                self?.stopRecording()
            }
        }
    }
}
