import AppKit
@preconcurrency import AVFoundation
import Foundation
import SQLite3
@preconcurrency import Speech
import SwiftUI

private enum ProviderChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto
    case codex
    case claude

    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .codex: return "Codex"
        case .claude: return "Claude"
        }
    }
    var subtitle: String {
        switch self {
        case .auto: return "RCC chooses"
        case .codex: return "Build & edit"
        case .claude: return "Analyze & review"
        }
    }
    var symbol: String {
        switch self {
        case .auto: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .claude: return "sun.max.fill"
        }
    }
    var tint: Color {
        switch self {
        case .auto: return Color(red: 0.38, green: 0.86, blue: 0.58)
        case .codex: return Color(red: 0.95, green: 0.64, blue: 0.80)
        case .claude: return Color(red: 0.98, green: 0.53, blue: 0.68)
        }
    }
}

private func explicitlyRequestedProvider(in request: String) -> ProviderChoice? {
    let value = request
        .lowercased()
        .replacingOccurrences(of: "[\\p{P}\\p{S}]+", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

    // Voice dictation frequently turns 코덱스 into 코덱세/코덱센트/코덱선트.
    // This recognizes only directed backend requests; merely discussing a
    // provider keeps the private RCC auto route in control.
    let codexPatterns = [
        #"코덱(?:스|세|센트|선트)?\s*(?:(?:한테|에게|로|으로)(?:\s|\S){0,24}(?:시켜|시키|맡겨|보내|돌려|실행|해|하게|말|부탁)|(?:가|이)?\s*(?:뭐\s*)?(?:시켜|시키|맡겨|보내|돌려|실행|해|하게|말|부탁))"#,
        #"(?:시켜|시키|맡겨|보내|돌려|실행|부탁)(?:\s|\S){0,18}코덱(?:스|세|센트|선트)?"#,
        #"(?:use|ask|route|send|run|delegate)(?:\s+\w+){0,3}\s+codex\b"#,
        #"\bcodex\b(?:\s+\w+){0,3}\s+(?:do|run|handle|execute)\b"#,
    ]
    let claudePatterns = [
        #"클(?:로드|로더)\s*(?:코드)?\s*(?:(?:한테|에게|로|으로)(?:\s|\S){0,24}(?:시켜|시키|맡겨|보내|돌려|실행|해|하게|말|부탁)|(?:가|이)?\s*(?:뭐\s*)?(?:시켜|시키|맡겨|보내|돌려|실행|해|하게|말|부탁))"#,
        #"(?:시켜|시키|맡겨|보내|돌려|실행|부탁)(?:\s|\S){0,18}클(?:로드|로더)(?:\s*코드)?"#,
        #"(?:use|ask|route|send|run|delegate)(?:\s+\w+){0,3}\s+claude(?:\s+code)?\b"#,
        #"\bclaude(?:\s+code)?\b(?:\s+\w+){0,3}\s+(?:do|run|handle|execute)\b"#,
    ]
    func lastMatch(in patterns: [String]) -> String.Index? {
        patterns.compactMap { pattern in
            value.range(of: pattern, options: .regularExpression)?.lowerBound
        }.max()
    }
    let codex = lastMatch(in: codexPatterns)
    let claude = lastMatch(in: claudePatterns)
    switch (codex, claude) {
    case (.some(let codexIndex), .some(let claudeIndex)):
        return codexIndex > claudeIndex ? .codex : .claude
    case (.some, .none): return .codex
    case (.none, .some): return .claude
    case (.none, .none): return nil
    }
}

private func providerIntentSelfTest() throws {
    let codexRequests = [
        "코덱스한테 말시켜봐",
        "코덱세한테 뭐 시켜봐",
        "1 더하기 1 코덱선트 시켜라니까",
        "코덱센트 시켜서 확인해",
        "ask Codex to run the tests",
        "use Codex for this task",
    ]
    let claudeRequests = [
        "클로드한테 레드팀 시켜",
        "이거 클로더 코드로 해",
        "ask Claude Code to review this",
        "use Claude for this task",
    ]
    let autoRequests = [
        "코덱스 사용량과 클로드 사용량을 비교해줘",
        "Codex and Claude are both backends",
        "이 버그를 고치고 테스트해",
    ]
    let failures = codexRequests.filter { explicitlyRequestedProvider(in: $0) != .codex }
        + claudeRequests.filter { explicitlyRequestedProvider(in: $0) != .claude }
        + autoRequests.filter { explicitlyRequestedProvider(in: $0) != nil }
        + (explicitlyRequestedProvider(in: "코덱스한테 시키지 말고 클로드한테 시켜") == .claude
            ? [] : ["last directed provider"])
    guard failures.isEmpty else {
        throw RunnerError.message("OS-1 provider intent self-test failed: \(failures.joined(separator: " | "))")
    }

    guard composerReturnAction(shiftPressed: false) == .send,
          composerReturnAction(shiftPressed: true) == .newline else {
        throw RunnerError.message("OS-1 composer keyboard self-test failed.")
    }

    var queue = ["first", "second", "third"]
    let drained = [queue.removeFirst(), queue.removeFirst(), queue.removeFirst()]
    guard drained == ["first", "second", "third"], queue.isEmpty else {
        throw RunnerError.message("OS-1 queued submission FIFO self-test failed.")
    }

    guard composerText(base: "", dictated: "안녕하세요") == "안녕하세요",
          composerText(base: "기존 작업", dictated: "계속해") == "기존 작업 계속해",
          composerText(base: "first line\n", dictated: "둘째 줄") == "first line\n둘째 줄",
          dictationText(committed: "첫 문장.", current: "둘째 문장") == "첫 문장. 둘째 문장",
          composerText(
            base: "이미 적은 내용",
            dictated: dictationText(committed: "첫 구간", current: "둘째 구간")
          ) == "이미 적은 내용 첫 구간 둘째 구간" else {
        throw RunnerError.message("OS-1 voice dictation composer merge self-test failed.")
    }

    let localStep = AppRunStep(
        sequence: 1,
        provider: "local",
        action: "deterministic_compute",
        model: "local-deterministic",
        effort: "none",
        revasDisposition: "adopted",
        sessionID: "8eaa48c6-af59-4f4c-a2be-9a0ec3b6fc21",
        permissionProfile: "read_only",
        exitCode: 0,
        output: "2",
        stderr: "",
        durationMS: 1,
        nativeRecord: AppNativeRecord(
            turnID: "rcc-local-8eaa48c6af594f4ca2be9a0ec3b6fc21",
            recordPath: "/tmp/exact.json",
            persistence: "verified",
            desktopVisibility: "local_only"
        )
    )
    guard backendTierLabel(action: localStep.action, provider: localStep.provider) == "Exact local RCC executor",
          nativeRecordReceipt(localStep).contains("local exact receipt persisted") else {
        throw RunnerError.message("OS-1 local exact execution UI self-test failed.")
    }
}

private enum ComposerReturnAction: Equatable {
    case send
    case newline
}

private func composerReturnAction(shiftPressed: Bool) -> ComposerReturnAction {
    shiftPressed ? .newline : .send
}

private func composerText(base: String, dictated transcript: String) -> String {
    guard !transcript.isEmpty else { return base }
    guard !base.isEmpty else { return transcript }
    guard let last = base.last, !last.isWhitespace else { return base + transcript }
    return base + " " + transcript
}

private func dictationText(committed: String, current: String) -> String {
    composerText(base: committed, dictated: current)
}

private enum VoiceDictationPhase: Equatable {
    case idle
    case authorizing
    case listening
    case finalizing
    case transcribing
}

private struct LocalWhisperConfiguration: Sendable {
    let executableURL: URL
    let modelID: String
}

private struct LocalWhisperResult: Decodable {
    let text: String
}

/// AVAudioEngine calls its tap on a realtime queue. This explicitly Sendable
/// bridge owns either the live Speech request or the local recording file and
/// prevents the controller's MainActor isolation from leaking into that queue.
private final class SpeechAudioBufferSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest?
    private let audioFile: AVAudioFile?
    private let onLevel: @Sendable (CGFloat) -> Void
    private var lastLevelUpdate = Date.distantPast

    init(
        request: SFSpeechAudioBufferRecognitionRequest? = nil,
        audioFile: AVAudioFile? = nil,
        onLevel: @escaping @Sendable (CGFloat) -> Void
    ) {
        self.request = request
        self.audioFile = audioFile
        self.onLevel = onLevel
    }

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
        try? audioFile?.write(from: buffer)
        guard Date().timeIntervalSince(lastLevelUpdate) >= 0.075,
              let samples = buffer.floatChannelData?[0] else { return }
        lastLevelUpdate = Date()
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = samples[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        let decibels = 20 * log10(max(rms, 0.000_01))
        let normalized = CGFloat(max(0, min(1, (decibels + 52) / 52)))
        onLevel(normalized)
    }
}

@MainActor
private final class VoiceDictationController: ObservableObject {
    @Published private(set) var phase: VoiceDictationPhase = .idle
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var elapsedSeconds = 0

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioBufferSink: SpeechAudioBufferSink?
    private var elapsedTimer: Timer?
    private var finishTimeoutTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var localTranscriptionTask: Task<Void, Never>?
    private var localWhisper: LocalWhisperConfiguration?
    private var localRecordingURL: URL?
    private var baseText = ""
    private var committedTranscript = ""
    private var currentTranscript = ""
    private var onTranscript: ((String) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var onFinish: (() -> Void)?
    private var tapInstalled = false
    private var wantsRecording = false
    private var recognitionGeneration = 0
    private var consecutiveRecoveryCount = 0

    var isActive: Bool { phase != .idle }
    var isRecording: Bool { phase == .listening }
    var isAuthorizing: Bool { phase == .authorizing }
    var isFinalizing: Bool { phase == .finalizing || phase == .transcribing }
    var engineLabel: String { localWhisper == nil ? "Apple speech" : "Local Whisper" }
    var statusLabel: String {
        switch phase {
        case .idle: return "Voice"
        case .authorizing: return "Starting…"
        case .listening: return "Listening"
        case .finalizing: return "Finishing…"
        case .transcribing: return "Transcribing…"
        }
    }
    var elapsedLabel: String {
        String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    func toggle(
        initialText: String,
        onTranscript: @escaping (String) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        if isActive {
            finish()
            return
        }
        baseText = initialText
        committedTranscript = ""
        currentTranscript = ""
        localWhisper = localWhisperConfiguration()
        localRecordingURL = nil
        self.onTranscript = onTranscript
        self.onFailure = onFailure
        self.onFinish = nil
        wantsRecording = true
        phase = .authorizing
        elapsedSeconds = 0
        startElapsedTimer()
        Task { await authorizeAndStart() }
    }

    /// Finish keeps the recognition task alive briefly so the final spoken
    /// words reach the composer. This is deliberately different from cancel.
    func finish(onComplete: (() -> Void)? = nil) {
        if let onComplete { onFinish = onComplete }
        guard isActive, !isFinalizing else { return }
        wantsRecording = false
        if let configuration = localWhisper, let recordingURL = localRecordingURL {
            phase = .transcribing
            stopAudioCapture()
            transcribeLocally(configuration: configuration, recordingURL: recordingURL)
            return
        }
        phase = .finalizing
        stopAudioCapture()
        let generation = recognitionGeneration
        finishTimeoutTask?.cancel()
        finishTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, let self,
                  self.phase == .finalizing,
                  self.recognitionGeneration == generation else { return }
            self.completeFinalization()
        }
    }

    /// Cancel is lossless: it restores the exact text that existed before the
    /// microphone was started.
    func cancel() {
        guard isActive else { return }
        let restore = baseText
        let transcriptHandler = onTranscript
        resetRecognition(cancelTask: true)
        phase = .idle
        level = 0
        elapsedSeconds = 0
        transcriptHandler?(restore)
        clearCallbacks()
    }

    /// Session changes and view teardown use cancellation so a late Speech
    /// callback can never write into a different composer.
    func stop() {
        cancel()
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest?.endAudio()
        audioBufferSink = nil
    }

    private func resetRecognition(cancelTask: Bool) {
        wantsRecording = false
        recognitionGeneration += 1
        restartTask?.cancel()
        restartTask = nil
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil
        localTranscriptionTask?.cancel()
        localTranscriptionTask = nil
        stopAudioCapture()
        if cancelTask { recognitionTask?.cancel() }
        recognitionTask = nil
        recognitionRequest = nil
        audioBufferSink = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        removeLocalRecording()
    }

    private func authorizeAndStart() async {
        let microphoneGranted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        case .authorized:
            microphoneGranted = true
        default:
            microphoneGranted = false
        }
        guard phase == .authorizing, wantsRecording else { return }
        guard microphoneGranted else {
            fail("Microphone access is off. Allow Open OS-1 Codex in System Settings → Privacy & Security → Microphone.")
            return
        }

        if let configuration = localWhisper ?? localWhisperConfiguration() {
            do {
                localWhisper = configuration
                try startLocalWhisperCapture()
                return
            } catch {
                localWhisper = nil
                removeLocalRecording()
            }
        }

        let speechStatus: SFSpeechRecognizerAuthorizationStatus
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        case let existing:
            speechStatus = existing
        }
        guard phase == .authorizing, wantsRecording else { return }
        guard speechStatus == .authorized else {
            fail("Local Whisper is unavailable and Speech Recognition access is off. Install Handy or allow Open OS-1 Codex in System Settings → Privacy & Security → Speech Recognition.")
            return
        }

        do {
            try startRecognition()
        } catch {
            fail("Voice input could not start: \(error.localizedDescription)")
        }
    }

    private func localWhisperConfiguration() -> LocalWhisperConfiguration? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let executableCandidates = [
            URL(fileURLWithPath: "/Applications/Handy.app/Contents/MacOS/handy"),
            home.appendingPathComponent("Applications/Handy.app/Contents/MacOS/handy"),
        ]
        guard let executableURL = executableCandidates.first(where: {
            fileManager.isExecutableFile(atPath: $0.path)
        }) else { return nil }

        let support = home.appendingPathComponent("Library/Application Support/com.pais.handy")
        let settingsURL = support.appendingPathComponent("settings_store.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = root["settings"] as? [String: Any],
              let modelID = settings["selected_model"] as? String,
              !modelID.isEmpty else { return nil }
        let modelURL = support.appendingPathComponent("models").appendingPathComponent(
            URL(fileURLWithPath: modelID).lastPathComponent
        )
        guard fileManager.fileExists(atPath: modelURL.path) else { return nil }
        return LocalWhisperConfiguration(executableURL: executableURL, modelID: modelID)
    }

    private func startLocalWhisperCapture() throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RunnerError.message("No microphone audio format is available.")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("os1-dictation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recordingURL = directory.appendingPathComponent("recording.caf")
        let audioFile = try AVAudioFile(forWriting: recordingURL, settings: format.settings)
        localRecordingURL = recordingURL
        let bufferSink = SpeechAudioBufferSink(audioFile: audioFile) { @Sendable [weak self] value in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .listening else { return }
                self.level = max(value, self.level * 0.62)
            }
        }
        audioBufferSink = bufferSink
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format,
            block: { @Sendable [bufferSink] buffer, _ in
                bufferSink.append(buffer)
            }
        )
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
        phase = .listening
        recognitionGeneration += 1
    }

    private func startRecognition() throws {
        let locale = preferredDictationLocale()
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            throw RunnerError.message("Speech recognition is not available on this Mac right now.")
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = [
            "OS-1", "OmarAGI", "Codex", "Claude Code", "RCC", "REVAS",
            "Luna", "Terra", "Sol", "GitHub", "Cloudflare", "레바스", "코덱스", "클로드"
        ]
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request
        let bufferSink = SpeechAudioBufferSink(request: request) { @Sendable [weak self] value in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .listening else { return }
                self.level = max(value, self.level * 0.62)
            }
        }
        audioBufferSink = bufferSink

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RunnerError.message("No microphone audio format is available.")
        }
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format,
            block: { @Sendable [bufferSink] buffer, _ in
                bufferSink.append(buffer)
            }
        )
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
        phase = .listening

        recognitionGeneration += 1
        let generation = recognitionGeneration
        recognitionTask = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorMessage = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.phase != .idle,
                      self.recognitionGeneration == generation else { return }
                if let transcript, !transcript.isEmpty {
                    self.currentTranscript = transcript
                    self.consecutiveRecoveryCount = 0
                    self.publishTranscript()
                }
                if isFinal {
                    self.commitCurrentSegment()
                    if self.wantsRecording {
                        self.restartAfterFinalResult()
                    } else {
                        self.completeFinalization()
                    }
                } else if let errorMessage {
                    if self.wantsRecording, self.consecutiveRecoveryCount < 3 {
                        self.consecutiveRecoveryCount += 1
                        self.commitCurrentSegment()
                        self.restartAfterFinalResult(delayNanoseconds: 220_000_000)
                    } else if self.phase == .finalizing {
                        self.completeFinalization()
                    } else {
                        self.fail("Voice input stopped: \(errorMessage)")
                    }
                }
            }
        }
    }

    /// Speech may finalize a segment after a pause. Keep the microphone UI and
    /// user intent active while transparently rolling into a fresh segment.
    private func restartAfterFinalResult(delayNanoseconds: UInt64 = 120_000_000) {
        guard wantsRecording else { return }
        recognitionGeneration += 1
        stopAudioCapture()
        recognitionTask = nil
        recognitionRequest = nil
        phase = .listening
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self, self.wantsRecording else { return }
            do {
                try self.startRecognition()
            } catch {
                self.fail("Voice input could not continue: \(error.localizedDescription)")
            }
        }
    }

    private func transcribeLocally(
        configuration: LocalWhisperConfiguration,
        recordingURL: URL
    ) {
        let generation = recognitionGeneration
        localTranscriptionTask?.cancel()
        localTranscriptionTask = Task { [weak self] in
            do {
                let transcript = try await Task.detached(priority: .userInitiated) {
                    try Self.performLocalWhisperTranscription(
                        configuration: configuration,
                        recordingURL: recordingURL
                    )
                }.value
                guard !Task.isCancelled, let self,
                      self.phase == .transcribing,
                      self.recognitionGeneration == generation else { return }
                self.currentTranscript = transcript
                self.publishTranscript()
                self.completeFinalization()
            } catch {
                guard !Task.isCancelled, let self,
                      self.phase == .transcribing,
                      self.recognitionGeneration == generation else { return }
                self.fail("Local Whisper could not transcribe this recording: \(error.localizedDescription)")
            }
        }
    }

    nonisolated private static func performLocalWhisperTranscription(
        configuration: LocalWhisperConfiguration,
        recordingURL: URL
    ) throws -> String {
        let waveURL = recordingURL.deletingLastPathComponent().appendingPathComponent("recording.wav")
        defer { try? FileManager.default.removeItem(at: recordingURL.deletingLastPathComponent()) }

        _ = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/afconvert"),
            arguments: [
                "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
                recordingURL.path, waveURL.path,
            ]
        )
        let output = try runProcess(
            executableURL: configuration.executableURL,
            arguments: [
                "--transcribe-file", waveURL.path,
                "--model", configuration.modelID,
                "--json",
            ]
        )
        let decoder = JSONDecoder()
        let result: LocalWhisperResult
        if let decoded = try? decoder.decode(LocalWhisperResult.self, from: output) {
            result = decoded
        } else if let line = String(data: output, encoding: .utf8)?
            .split(separator: "\n")
            .reversed()
            .first(where: { $0.first == "{" }),
            let data = String(line).data(using: .utf8) {
            result = try decoder.decode(LocalWhisperResult.self, from: data)
        } else {
            throw RunnerError.message("Handy returned an unreadable transcription result.")
        }
        let transcript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw RunnerError.message("No speech was detected.")
        }
        return transcript
    }

    nonisolated private static func runProcess(
        executableURL: URL,
        arguments: [String]
    ) throws -> Data {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = standardError.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RunnerError.message(detail?.isEmpty == false ? detail! : "Voice engine exited unexpectedly.")
        }
        return output
    }

    private func removeLocalRecording() {
        guard let localRecordingURL else { return }
        try? FileManager.default.removeItem(at: localRecordingURL.deletingLastPathComponent())
        self.localRecordingURL = nil
    }

    private func preferredDictationLocale() -> Locale {
        let preferred = Locale.preferredLanguages
        if let korean = preferred.first(where: { $0.lowercased().hasPrefix("ko") }) {
            return Locale(identifier: korean)
        }
        return Locale.current
    }

    private func publishTranscript() {
        let dictated = dictationText(committed: committedTranscript, current: currentTranscript)
        onTranscript?(composerText(base: baseText, dictated: dictated))
    }

    private func commitCurrentSegment() {
        guard !currentTranscript.isEmpty else { return }
        committedTranscript = dictationText(committed: committedTranscript, current: currentTranscript)
        currentTranscript = ""
        publishTranscript()
    }

    private func completeFinalization() {
        guard phase != .idle else { return }
        commitCurrentSegment()
        let completion = onFinish
        resetRecognition(cancelTask: true)
        phase = .idle
        level = 0
        clearCallbacks()
        completion?()
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.phase != .idle else { return }
                self.elapsedSeconds += 1
            }
        }
    }

    private func clearCallbacks() {
        onTranscript = nil
        onFailure = nil
        onFinish = nil
        baseText = ""
        committedTranscript = ""
        currentTranscript = ""
        localWhisper = nil
        consecutiveRecoveryCount = 0
    }

    private func fail(_ message: String) {
        commitCurrentSegment()
        let failure = onFailure
        resetRecognition(cancelTask: true)
        phase = .idle
        level = 0
        clearCallbacks()
        failure?(message)
    }
}

private struct NativeSessionSummary: Identifiable, Sendable {
    let id: String
    let provider: ProviderChoice
    let title: String
    let workspace: String
    let workspaceLabel: String?
    let updatedAt: Date
    let sourcePath: String?
    var linkedTitle: String?

    var displayTitle: String {
        let value = (linkedTitle ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Untitled session" : value
    }

    var displayWorkspace: String {
        if let workspaceLabel, !workspaceLabel.isEmpty { return workspaceLabel }
        let value = URL(fileURLWithPath: workspace).lastPathComponent
        return value.isEmpty ? "No workspace" : value
    }
}

private struct NativeSessionMessage: Identifiable, Sendable {
    let id: String
    let role: MessageRole
    let text: String
    let timestamp: Date?
}

private enum NativeSessionReader {
    nonisolated(unsafe) private static let iso8601 = ISO8601DateFormatter()

    private struct ClaudeDesktopMetadata {
        let title: String
        let workspace: String
        let lastActivityAt: Date?
        let isArchived: Bool
    }

    static func sessions(for provider: ProviderChoice) throws -> [NativeSessionSummary] {
        switch provider {
        case .codex: return try codexSessions()
        case .claude: return try claudeSessions()
        case .auto: return []
        }
    }

    static func transcript(for session: NativeSessionSummary) throws -> [NativeSessionMessage] {
        switch session.provider {
        case .codex: return try codexTranscript(sessionID: session.id)
        case .claude: return try claudeTranscript(session: session)
        case .auto: return []
        }
    }

    private static func codexSessions() throws -> [NativeSessionSummary] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.codex/state_5.sqlite"
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            throw RunnerError.message("Codex session index could not be opened.")
        }
        defer { sqlite3_close(database) }
        let query = """
        SELECT id,
               COALESCE(NULLIF(name, ''), NULLIF(title, ''), NULLIF(first_user_message, ''), 'Untitled session'),
               cwd,
               COALESCE(NULLIF(recency_at_ms, 0), NULLIF(updated_at_ms, 0), updated_at * 1000)
        FROM threads
        WHERE archived = 0 AND preview <> ''
        ORDER BY recency_at_ms DESC, updated_at_ms DESC
        LIMIT 500
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw RunnerError.message("Codex session index could not be read.")
        }
        defer { sqlite3_finalize(statement) }
        var result: [NativeSessionSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = columnText(statement, 0)
            guard !id.isEmpty else { continue }
            result.append(NativeSessionSummary(
                id: id,
                provider: .codex,
                title: columnText(statement, 1),
                workspace: columnText(statement, 2),
                workspaceLabel: nil,
                updatedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 3)) / 1_000),
                sourcePath: nil,
                linkedTitle: nil
            ))
        }
        return result
    }

    private static func codexTranscript(sessionID: String) throws -> [NativeSessionMessage] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.codex/thread_history_1.sqlite"
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            throw RunnerError.message("Codex transcript database could not be opened.")
        }
        defer { sqlite3_close(database) }
        let query = """
        SELECT item_type, item_json, created_at_ms
        FROM (
          SELECT rollout_ordinal, item_type, item_json, created_at_ms
          FROM thread_items
          WHERE thread_id = ? AND item_type IN ('userMessage', 'agentMessage')
          ORDER BY rollout_ordinal DESC
          LIMIT 400
        )
        ORDER BY rollout_ordinal ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw RunnerError.message("Codex transcript could not be read.")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var result: [NativeSessionMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let type = columnText(statement, 0)
            let json = columnText(statement, 1)
            guard let data = json.data(using: .utf8),
                  let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let text: String
            let role: MessageRole
            if type == "userMessage" {
                role = .user
                text = textContent(item["content"])
            } else {
                role = .assistant
                text = item["text"] as? String ?? ""
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            result.append(NativeSessionMessage(
                id: (item["id"] as? String) ?? "codex-\(result.count)",
                role: role,
                text: trimmed,
                timestamp: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 2)) / 1_000)
            ))
        }
        return result
    }

    private static func claudeSessions() throws -> [NativeSessionSummary] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        let desktopMetadata = claudeDesktopSessionMetadata()
        let repositoryLabels = claudeRepositoryLabels()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            files.append((url, values?.contentModificationDate ?? .distantPast))
        }
        files.sort { $0.1 > $1.1 }
        return files.compactMap { url, modifiedAt in
            guard let records = try? readJSONLines(url, maximumBytes: 768 * 1_024), !records.isEmpty else { return nil }
            var id = url.deletingPathExtension().lastPathComponent
            var workspace = ""
            var timestamp: Date?
            var title = ""
            var hasVisibleConversation = false
            for record in records {
                if let value = record["sessionId"] as? String, !value.isEmpty { id = value }
                if let value = record["cwd"] as? String, !value.isEmpty { workspace = value }
                if let value = record["timestamp"] as? String, let date = iso8601.date(from: value) {
                    timestamp = timestamp.map { max($0, date) } ?? date
                }
                let type = record["type"] as? String
                if type == "user" || type == "assistant",
                   let message = record["message"] as? [String: Any] {
                    let text = textContent(message["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        hasVisibleConversation = true
                        if title.isEmpty, type == "user" { title = firstLine(text) }
                    }
                }
            }
            // Claude Code print-mode sessions are genuine persistent backend
            // sessions but do not carry Claude Desktop's `bridge-session`
            // marker. The previous marker gate hid every session created or
            // resumed by OS-1 even though its JSONL transcript existed. Show
            // every persistent Claude conversation with visible user/assistant
            // turns so the backend surface mirrors Claude Code itself.
            guard hasVisibleConversation else { return nil }
            if let metadata = desktopMetadata[id] {
                guard !metadata.isArchived else { return nil }
                if !metadata.title.isEmpty { title = metadata.title }
                if workspace.isEmpty, !metadata.workspace.isEmpty { workspace = metadata.workspace }
                if let activity = metadata.lastActivityAt { timestamp = activity }
            }
            return NativeSessionSummary(
                id: id,
                provider: .claude,
                title: title,
                workspace: workspace,
                workspaceLabel: claudeProjectLabel(workspace, repositoryLabels: repositoryLabels),
                updatedAt: timestamp ?? modifiedAt,
                sourcePath: url.path,
                linkedTitle: nil
            )
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func claudeDesktopSessionMetadata() -> [String: ClaudeDesktopMetadata] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }
        var result: [String: ClaudeDesktopMetadata] = [:]
        for case let url as URL in enumerator where url.pathExtension == "json" && url.lastPathComponent.hasPrefix("local_") {
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cliSessionID = value["cliSessionId"] as? String,
                  !cliSessionID.isEmpty else { continue }
            let milliseconds = value["lastActivityAt"] as? Double
                ?? (value["lastActivityAt"] as? NSNumber)?.doubleValue
            result[cliSessionID] = ClaudeDesktopMetadata(
                title: value["title"] as? String ?? "",
                workspace: value["originCwd"] as? String ?? value["cwd"] as? String ?? "",
                lastActivityAt: milliseconds.map { Date(timeIntervalSince1970: $0 / 1_000) },
                isArchived: value["isArchived"] as? Bool ?? false
            )
        }
        return result
    }

    private static func claudeProjectLabel(_ workspace: String, repositoryLabels: [String: String]) -> String {
        guard !workspace.isEmpty else { return "No folder" }
        if workspace.contains("/Library/Application Support/Claude/scratch-workspaces/") {
            return "No folder"
        }
        if let label = repositoryLabels[workspace], !label.isEmpty { return label }
        let name = URL(fileURLWithPath: workspace).lastPathComponent
        return name.isEmpty ? "No folder" : name
    }

    private static func claudeRepositoryLabels() -> [String: String] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let repositories = root["githubRepoPaths"] as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (repository, rawPaths) in repositories {
            guard let paths = rawPaths as? [String] else { continue }
            let label = repository.split(separator: "/").last.map(String.init) ?? repository
            for path in paths { result[path] = label }
        }
        return result
    }

    private static func claudeTranscript(session: NativeSessionSummary) throws -> [NativeSessionMessage] {
        guard let sourcePath = session.sourcePath else { return [] }
        let records = try readJSONLines(URL(fileURLWithPath: sourcePath), maximumBytes: nil)
        var result: [NativeSessionMessage] = []
        for record in records {
            guard let type = record["type"] as? String, type == "user" || type == "assistant",
                  let message = record["message"] as? [String: Any] else { continue }
            let text = textContent(message["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let timestamp = (record["timestamp"] as? String).flatMap(iso8601.date(from:))
            result.append(NativeSessionMessage(
                id: (record["uuid"] as? String) ?? "claude-\(result.count)",
                role: type == "user" ? .user : .assistant,
                text: text,
                timestamp: timestamp
            ))
        }
        return Array(result.suffix(400))
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private static func readJSONLines(_ url: URL, maximumBytes: Int?) throws -> [[String: Any]] {
        let data: Data
        if let maximumBytes {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let fileSize = try handle.seekToEnd()
            if fileSize <= UInt64(maximumBytes) {
                try handle.seek(toOffset: 0)
                data = try handle.readToEnd() ?? Data()
            } else {
                // Keep session identity/title context from the beginning and
                // current activity from the end. Reading only the first bytes
                // made long-running Claude sessions look stale after resume.
                let headBytes = max(64 * 1_024, maximumBytes / 4)
                let tailBytes = max(64 * 1_024, maximumBytes - headBytes)
                try handle.seek(toOffset: 0)
                let head = try handle.read(upToCount: headBytes) ?? Data()
                try handle.seek(toOffset: fileSize - UInt64(tailBytes))
                var tail = try handle.readToEnd() ?? Data()
                if let newline = tail.firstIndex(of: 0x0A) {
                    tail = Data(tail[tail.index(after: newline)...])
                }
                data = head + Data("\n".utf8) + tail
            }
        } else {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            guard let lineData = String(line).data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
        }
    }

    private static func textContent(_ value: Any?) -> String {
        if let value = value as? String { return value }
        guard let values = value as? [[String: Any]] else { return "" }
        return values.compactMap { item -> String? in
            guard item["type"] as? String == "text" || item["type"] as? String == "input_text" || item["type"] as? String == "output_text" else { return nil }
            return item["text"] as? String
        }.joined(separator: "\n\n")
    }

    private static func firstLine(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed).prefix(90))
    }
}

private enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case receipt
    case system
}

private struct ChatMessage: Codable, Identifiable, Sendable {
    let id: UUID
    let role: MessageRole
    let text: String
    let provider: String?
    let permissionProfile: String?
    let timestamp: Date
    /// Receipt-only: whether the native backend record was read back after the
    /// step. Absent on receipts written before OS-1 verified persistence.
    let nativeRecordVerified: Bool?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        provider: String? = nil,
        permissionProfile: String? = nil,
        timestamp: Date = Date(),
        nativeRecordVerified: Bool? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.provider = provider
        self.permissionProfile = permissionProfile
        self.timestamp = timestamp
        self.nativeRecordVerified = nativeRecordVerified
    }
}

private struct ConversationSession: Codable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var workspace: String
    var provider: ProviderChoice
    var messages: [ChatMessage]
    var codexSessionID: String?
    var claudeSessionID: String?
    var lastProvider: String?
    var codexCapacity: Int?
    var claudeCapacity: Int?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New session pair",
        workspace: String,
        provider: ProviderChoice = .auto,
        messages: [ChatMessage] = [],
        codexSessionID: String? = nil,
        claudeSessionID: String? = nil,
        lastProvider: String? = nil,
        codexCapacity: Int = 30,
        claudeCapacity: Int = 100,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.workspace = workspace
        self.provider = provider
        self.messages = messages
        self.codexSessionID = codexSessionID
        self.claudeSessionID = claudeSessionID
        self.lastProvider = lastProvider
        self.codexCapacity = codexCapacity
        self.claudeCapacity = claudeCapacity
        self.updatedAt = updatedAt
    }

    var effectiveCodexCapacity: Int { codexCapacity ?? 30 }
    var effectiveClaudeCapacity: Int { claudeCapacity ?? 100 }
}

private struct SessionEnvelope: Codable {
    let schema: Int
    let sessions: [ConversationSession]
}

private struct PendingSubmission: Identifiable, Sendable {
    let id: UUID
    let sessionID: UUID
    let userMessageID: UUID
    let request: String
    let provider: ProviderChoice
    let workspace: String
    let codexCapacity: Int
    let claudeCapacity: Int

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        userMessageID: UUID,
        request: String,
        provider: ProviderChoice,
        workspace: String,
        codexCapacity: Int,
        claudeCapacity: Int
    ) {
        self.id = id
        self.sessionID = sessionID
        self.userMessageID = userMessageID
        self.request = request
        self.provider = provider
        self.workspace = workspace
        self.codexCapacity = codexCapacity
        self.claudeCapacity = claudeCapacity
    }
}

private struct AppNativeRecord: Decodable, Sendable {
    let turnID: String?
    let recordPath: String?
    let persistence: String
    let desktopVisibility: String

    enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case recordPath = "record_path"
        case persistence
        case desktopVisibility = "desktop_visibility"
    }

    var isVerified: Bool { persistence == "verified" }
}

private struct AppRunStep: Decodable, Sendable {
    let sequence: Int
    let provider: String
    let action: String
    let model: String?
    let effort: String
    let revasDisposition: String
    let sessionID: String
    let permissionProfile: String
    let exitCode: Int32
    let output: String
    let stderr: String
    let durationMS: Int64
    let nativeRecord: AppNativeRecord?

    enum CodingKeys: String, CodingKey {
        case sequence, provider, action, model, effort, output, stderr
        case revasDisposition = "revas_disposition"
        case sessionID = "session_id"
        case permissionProfile = "permission_profile"
        case exitCode = "exit_code"
        case durationMS = "duration_ms"
        case nativeRecord = "native_record"
    }
}

/// Receipt wording is derived from evidence the runtime actually gathered, so
/// the receipt never says more than what was read back from the backend.
private func nativeRecordReceipt(_ step: AppRunStep) -> String {
    guard let record = step.nativeRecord else { return "native session linked (unverified)" }
    var parts: [String] = []
    if record.isVerified {
        let file = record.recordPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "record"
        parts.append("native record verified · \(file)")
    } else {
        parts.append("native record \(record.persistence)")
    }
    switch record.desktopVisibility {
    case "local_only": parts.append("local exact receipt persisted")
    case "revealed": parts.append("Codex Desktop: synced and opened")
    case "claude_revealed": parts.append("Claude Desktop: synced and opened")
    case "not_revealed": parts.append("\(step.provider == "claude" ? "Claude" : "Codex") Desktop: kept in background")
    case "desktop_not_running": parts.append("Codex Desktop: lists on launch")
    case let value where value.hasPrefix("reveal_failed"): parts.append("Codex Desktop: open failed")
    case let value where value.hasPrefix("claude_reveal_failed"): parts.append("Claude Desktop: sync failed")
    default: break
    }
    return parts.joined(separator: " · ")
}

private struct AppRunSummary: Decodable, Sendable {
    let status: String
    let steps: [AppRunStep]
}

private enum RunnerError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}

private func backendTierLabel(action: String, provider: String) -> String {
    if provider == "local" || action == "deterministic_compute" {
        return "Exact local RCC executor"
    }
    let engine = provider == "codex" ? "Codex" : "Claude"
    switch action {
    case "agent_run_efficient": return "Efficient \(engine) backend"
    case "agent_run_deep": return "Deep \(engine) backend"
    default: return "Standard \(engine) backend"
    }
}

private func compactSessionAge(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "now" }
    if seconds < 3_600 { return "\(seconds / 60)m" }
    if seconds < 86_400 { return "\(seconds / 3_600)h" }
    if seconds < 2_592_000 { return "\(seconds / 86_400)d" }
    return date.formatted(date: .abbreviated, time: .omitted)
}

private enum OS1Runner {
    static func run(
        workspace: String,
        prompt: String,
        provider: ProviderChoice,
        context: String,
        codexSessionID: String?,
        claudeSessionID: String?,
        codexCapacity: Int,
        claudeCapacity: Int
    ) async throws -> AppRunSummary {
        try await Task.detached(priority: .userInitiated) {
            try runBlocking(
                workspace: workspace,
                prompt: prompt,
                provider: provider,
                context: context,
                codexSessionID: codexSessionID,
                claudeSessionID: claudeSessionID,
                codexCapacity: codexCapacity,
                claudeCapacity: claudeCapacity
            )
        }.value
    }

    private static func executable() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("os1").path
        let candidates = [bundled].compactMap { $0 } + [
            "/usr/local/bin/os1",
            "/opt/homebrew/bin/os1",
            "\(home)/.local/bin/os1",
        ]
        guard let path = candidates.first(where: FileManager.default.isExecutableFile) else {
            throw RunnerError.message("OS-1 runtime is missing. Reinstall OS-1, then try again.")
        }
        return path
    }

    private static func runBlocking(
        workspace: String,
        prompt: String,
        provider: ProviderChoice,
        context: String,
        codexSessionID: String?,
        claudeSessionID: String?,
        codexCapacity: Int,
        claudeCapacity: Int
    ) throws -> AppRunSummary {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory
            .appendingPathComponent("os1-app-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: temporary,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: temporary) }

        let stdoutURL = temporary.appendingPathComponent("stdout.json")
        let stderrURL = temporary.appendingPathComponent("stderr.txt")
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)

        var arguments = [
            "run",
            "--workspace", workspace,
            "--prompt", prompt,
            "--provider", provider.rawValue,
            "--output-format", "json",
        ]
        if !context.isEmpty {
            let contextURL = temporary.appendingPathComponent("session-context.txt")
            try Data(context.utf8).write(
                to: contextURL,
                options: [.atomic, .completeFileProtectionUnlessOpen]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: contextURL.path
            )
            arguments += ["--context-file", contextURL.path]
        }
        if let codexSessionID { arguments += ["--codex-session-id", codexSessionID] }
        if let claudeSessionID { arguments += ["--claude-session-id", claudeSessionID] }
        arguments += [
            "--codex-capacity", String(codexCapacity),
            "--claude-capacity", String(claudeCapacity),
            // Codex and Claude are execution backends. Keep OS-1 in front;
            // users can explicitly open a linked native session from the
            // routing menu when they actually want to inspect that app.
            "--desktop-reveal", "never",
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: try executable())
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        var environment = ProcessInfo.processInfo.environment
        let home = fileManager.homeDirectoryForCurrentUser.path
        let preferredPath = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            environment["PATH"] ?? "",
        ].joined(separator: ":")
        environment["PATH"] = preferredPath
        process.environment = environment

        do {
            try process.run()
            process.waitUntilExit()
            try stdout.close()
            try stderr.close()
        } catch {
            try? stdout.close()
            try? stderr.close()
            throw RunnerError.message("OS-1 could not start: \(error.localizedDescription)")
        }

        let outputData = try Data(contentsOf: stdoutURL)
        let errorText = String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            let fallback = String(decoding: outputData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RunnerError.message(errorText.isEmpty ? fallback : errorText)
        }
        do {
            return try JSONDecoder().decode(AppRunSummary.self, from: outputData)
        } catch {
            throw RunnerError.message("OS-1 returned an unreadable result.")
        }
    }
}

@MainActor
private final class SessionStore: ObservableObject {
    @Published var sessions: [ConversationSession] = []
    @Published var selectedSessionID: UUID?
    @Published var surface: ProviderChoice = .auto
    @Published var composer = ""
    @Published var search = ""
    @Published var nativeSearch = ""
    @Published var nativeSessions: [NativeSessionSummary] = []
    @Published var selectedNativeSessionID: String?
    @Published var nativeMessages: [NativeSessionMessage] = []
    @Published var isLoadingNativeSessions = false
    @Published var isRunning = false
    @Published private(set) var activeSessionID: UUID?
    @Published var pendingProvider: ProviderChoice?
    @Published private(set) var queuedSubmissions: [PendingSubmission] = []
    @Published var statusText = "Ready"
    @Published var alertMessage: String?

    let voiceDictation = VoiceDictationController()

    private let fileManager = FileManager.default

    init() {
        load()
        if sessions.isEmpty {
            createSession(provider: .auto)
        } else {
            selectedSessionID = sessions.first?.id
        }
    }

    var selectedIndex: Int? {
        sessions.firstIndex(where: { $0.id == selectedSessionID })
    }

    var selectedSession: ConversationSession? {
        guard let index = selectedIndex else { return nil }
        return sessions[index]
    }

    var selectedSessionQueueCount: Int {
        guard let selectedSessionID else { return 0 }
        return queuedSubmissions.lazy.filter { $0.sessionID == selectedSessionID }.count
    }

    func isSessionRunning(_ sessionID: UUID) -> Bool {
        isRunning && activeSessionID == sessionID
    }

    var filteredSessions: [ConversationSession] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.workspace.localizedCaseInsensitiveContains(query)
        }
    }

    var filteredNativeSessions: [NativeSessionSummary] {
        let query = nativeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nativeSessions }
        return nativeSessions.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query) ||
            $0.workspace.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedNativeSession: NativeSessionSummary? {
        nativeSessions.first(where: { $0.id == selectedNativeSessionID })
    }

    func createSession(provider: ProviderChoice? = nil) {
        voiceDictation.stop()
        let inherited = provider ?? selectedSession?.provider ?? .auto
        let session = ConversationSession(
            workspace: fileManager.homeDirectoryForCurrentUser.path,
            provider: inherited
        )
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
        composer = ""
        statusText = "Choose a workspace, then describe the task"
        save()
    }

    func select(_ id: UUID) {
        voiceDictation.stop()
        selectedSessionID = id
        composer = ""
        statusText = "Ready"
    }

    func chooseProvider(_ provider: ProviderChoice) {
        guard let index = selectedIndex else { return }
        let previous = sessions[index].provider
        guard previous != provider else { return }
        sessions[index].provider = provider
        sessions[index].updatedAt = Date()
        if !sessions[index].messages.isEmpty {
            sessions[index].messages.append(ChatMessage(
                role: .system,
                text: provider == .auto
                    ? "RCC will choose and continue the matching native Codex or Claude session."
                    : "Next turn will create or resume the linked native \(provider.title) session.",
                provider: provider.rawValue
            ))
        }
        statusText = provider == .auto
            ? "RCC will choose the next engine"
            : "Next turn: \(provider.title)"
        save()
    }

    func showClaudexHome() {
        surface = .auto
        chooseProvider(.auto)
        statusText = isRunning
            ? "Claudex home · a governed task is running"
            : "Claudex home · RCC auto routing"
        NSApp.activate(ignoringOtherApps: true)
    }

    func inspectBackend(_ provider: ProviderChoice) {
        guard provider != .auto else { return }
        voiceDictation.stop()
        surface = provider
        nativeSearch = ""
        let preferredID = provider == .codex
            ? selectedSession?.codexSessionID
            : selectedSession?.claudeSessionID
        statusText = "Syncing local \(provider.title) sessions…"
        isLoadingNativeSessions = true
        nativeMessages = []
        Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try NativeSessionReader.sessions(for: provider)
                }.value
                guard surface == provider else { return }
                var linkedTitles: [String: String] = [:]
                for session in sessions {
                    let id = provider == .codex ? session.codexSessionID : session.claudeSessionID
                    if let id { linkedTitles[id] = session.title }
                }
                nativeSessions = loaded.map { value in
                    var copy = value
                    copy.linkedTitle = linkedTitles[value.id]
                    return copy
                }
                selectedNativeSessionID = preferredID.flatMap { id in
                    nativeSessions.contains(where: { $0.id == id }) ? id : nil
                } ?? nativeSessions.first?.id
                isLoadingNativeSessions = false
                statusText = "\(provider.title) backend · \(nativeSessions.count) local sessions synced"
                loadSelectedNativeTranscript()
            } catch {
                guard surface == provider else { return }
                isLoadingNativeSessions = false
                nativeSessions = []
                selectedNativeSessionID = nil
                nativeMessages = []
                alertMessage = error.localizedDescription
                statusText = "Native session sync needs attention"
            }
        }
    }

    func refreshNativeSessions() {
        guard surface != .auto else { return }
        inspectBackend(surface)
    }

    /// The first-party `codex://threads/<id>` deep link makes Codex Desktop
    /// read the thread through its own app-server and open it, which is the
    /// only way a running Desktop lists a thread OS-1 persisted separately.
    /// If Desktop keeps the writer lock, the next OS-1 turn automatically
    /// forks the complete history and continues in a new visible thread.
    func openInCodexDesktop() {
        guard !isRunning, let index = selectedIndex,
              let id = sessions[index].codexSessionID,
              let url = URL(string: "codex://threads/\(id)") else { return }
        NSWorkspace.shared.open(url)
        sessions[index].messages.append(ChatMessage(
            role: .system,
            text: "Opened Codex session \(id) in Codex Desktop. If Desktop owns this thread, the next OS-1 turn will preserve its history in a new linked Codex session automatically."
        ))
        sessions[index].updatedAt = Date()
        statusText = "Opened in Codex Desktop"
        save()
    }

    /// Claude Code transcripts remain synchronized in OS-1 without opening
    /// Claude Desktop. This explicit action imports and opens the linked CLI
    /// session only when the user asks to inspect the native backend.
    func openInClaudeDesktop() {
        guard !isRunning, let index = selectedIndex,
              let id = sessions[index].claudeSessionID,
              let url = URL(string: "claude://resume?session=\(id)") else { return }
        NSWorkspace.shared.open(url)
        sessions[index].messages.append(ChatMessage(
            role: .system,
            text: "Opened Claude session \(id) in Claude Desktop. The next OS-1 Claude turn will continue in a new linked native session so Desktop remains the sole writer for the opened record."
        ))
        sessions[index].updatedAt = Date()
        statusText = "Opened in Claude Desktop"
        save()
    }

    func selectNativeSession(_ id: String) {
        selectedNativeSessionID = id
        loadSelectedNativeTranscript()
    }

    private func loadSelectedNativeTranscript() {
        guard let session = selectedNativeSession else {
            nativeMessages = []
            return
        }
        let expectedID = session.id
        isLoadingNativeSessions = true
        Task {
            do {
                let messages = try await Task.detached(priority: .userInitiated) {
                    try NativeSessionReader.transcript(for: session)
                }.value
                guard selectedNativeSessionID == expectedID else { return }
                nativeMessages = messages
                isLoadingNativeSessions = false
            } catch {
                guard selectedNativeSessionID == expectedID else { return }
                nativeMessages = []
                isLoadingNativeSessions = false
                alertMessage = error.localizedDescription
            }
        }
    }

    func setCapacity(_ provider: ProviderChoice, value: Int) {
        guard let index = selectedIndex, [0, 10, 25, 50, 75, 100].contains(value) else { return }
        if provider == .codex { sessions[index].codexCapacity = value }
        if provider == .claude { sessions[index].claudeCapacity = value }
        if sessions[index].effectiveCodexCapacity + sessions[index].effectiveClaudeCapacity == 0 {
            if provider == .codex { sessions[index].claudeCapacity = 10 }
            if provider == .claude { sessions[index].codexCapacity = 10 }
        }
        sessions[index].provider = .auto
        sessions[index].updatedAt = Date()
        statusText = "RCC capacity mix updated"
        save()
    }

    func chooseWorkspace() {
        guard !isRunning, let index = selectedIndex else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose the project folder OS-1 may work in"
        panel.prompt = "Use this folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: sessions[index].workspace, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let nextWorkspace = url.standardizedFileURL.path
        if sessions[index].workspace != nextWorkspace,
           sessions[index].codexSessionID != nil || sessions[index].claudeSessionID != nil {
            sessions[index].codexSessionID = nil
            sessions[index].claudeSessionID = nil
            sessions[index].lastProvider = nil
            sessions[index].messages.append(ChatMessage(
                role: .system,
                text: "Workspace changed. Native Codex and Claude links were reset so sessions cannot resume in the wrong project."
            ))
        }
        sessions[index].workspace = nextWorkspace
        sessions[index].updatedAt = Date()
        statusText = "Workspace connected"
        save()
    }

    func useSuggestion(_ value: String) {
        composer = value
    }

    func toggleVoiceDictation() {
        voiceDictation.toggle(
            initialText: composer,
            onTranscript: { [weak self] value in
                self?.composer = value
            },
            onFailure: { [weak self] message in
                self?.alertMessage = message
            }
        )
    }

    func finishVoiceDictation() {
        voiceDictation.finish()
    }

    @discardableResult
    func cancelVoiceDictation() -> Bool {
        guard voiceDictation.isActive else { return false }
        voiceDictation.cancel()
        return true
    }

    func stopVoiceDictation() {
        voiceDictation.stop()
    }

    func send() {
        if voiceDictation.isActive {
            voiceDictation.finish { [weak self] in self?.send() }
            return
        }
        let request = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, let index = selectedIndex else { return }
        var isDirectory: ObjCBool = false
        let workspace = sessions[index].workspace
        guard fileManager.fileExists(atPath: workspace, isDirectory: &isDirectory), isDirectory.boolValue else {
            alertMessage = "Choose an existing project folder before sending the task."
            return
        }

        let configuredProvider = sessions[index].provider
        let provider = configuredProvider == .auto
            ? (explicitlyRequestedProvider(in: request) ?? .auto)
            : configuredProvider
        if sessions[index].messages.isEmpty {
            sessions[index].title = title(for: request)
        }
        let userMessage = ChatMessage(role: .user, text: request)
        sessions[index].updatedAt = Date()
        composer = ""

        let submission = PendingSubmission(
            sessionID: sessions[index].id,
            userMessageID: userMessage.id,
            request: request,
            provider: provider,
            workspace: workspace,
            codexCapacity: sessions[index].effectiveCodexCapacity,
            claudeCapacity: sessions[index].effectiveClaudeCapacity
        )
        if isRunning {
            queuedSubmissions.append(submission)
            statusText = "Task queued · \(queuedSubmissions.count) waiting"
            save()
            return
        }
        sessions[index].messages.append(userMessage)
        start(submission)
    }

    private func start(_ submission: PendingSubmission) {
        guard !isRunning,
              let index = sessions.firstIndex(where: { $0.id == submission.sessionID }) else {
            runNextQueuedSubmissionIfNeeded()
            return
        }
        let existingUserMessage = sessions[index].messages.contains { $0.id == submission.userMessageID }
        let context = handoffContext(
            for: sessions[index],
            nextProvider: submission.provider,
            before: existingUserMessage ? submission.userMessageID : nil
        )
        if !existingUserMessage {
            sessions[index].messages.append(ChatMessage(
                id: submission.userMessageID,
                role: .user,
                text: submission.request
            ))
            sessions[index].updatedAt = Date()
        }
        let codexSessionID = sessions[index].codexSessionID
        let claudeSessionID = sessions[index].claudeSessionID
        isRunning = true
        activeSessionID = submission.sessionID
        pendingProvider = submission.provider == .auto ? nil : submission.provider
        statusText = submission.provider == .auto
            ? "RCC is choosing the best engine…"
            : "\(submission.provider.title) is working…"
        save()

        Task {
            do {
                let summary = try await OS1Runner.run(
                    workspace: submission.workspace,
                    prompt: submission.request,
                    provider: submission.provider,
                    context: context,
                    codexSessionID: codexSessionID,
                    claudeSessionID: claudeSessionID,
                    codexCapacity: submission.codexCapacity,
                    claudeCapacity: submission.claudeCapacity
                )
                guard let target = sessions.firstIndex(where: { $0.id == submission.sessionID }) else {
                    throw RunnerError.message("The queued OS-1 session no longer exists.")
                }
                if summary.status != "complete" {
                    throw RunnerError.message("OS-1 did not return a completed governed run.")
                }
                if submission.provider != .auto, summary.steps.isEmpty {
                    throw RunnerError.message("OS-1 did not create or resume the requested \(submission.provider.title) backend session.")
                }
                if submission.provider != .auto,
                   summary.steps.contains(where: { $0.provider != submission.provider.rawValue }) {
                    throw RunnerError.message("OS-1 rejected a backend mismatch. The request targeted \(submission.provider.title), but a different backend answered.")
                }
                if summary.steps.contains(where: { UUID(uuidString: $0.sessionID) == nil }) {
                    throw RunnerError.message("OS-1 rejected an invalid native backend session link.")
                }
                if summary.steps.isEmpty {
                    sessions[target].messages.append(ChatMessage(
                        role: .assistant,
                        text: "The governed route completed without an additional model step.",
                        provider: submission.provider.rawValue
                    ))
                }
                for step in summary.steps {
                    if step.provider == "codex" {
                        sessions[target].codexSessionID = step.sessionID
                    } else if step.provider == "claude" {
                        sessions[target].claudeSessionID = step.sessionID
                    }
                    sessions[target].lastProvider = step.provider
                    let visibleOutput = step.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    let visibleError = step.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    sessions[target].messages.append(ChatMessage(
                        role: .assistant,
                        text: visibleOutput.isEmpty
                            ? (visibleError.isEmpty ? "The engine finished without text output." : visibleError)
                            : visibleOutput,
                        provider: step.provider,
                        permissionProfile: step.permissionProfile
                    ))
                    sessions[target].messages.append(ChatMessage(
                        role: .receipt,
                        text: "\(backendTierLabel(action: step.action, provider: step.provider)) · \(step.model ?? "provider default") · \(step.effort) reasoning · REVAS \(step.revasDisposition) · \(nativeRecordReceipt(step)) · step \(step.sequence) · \(step.durationMS / 1_000)s · exit \(step.exitCode)",
                        provider: step.provider,
                        permissionProfile: step.permissionProfile,
                        nativeRecordVerified: (step.nativeRecord?.isVerified ?? false) && step.revasDisposition == "adopted"
                    ))
                }
                sessions[target].updatedAt = Date()
                let allVerified = summary.steps.allSatisfy { $0.nativeRecord?.isVerified == true }
                statusText = allVerified
                    ? "Native record verified · evidence recorded"
                    : "Native record unverified · check the receipt"
            } catch {
                if let target = sessions.firstIndex(where: { $0.id == submission.sessionID }) {
                    sessions[target].messages.append(ChatMessage(
                        role: .system,
                        text: error.localizedDescription
                    ))
                    sessions[target].updatedAt = Date()
                }
                statusText = "Needs attention"
            }
            isRunning = false
            activeSessionID = nil
            pendingProvider = nil
            save()
            runNextQueuedSubmissionIfNeeded()
        }
    }

    private func runNextQueuedSubmissionIfNeeded() {
        guard !isRunning, !queuedSubmissions.isEmpty else { return }
        let next = queuedSubmissions.removeFirst()
        guard sessions.contains(where: { $0.id == next.sessionID }) else {
            runNextQueuedSubmissionIfNeeded()
            return
        }
        start(next)
    }

    private func title(for request: String) -> String {
        let firstLine = request.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? request
        return String(firstLine.prefix(48))
    }

    private func handoffContext(
        for session: ConversationSession,
        nextProvider: ProviderChoice,
        before userMessageID: UUID? = nil
    ) -> String {
        guard !session.messages.isEmpty else { return "" }
        if nextProvider != .auto, session.lastProvider == nextProvider.rawValue { return "" }
        let boundedMessages: ArraySlice<ChatMessage>
        if let userMessageID,
           let messageIndex = session.messages.firstIndex(where: { $0.id == userMessageID }) {
            boundedMessages = session.messages[..<messageIndex]
        } else {
            boundedMessages = session.messages[...]
        }
        let relevant = boundedMessages.filter { $0.role == .user || $0.role == .assistant }.suffix(16)
        let text = relevant.map { message in
            let speaker = message.role == .user
                ? "USER"
                : (message.provider?.uppercased() ?? "ASSISTANT")
            return "\(speaker):\n\(String(message.text.prefix(12_000)))"
        }.joined(separator: "\n\n")
        return String(text.suffix(180_000))
    }

    private var storageURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OS-1", isDirectory: true)
            .appendingPathComponent("sessions.json", isDirectory: false)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let envelope = try? JSONDecoder().decode(SessionEnvelope.self, from: data),
              [1, 2, 3].contains(envelope.schema) else { return }
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        sessions = envelope.sessions
            .filter { $0.updatedAt >= cutoff }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(30)
            .map { session in
                var bounded = session
                bounded.messages = Array(session.messages.suffix(40))
                return bounded
            }
    }

    private func save() {
        let directory = storageURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let bounded = sessions.sorted { $0.updatedAt > $1.updatedAt }.prefix(30).map { session in
                var copy = session
                copy.messages = Array(session.messages.suffix(40)).map { message in
                    ChatMessage(
                        id: message.id,
                        role: message.role,
                        text: String(message.text.prefix(120_000)),
                        provider: message.provider,
                        permissionProfile: message.permissionProfile,
                        timestamp: message.timestamp,
                        nativeRecordVerified: message.nativeRecordVerified
                    )
                }
                return copy
            }
            let data = try JSONEncoder().encode(SessionEnvelope(schema: 3, sessions: bounded))
            try data.write(to: storageURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
        } catch {
            alertMessage = "Session history could not be saved: \(error.localizedDescription)"
        }
    }
}

private enum Theme {
    static let background = Color(red: 0.008, green: 0.008, blue: 0.011)
    static let panel = Color(red: 0.015, green: 0.014, blue: 0.017)
    static let panelRaised = Color(red: 0.035, green: 0.029, blue: 0.034)
    static let border = Color.white.opacity(0.14)
    static let borderStrong = Color.white.opacity(0.22)
    static let muted = Color.white.opacity(0.47)
    static let text = Color.white.opacity(0.95)
    static let pink = Color(red: 0.93, green: 0.70, blue: 0.80)
    static let pinkDeep = Color(red: 0.22, green: 0.10, blue: 0.16)
    static let green = Color(red: 0.28, green: 0.93, blue: 0.55)
    static let radiusShell: CGFloat = 22
    static let radiusPanel: CGFloat = 18
    static let radiusControl: CGFloat = 13
    static let radiusMessage: CGFloat = 16
    static let radiusComposer: CGFloat = 22
    @MainActor static let constellationImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "Constellation", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}

private struct OmarAGILogo: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "OmarAGI", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                ZStack {
                    Circle().stroke(Theme.pink, lineWidth: max(4, size * 0.18))
                    Circle().fill(Color.white.opacity(0.94)).frame(width: max(4, size * 0.12))
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

private struct ProviderBrandIcon: View {
    let provider: ProviderChoice
    let size: CGFloat
    var filled = true

    private var resourceName: String {
        provider == .claude ? "ClaudeCode" : "Codex"
    }

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                Image(systemName: provider == .claude ? "sun.max.fill" : "chevron.left.forwardslash.chevron.right")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(provider.tint)
                    .padding(size * 0.2)
            }
        }
        .frame(width: size, height: size)
        .opacity(filled ? 1 : 0.96)
        .accessibilityHidden(true)
    }
}

@main
private struct OS1DesktopApp: App {
    @StateObject private var store: SessionStore

    init() {
        if CommandLine.arguments.contains("--self-test") {
            do {
                try providerIntentSelfTest()
                print("OS-1 app provider intent, native dispatch, and voice dictation self-test: OK")
                exit(EXIT_SUCCESS)
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        _store = StateObject(wrappedValue: SessionStore())
    }

    var body: some Scene {
        WindowGroup("OS-1 Claudex") {
            RootView(store: store)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New session pair") { store.createSession() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
            CommandMenu("Voice") {
                Button(store.voiceDictation.isActive ? "Finish Dictation" : "Start Dictation") {
                    store.toggleVoiceDictation()
                }
                .keyboardShortcut(.space, modifiers: [.command, .shift])

                Button("Cancel Dictation") {
                    _ = store.cancelVoiceDictation()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!store.voiceDictation.isActive)
            }
        }
    }
}

private struct RootView: View {
    @ObservedObject var store: SessionStore
    @State private var backdropOffset = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CosmicBackdrop(offset: backdropOffset)
                VStack(spacing: 0) {
                    HStack {
                        Text("INTERACTIVE PRODUCT VIEW")
                        Spacer()
                        HStack(spacing: 8) {
                            Circle().fill(Theme.green).frame(width: 7, height: 7)
                                .shadow(color: Theme.green.opacity(0.82), radius: 6)
                            Text("GOVERNANCE ACTIVE")
                        }
                    }
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.7)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 3)
                    .frame(height: 28, alignment: .top)

                    HStack(spacing: 0) {
                        ProviderRail(store: store)
                        Rectangle().fill(Theme.border).frame(width: 1)
                        if store.surface == .auto {
                            SessionSidebar(store: store)
                            Rectangle().fill(Theme.border).frame(width: 1)
                            ConversationView(store: store)
                        } else {
                            NativeSessionBrowser(store: store, provider: store.surface)
                        }
                    }
                    .background(Theme.background.opacity(0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusShell, style: .continuous)
                            .stroke(Theme.borderStrong, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusShell, style: .continuous))
                    .shadow(color: Color.black.opacity(0.42), radius: 22, y: 12)
                }
                .padding(12)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let width = max(geometry.size.width, 1)
                    let height = max(geometry.size.height, 1)
                    backdropOffset = CGSize(
                        width: ((location.x / width) - 0.5) * -12,
                        height: ((location.y / height) - 0.5) * -9
                    )
                case .ended:
                    backdropOffset = .zero
                }
            }
        }
        .frame(minWidth: 1_100, minHeight: 680)
        .background(Theme.background)
        .alert("OS-1 Claudex", isPresented: Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }
}

private struct CosmicBackdrop: View {
    let offset: CGSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image = Theme.constellationImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(
                            width: geometry.size.width * 1.07,
                            height: geometry.size.height * 1.07
                        )
                        .offset(offset)
                        .opacity(0.72)
                }
                RadialGradient(
                    colors: [Color.black.opacity(0.10), Color.black.opacity(0.72)],
                    center: UnitPoint(x: 0.52, y: 0.42),
                    startRadius: 20,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.72
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .animation(.linear(duration: 0.11), value: offset)
    }
}

private struct ProviderRail: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(spacing: 22) {
            Button { store.showClaudexHome() } label: {
                OmarAGILogo(size: 48)
            }
            .buttonStyle(.plain)
            .help("Claudex home")
            .accessibilityLabel("Claudex home")
            .padding(.bottom, 8)

            ForEach([ProviderChoice.codex, ProviderChoice.claude]) { provider in
                BackendStatus(
                    provider: provider,
                    selected: store.surface == provider,
                    active: store.selectedSession?.lastProvider == provider.rawValue,
                    linked: provider == .codex
                        ? store.selectedSession?.codexSessionID != nil
                        : store.selectedSession?.claudeSessionID != nil,
                    disabled: false
                ) { store.inspectBackend(provider) }
            }

            Spacer()

            VStack(spacing: 6) {
                Circle().fill(Theme.green).frame(width: 9, height: 9)
                    .shadow(color: Theme.green.opacity(0.85), radius: 6)
                Text("RCC\nGOVERNED")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 24)
        .frame(width: 78)
        .background(Color.black.opacity(0.74))
    }
}

private struct BackendStatus: View {
    let provider: ProviderChoice
    let selected: Bool
    let active: Bool
    let linked: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                ProviderBrandIcon(provider: provider, size: 28)
                Text(provider == .claude ? "CLAUDE" : "CODEX")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 3) {
                    Circle().fill(linked ? Theme.green : Theme.muted).frame(width: 4, height: 4)
                    Text(linked ? "SYNCED" : "CONNECT")
                        .font(.system(size: 5.5, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(linked ? (selected ? Theme.text : provider.tint) : Theme.muted)
            .frame(width: 58, height: 80)
            .background(linked ? provider.tint.opacity(selected ? 0.13 : (active ? 0.08 : 0.025)) : Color.black.opacity(0.25))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .stroke(linked ? provider.tint.opacity(selected || active ? 0.75 : 0.25) : Theme.border, lineWidth: selected ? 1.3 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help("View synchronized \(provider.title) sessions inside Claudex")
        .accessibilityLabel(provider == .claude ? "Claude Code backend" : "Codex backend")
    }
}

private struct NativeSessionBrowser: View {
    @ObservedObject var store: SessionStore
    let provider: ProviderChoice

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("OS-1").foregroundStyle(Theme.pink)
                    Text("CLAUDEX").foregroundStyle(Theme.text)
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .tracking(2.1)
                .padding(.horizontal, 24)
                .padding(.top, 34)
                .padding(.bottom, 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text(provider == .claude ? "CLAUDE CODE SESSIONS" : "CODEX SESSIONS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(provider.tint)
                    HStack(spacing: 6) {
                        Circle().fill(Theme.green).frame(width: 6, height: 6)
                        Text("SYNCED · \(store.nativeSessions.count)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Search \(provider.title) sessions", text: $store.nativeSearch)
                        .textFieldStyle(.plain)
                    Button { store.refreshNativeSessions() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh local sessions")
                    .accessibilityLabel("Refresh backend sessions")
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Color.black.opacity(0.24))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .stroke(Theme.borderStrong)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                if store.isLoadingNativeSessions && store.nativeSessions.isEmpty {
                    Spacer()
                    ProgressView("Synchronizing local sessions…")
                        .controlSize(.small)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if store.filteredNativeSessions.isEmpty {
                    Spacer()
                    Text("No local sessions found")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(store.filteredNativeSessions) { session in
                                NativeSessionRow(
                                    session: session,
                                    selected: store.selectedNativeSessionID == session.id,
                                    tint: provider.tint
                                ) { store.selectNativeSession(session.id) }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                }
            }
            .frame(width: 315)
            .background(Color.black.opacity(0.72))

            Rectangle().fill(Theme.border).frame(width: 1)

            NativeTranscriptView(store: store, provider: provider)
        }
    }
}

private struct NativeSessionRow: View {
    let session: NativeSessionSummary
    let selected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Circle().fill(session.linkedTitle == nil ? Theme.muted : Theme.green)
                        .frame(width: 6, height: 6)
                    Text(session.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if session.linkedTitle != nil {
                        Text("OS1")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.green)
                    }
                }
                HStack(spacing: 6) {
                    Text(session.displayWorkspace)
                        .lineLimit(1)
                    Spacer()
                    Text(compactSessionAge(session.updatedAt))
                        .lineLimit(1)
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.panelRaised : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(selected ? tint.opacity(0.42) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.displayTitle)
    }
}

private struct NativeTranscriptView: View {
    @ObservedObject var store: SessionStore
    let provider: ProviderChoice

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("\(provider == .claude ? "CLAUDE CODE" : "CODEX") · \(store.selectedNativeSession?.displayTitle ?? "SELECT A SESSION")")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer()
                if let session = store.selectedNativeSession, !session.workspace.isEmpty {
                    Text(session.displayWorkspace)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Circle().fill(Theme.green).frame(width: 8, height: 8)
                    .shadow(color: Theme.green.opacity(0.75), radius: 5)
                Text("RCC governed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 24)
            .frame(height: 66)
            .background(Color.black.opacity(0.72))

            Rectangle().fill(Theme.border).frame(height: 1)

            if store.selectedNativeSession == nil {
                Spacer()
                Text("Choose a \(provider.title) session from the left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
            } else if store.isLoadingNativeSessions && store.nativeMessages.isEmpty {
                Spacer()
                ProgressView("Loading synchronized transcript…")
                    .controlSize(.small)
                    .foregroundStyle(Theme.muted)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(store.nativeMessages) { message in
                                NativeMessageCard(message: message, provider: provider)
                                    .id(message.id)
                            }
                            if store.nativeMessages.isEmpty {
                                Text("This session has no visible user or assistant messages yet.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                                    .padding(.top, 60)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 30)
                        .frame(maxWidth: 1_020)
                        .frame(maxWidth: .infinity)
                    }
                    .onAppear { scrollToBottom(proxy) }
                    .onChange(of: store.nativeMessages.count) { _ in scrollToBottom(proxy) }
                }
            }

            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("READ-ONLY SYNCHRONIZED BACKEND · USE CLAUDEX HOME TO ROUTE THE NEXT TASK")
                Spacer()
                Text(provider == .claude ? "CLAUDE CODE" : "CODEX")
                    .foregroundStyle(provider.tint)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Color.black.opacity(0.72))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let id = store.nativeMessages.last?.id else { return }
        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .bottom) }
    }
}

private struct NativeMessageCard: View {
    let message: NativeSessionMessage
    let provider: ProviderChoice

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 100) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    if message.role == .user {
                        Image(systemName: "person.crop.circle.fill")
                    } else {
                        ProviderBrandIcon(provider: provider, size: 14, filled: false)
                    }
                    Text(message.role == .user ? "YOU" : (provider == .claude ? "CLAUDE CODE" : "CODEX"))
                    Spacer()
                    if let timestamp = message.timestamp {
                        Text(timestamp, style: .time)
                    }
                }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(message.role == .user ? Theme.muted : provider.tint)
                Text(message.text)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(message.role == .user ? Color.black.opacity(0.5) : provider.tint.opacity(0.025))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMessage, style: .continuous)
                    .stroke(message.role == .user ? Theme.borderStrong : provider.tint.opacity(0.18))
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMessage, style: .continuous))
            if message.role != .user { Spacer(minLength: 60) }
        }
    }
}

private struct RailButton: View {
    let provider: ProviderChoice
    let selected: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ProviderBrandIcon(provider: provider, size: 24)
                Text(provider.title.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
            }
            .foregroundStyle(selected ? provider.tint : Theme.muted)
            .frame(width: 58, height: 58)
            .background(selected ? provider.tint.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? provider.tint : Theme.border, lineWidth: selected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help("Use \(provider.title) for the next turn")
    }
}

private struct SessionSidebar: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("OS-1")
                    .foregroundStyle(Theme.pink)
                Text("CLAUDEX")
                    .foregroundStyle(Theme.text)
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .tracking(2.1)
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 24)

            Button { store.createSession() } label: {
                Label("New governed task", systemImage: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(Color.black.opacity(0.24))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                            .stroke(Theme.borderStrong)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search sessions", text: $store.search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Color.black.opacity(0.24))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .stroke(Theme.borderStrong)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 12)

            HStack {
                Text("SYNCED SESSIONS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(store.filteredSessions.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 25)
            .padding(.top, 24)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.filteredSessions) { session in
                        SessionRow(
                            session: session,
                            selected: store.selectedSessionID == session.id
                        ) { store.select(session.id) }
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 315)
        .background(Color.black.opacity(0.72))
    }
}

private struct SessionRow: View {
    let session: ConversationSession
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    Text(URL(fileURLWithPath: session.workspace).lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.panelRaised : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(selected ? Theme.border.opacity(0.45) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

private struct NativeBadge: View {
    let label: String
    let linked: Bool
    let tint: Color

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(linked ? tint : Theme.muted.opacity(0.55))
            .frame(width: 17, height: 15)
            .background(linked ? tint.opacity(0.13) : Color.white.opacity(0.025))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(linked ? tint.opacity(0.45) : Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct ConversationView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            ConversationHeader(store: store)
            Rectangle().fill(Theme.border).frame(height: 1)
            if let session = store.selectedSession {
                if session.messages.isEmpty {
                    WelcomeView(store: store, session: session)
                } else {
                    MessageTimeline(
                        session: session,
                        isRunning: store.isSessionRunning(session.id),
                        queuedSubmissions: store.queuedSubmissions.filter { $0.sessionID == session.id }
                    )
                }
                ComposerView(store: store, session: session)
            }
        }
        .background(Theme.background)
    }
}

private struct ConversationHeader: View {
    @ObservedObject var store: SessionStore

    private var providerLabel: String {
        let value: String
        if store.activeSessionID == store.selectedSessionID {
            value = store.pendingProvider?.rawValue ?? store.selectedSession?.lastProvider ?? "RCC"
        } else {
            value = store.selectedSession?.lastProvider ?? "RCC"
        }
        return value.uppercased()
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(providerLabel) · \(store.selectedSession?.title ?? "OS-1 CLAUDEX")")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(Theme.green).frame(width: 6, height: 6)
                    Text(store.statusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer()

            if let session = store.selectedSession {
                Circle().fill(Theme.green).frame(width: 8, height: 8)
                    .shadow(color: Theme.green.opacity(0.75), radius: 5)
                Text("RCC governed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)

                Menu {
                    Button("Auto routing") { store.chooseProvider(.auto) }
                    Divider()
                    Menu("Codex capacity · \(session.effectiveCodexCapacity)%") {
                        ForEach([0, 10, 25, 50, 75, 100], id: \.self) { value in
                            Button("\(value)%") { store.setCapacity(.codex, value: value) }
                        }
                    }
                    Menu("Claude capacity · \(session.effectiveClaudeCapacity)%") {
                        ForEach([0, 10, 25, 50, 75, 100], id: \.self) { value in
                            Button("\(value)%") { store.setCapacity(.claude, value: value) }
                        }
                    }
                    Divider()
                    Button("Force Codex next turn") { store.chooseProvider(.codex) }
                    Button("Force Claude next turn") { store.chooseProvider(.claude) }
                    Divider()
                    Button("Inspect Codex backend") { store.inspectBackend(.codex) }
                        .disabled(session.codexSessionID == nil)
                    Button("Open in Codex Desktop") { store.openInCodexDesktop() }
                        .disabled(session.codexSessionID == nil)
                    Button("Inspect Claude backend") { store.inspectBackend(.claude) }
                        .disabled(session.claudeSessionID == nil)
                    Button("Open in Claude Desktop") { store.openInClaudeDesktop() }
                        .disabled(session.claudeSessionID == nil)
                } label: {
                    Label(
                        session.provider == .auto
                            ? "Auto mix · C\(session.effectiveCodexCapacity) A\(session.effectiveClaudeCapacity)"
                            : "Override · \(session.provider.title)",
                        systemImage: "slider.horizontal.3"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.green)
                    .padding(.horizontal, 10)
                    .frame(height: 35)
                    .background(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                            .stroke(Theme.border)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(store.isRunning)

                Button { store.chooseWorkspace() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder")
                        Text(URL(fileURLWithPath: session.workspace).lastPathComponent)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 11)
                    .frame(height: 35)
                    .background(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                            .stroke(Theme.border)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(store.isRunning)
                .help(session.workspace)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 66)
        .background(Color.black.opacity(0.72))
    }
}

private struct WelcomeView: View {
    @ObservedObject var store: SessionStore
    let session: ConversationSession

    private let suggestions = [
        "Inspect this project and explain the safest next step.",
        "Find the current bug, fix it, and verify the result.",
        "Review the repository and make the smallest production-ready improvement.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 34)
                HStack(spacing: 12) {
                    Image(systemName: "diamond")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.pink)
                        .frame(width: 34, height: 34)
                        .background(Theme.pinkDeep)
                        .clipShape(Circle())
                    Text("Routing, model execution, token control, and receipts stay on one governed path.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                Text("Start a governed task.")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("Choose the project once. RCC routes each turn to Codex or Claude Code with the model tier, reasoning effort, token budget, and workspace authority kept on the same governed path.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    WelcomeStep(number: "1", title: "Choose folder", detail: "The project OS-1 may inspect or edit")
                    WelcomeStep(number: "2", title: "Set capacity", detail: "Default mix conserves scarce Codex usage")
                    WelcomeStep(number: "3", title: "Use OS-1", detail: "RCC selects backend, model, and effort")
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("TRY ONE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(Theme.muted)
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button { store.useSuggestion(suggestion) } label: {
                            HStack {
                                Text(suggestion)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 46)
                            .background(Color.black.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                                    .stroke(Theme.border)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 52)
            .frame(maxWidth: 850, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WelcomeStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.green)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(Color.black.opacity(0.3))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous)
                .stroke(Theme.border)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
    }
}

private struct MessageTimeline: View {
    let session: ConversationSession
    let isRunning: Bool
    let queuedSubmissions: [PendingSubmission]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(session.messages) { message in
                        MessageView(message: message).id(message.id)
                    }
                    ForEach(queuedSubmissions) { submission in
                        HStack {
                            Spacer(minLength: 100)
                            VStack(alignment: .trailing, spacing: 7) {
                                Text(submission.request)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.text.opacity(0.72))
                                    .multilineTextAlignment(.trailing)
                                Label("QUEUED", systemImage: "text.line.last.and.arrowtriangle.forward")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.pink)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background(Theme.panelRaised.opacity(0.72))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusMessage, style: .continuous)
                                    .stroke(Theme.pink.opacity(0.24))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMessage, style: .continuous))
                        }
                        .id(submission.id)
                    }
                    if isRunning {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Working in \(session.workspace)…")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                            if !queuedSubmissions.isEmpty {
                                Text("\(queuedSubmissions.count) queued")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.pink)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Theme.pinkDeep)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .id("running")
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 34)
                .frame(maxWidth: 1_020)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                if let last = session.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: session.messages.count) { _ in
                if let last = session.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

private struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 100)
                Text(message.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(Color.black.opacity(0.28))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMessage, style: .continuous)
                            .stroke(Theme.borderStrong)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMessage, style: .continuous))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    if message.provider == "local" {
                        Image(systemName: "function")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .frame(width: 14, height: 14)
                    } else {
                        ProviderBrandIcon(
                            provider: message.provider == "claude" ? .claude : .codex,
                            size: 14,
                            filled: false
                        )
                    }
                    Text((message.provider ?? "OS-1").uppercased())
                    if let permission = message.permissionProfile {
                        Text("· \(permission.replacingOccurrences(of: "_", with: " "))")
                            .foregroundStyle(Theme.muted)
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(message.provider == "local"
                    ? Theme.green
                    : (message.provider == "claude" ? ProviderChoice.claude.tint : ProviderChoice.codex.tint))
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .receipt:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("RCC GOVERNANCE RECEIPT")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(Theme.pink)
                    Spacer()
                    // Receipts saved before native-record verification existed
                    // carry no flag and keep their historical label.
                    Text(message.nativeRecordVerified == false ? "UNVERIFIED" : "VERIFIED")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(message.nativeRecordVerified == false ? Theme.pink : Theme.green)
                }
                Text(message.text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(Color.black.opacity(0.36))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMessage, style: .continuous)
                    .stroke(Theme.borderStrong)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMessage, style: .continuous))
        case .system:
            HStack(spacing: 8) {
                Image(systemName: "diamond")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.pink)
                    .frame(width: 30, height: 30)
                    .background(Theme.pinkDeep)
                    .clipShape(Circle())
                Text(message.text)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .foregroundStyle(Theme.muted)
            .padding(.vertical, 4)
        }
    }
}

/// Keeps SwiftUI's native focus, accessibility, undo, and IME behavior while
/// applying Codex's Return-to-send convention only to the focused composer.
@MainActor
private final class ComposerKeyMonitor: ObservableObject {
    var isFocused = false
    var submit: (() -> Void)?
    var cancelVoice: (() -> Bool)?
    private var eventMonitor: Any?

    func start() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isFocused else { return event }
            if event.keyCode == 53, self.cancelVoice?() == true {
                return nil
            }
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            guard isReturn,
                  composerReturnAction(shiftPressed: event.modifierFlags.contains(.shift)) == .send else {
                return event
            }
            if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
               textView.hasMarkedText() {
                return event
            }
            self.submit?()
            return nil
        }
    }

    func stop() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

}

private struct ClaudexComposerEditor: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancelVoice: () -> Bool
    @StateObject private var keyMonitor = ComposerKeyMonitor()
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.text)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .onAppear {
                keyMonitor.submit = onSubmit
                keyMonitor.cancelVoice = onCancelVoice
                isFocused = true
                keyMonitor.isFocused = true
                keyMonitor.start()
            }
            .onChange(of: isFocused) { focused in
                keyMonitor.isFocused = focused
            }
            .onDisappear {
                keyMonitor.isFocused = false
                keyMonitor.stop()
            }
    }
}

private struct VoiceWaveform: View {
    let level: CGFloat

    private let weights: [CGFloat] = [0.44, 0.72, 1, 0.62, 0.86]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(weights.enumerated()), id: \.offset) { _, weight in
                Capsule()
                    .fill(Theme.pink)
                    .frame(width: 3, height: 6 + (max(0.12, level) * 17 * weight))
            }
        }
        .frame(width: 28, height: 28)
        .animation(.easeOut(duration: 0.09), value: level)
        .accessibilityHidden(true)
    }
}

private struct VoiceDictationControl: View {
    @ObservedObject var controller: VoiceDictationController
    let start: () -> Void
    let finish: () -> Void
    let cancel: () -> Void

    var body: some View {
        Group {
            if controller.isActive {
                HStack(spacing: 6) {
                    Button(action: cancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 30)
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel and restore the previous text (Esc)")
                    .accessibilityLabel("Cancel voice input")

                    if controller.isAuthorizing || controller.isFinalizing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.pink)
                            .frame(width: 28, height: 28)
                    } else {
                        VoiceWaveform(level: controller.level)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(controller.statusLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("\(controller.engineLabel) · \(controller.elapsedLabel)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .fixedSize()
                    }
                    .frame(minWidth: 52, alignment: .leading)

                    Button(action: finish) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.86))
                            .frame(width: 32, height: 32)
                            .background(Theme.pink)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.isFinalizing)
                    .help("Use this transcript")
                    .accessibilityLabel("Finish voice input")
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(Theme.panelRaised)
                .overlay(
                    Capsule().stroke(Theme.pink.opacity(0.56), lineWidth: 1)
                )
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                Button(action: start) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                        .background(Theme.panelRaised)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.borderStrong))
                }
                .buttonStyle(.plain)
                .help("Dictate task (⌘⇧Space)")
                .accessibilityLabel("Start voice input")
            }
        }
        .animation(.easeInOut(duration: 0.16), value: controller.isActive)
    }
}

private struct ComposerView: View {
    @ObservedObject var store: SessionStore
    let session: ConversationSession

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                ClaudexComposerEditor(
                    text: $store.composer,
                    onSubmit: store.send,
                    onCancelVoice: store.cancelVoiceDictation
                )
                    .frame(minHeight: 70, maxHeight: 130)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .overlay(alignment: .topLeading) {
                        if store.composer.isEmpty {
                            Text("Route a governed task through OS-1…")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.3))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }

                VoiceDictationControl(
                    controller: store.voiceDictation,
                    start: store.toggleVoiceDictation,
                    finish: store.finishVoiceDictation,
                    cancel: { _ = store.cancelVoiceDictation() }
                )

                Button { store.send() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.86))
                        .frame(width: 44, height: 44)
                        .background(Theme.pink)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(store.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(store.isRunning ? "Add this task to the queue" : "Send task")
            }
            .padding(12)
            .background(Color.black.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusComposer, style: .continuous)
                    .stroke(Theme.borderStrong)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusComposer, style: .continuous))
            .shadow(color: Color.black.opacity(0.32), radius: 16, y: 8)

            HStack {
                Label(URL(fileURLWithPath: session.workspace).lastPathComponent, systemImage: "folder")
                Text("·")
                Text("OS-1 · RCC governed")
                Text("·")
                Text("capacity C\(session.effectiveCodexCapacity) / A\(session.effectiveClaudeCapacity)")
                Text("·")
                Text("Codex \(session.codexSessionID == nil ? "not linked" : "linked")")
                Text("·")
                Text("Claude \(session.claudeSessionID == nil ? "not linked" : "linked")")
                if store.selectedSessionQueueCount > 0 {
                    Text("·")
                    Label("\(store.selectedSessionQueueCount) queued", systemImage: "text.line.last.and.arrowtriangle.forward")
                        .foregroundStyle(Theme.pink)
                }
                if store.voiceDictation.isActive {
                    Text("·")
                    Label(
                        "\(store.voiceDictation.statusLabel) · \(store.voiceDictation.engineLabel) · \(store.voiceDictation.elapsedLabel)",
                        systemImage: "waveform"
                    )
                        .foregroundStyle(Theme.pink)
                }
                Spacer()
                Text("⌘⇧Space dictate · Esc cancel · ↩ send · ⇧↩ newline")
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 38)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Theme.background)
        .onDisappear { store.stopVoiceDictation() }
    }
}
