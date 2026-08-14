import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import AudioToolbox
import ScreenCaptureKit
import CanaryTranscriberCore

public final class TranscriptionViewModel: ObservableObject {
    @Published var files: [AudioFileItem] = []
    @Published var selectedFileID: AudioFileItem.ID?
    @Published var logs: String = "Ready. Add audio files and click Transcribe.\n"

    @Published var pythonPath: String = TranscriptionViewModel.defaultCanaryPythonPath()
    @Published var selectedProfileID: String = "multilingual-canary-v2"
    @Published var runtime: String = "mlx_audio_cli"
    @Published var model: String = "CogniSoftOrg/canary-1b-v2-mlx-bf16"
    @Published var language: String = "ru"
    @Published var chunkDuration: String = "30"
    @Published var timestamps: Bool = false
    @Published var writeNextToSource: Bool = true
    @Published var outputFolder: String = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/CanaryTranscripts").path
    @Published var separateMarkdownOutput: Bool = false
    @Published var markdownOutputFolder: String = ""
    @Published var diarizationEnabled: Bool = false
    @Published var diarizationSpeakerCount: String = "2"
    private let speakerAliasPersistence: SpeakerAliasPersistence
    @Published var speakerAliasesText: String {
        didSet { speakerAliasPersistence.saveText(speakerAliasesText) }
    }

    let libraryStore: SessionLibraryStore
    @Published var librarySessions: [SessionRecord] = []
    var activeSessionIDsByPath: [String: SessionRecord.ID] = [:]
    var logStartIndexByPath: [String: String.Index] = [:]
    /// Pre-requeue snapshot of a reused Library row, so cancelling a staged re-run via
    /// `removeQueuedSession` restores the prior state instead of deleting history.
    var revertSnapshots: [String: SessionRecord] = [:]

    public init(aliasPersistence: SpeakerAliasPersistence = SpeakerAliasPersistence(), libraryStore: SessionLibraryStore = SessionLibraryStore()) {
        self.speakerAliasPersistence = aliasPersistence
        self.speakerAliasesText = aliasPersistence.loadText()
        self.libraryStore = libraryStore
        self.librarySessions = libraryStore.load()
        reconcileStaleSessions()
    }

    @Published var isRunning = false
    @Published var currentProcessingPath: String?
    @Published var lastProgressLine: String = ""
    @Published var processTask: (any ProcessRunningTask)?
    @Published var currentConfigPath: String?
    @Published private(set) var lastBatchResult: BatchResult?
    let processRunner = ProcessRunner()
    private let batchResultAccumulator = BatchResultAccumulator()
    @Published var isFileDropTargeted = false

    @Published var appAudioCapture = AppAudioCaptureController()
    @Published var captureApps: [CaptureAppTarget] = []
    @Published var selectedCaptureAppID: CaptureAppTarget.ID?
    @Published var isRefreshingCaptureApps = false
    @Published var captureMicrophone: Bool = true
    @Published var microphoneDevices: [MicrophoneDeviceTarget] = []
    @Published var selectedMicrophoneID: MicrophoneDeviceTarget.ID?

    @Published var liveAppCapture = LiveAppAudioSegmentController()
    @Published private(set) var liveTranscript = ""
    @Published private(set) var isLiveTranscribing = false
    private var liveTranscriptAccumulator = LiveTranscriptAccumulator()
    private var liveTranscriptionWorker = LiveTranscriptionWorker()
    private var liveExportBaseURL: URL?

    // Dependencies & models
    @Published var ffmpegStatus: DependencyStatus = .unknown
    @Published var pythonStatus: DependencyStatus = .unknown
    @Published var modelDownloadStatus: [String: DependencyStatus] = [:]
    @Published var isInstallingFFmpeg = false
    @Published var isSettingUpPython = false
    @Published var isDownloadingModel = false

    var profiles: [TranscriptionProfile] {
        [
            TranscriptionProfile(
                id: "fast-parakeet-v3",
                title: "fast — Parakeet v3",
                runtime: "mlx_audio_cli",
                model: "mlx-community/parakeet-tdt-0.6b-v3",
                language: "ru",
                chunkDuration: "30",
                details: "Default fast MLX STT: NVIDIA Parakeet TDT 0.6B v3 via mlx-audio."
            ),
            TranscriptionProfile(
                id: "fast-whisper-turbo",
                title: "fast — Whisper Turbo",
                runtime: "mlx_whisper",
                model: "mlx-community/whisper-large-v3-turbo",
                language: "ru",
                chunkDuration: "30",
                details: "Fast Whisper-compatible profile via mlx-whisper."
            ),
            TranscriptionProfile(
                id: "accurate-whisper-large-v3",
                title: "accurate — Whisper large-v3",
                runtime: "mlx_whisper",
                model: "mlx-community/whisper-large-v3-mlx",
                language: "ru",
                chunkDuration: "30",
                details: "Well-tested universal baseline for quality and challenging audio."
            ),
            TranscriptionProfile(
                id: "multilingual-canary-v2",
                title: "multilingual European — Canary 1B v2",
                runtime: "mlx_audio_cli",
                model: "CogniSoftOrg/canary-1b-v2-mlx-bf16",
                language: "ru",
                chunkDuration: "30",
                details: "Canary 1B v2 for 25 European languages; ASR/translation via mlx-audio."
            ),
            TranscriptionProfile(
                id: "realtime-voxtral-mini",
                title: "realtime — Voxtral Mini Realtime",
                runtime: "mlx_audio_cli",
                model: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit",
                language: "ru",
                chunkDuration: "30",
                details: "Streaming/realtime-oriented model; runs on files via mlx-audio in batch mode."
            )
        ]
    }

    var selectedProfile: TranscriptionProfile {
        profiles.first(where: { $0.id == selectedProfileID }) ?? profiles[0]
    }

    var selectedCaptureApp: CaptureAppTarget? {
        guard let selectedCaptureAppID else { return nil }
        return captureApps.first(where: { $0.id == selectedCaptureAppID })
    }

    var selectedMicrophone: MicrophoneDeviceTarget? {
        guard let selectedMicrophoneID else { return nil }
        return microphoneDevices.first(where: { $0.id == selectedMicrophoneID })
    }

    @MainActor
    func refreshMicrophones() {
        let devices = AppAudioCaptureController.loadMicrophones()
        microphoneDevices = devices
        if let selectedMicrophoneID, !devices.contains(where: { $0.id == selectedMicrophoneID }) {
            self.selectedMicrophoneID = nil
        }
        logs += "Stage: microphones found: \(devices.count)"
        if let selectedMicrophone {
            logs += "; selected=\(selectedMicrophone.title)"
        } else {
            logs += "; selected=system default"
        }
        logs += "\n"
    }

    func refreshCaptureApps() {
        guard !isRefreshingCaptureApps else { return }
        isRefreshingCaptureApps = true
        logs += "Stage: refresh ScreenCaptureKit application list...\n"
        Task {
            do {
                let apps = try await AppAudioCaptureController.loadShareableApplications()
                await MainActor.run {
                    self.captureApps = apps
                    if let selectedCaptureAppID, !apps.contains(where: { $0.id == selectedCaptureAppID }) {
                        self.selectedCaptureAppID = nil
                    }
                    if self.selectedCaptureAppID == nil {
                        self.selectedCaptureAppID = apps.first?.id
                    }
                    self.logs += "Stage: ScreenCaptureKit apps found: \(apps.count)\n"
                    self.isRefreshingCaptureApps = false
                }
            } catch {
                await MainActor.run {
                    self.logs += "❌ Cannot refresh app list: \(error.localizedDescription)\n"
                    self.logs += "⚠️ Check System Settings → Privacy & Security → Screen Recording for Canary Transcriber.\n"
                    self.isRefreshingCaptureApps = false
                }
            }
        }
    }

    func startAppAudioCapture(withMic: Bool = true) {
        guard let target = selectedCaptureApp else {
            logs += "⚠️ Select an application first.\n"
            return
        }
        let captureDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/CanaryTranscripts/AppAudioCaptures", isDirectory: true)
        captureMicrophone = withMic
        let micLabel = captureMicrophone ? (selectedMicrophone?.title ?? "system default") : "off"
        logs += "Stage: start app audio capture for \(target.title); microphone=\(micLabel)\n"
        Task {
            await appAudioCapture.start(target: target, includeMicrophone: captureMicrophone, microphoneDeviceID: selectedMicrophoneID, outputDirectory: captureDir, onLog: { text in
                DispatchQueue.main.async {
                    self.logs += text
                    self.appendPersistentLog(text)
                }
            }, onFinished: { result in
                switch result {
                case .success(let url):
                    self.logs += "✅ App audio recording saved: \(url.path)\n"
                    self.appendPersistentLog("✅ App audio recording saved: \(url.path)\n")
                    self.addAudioPaths([url.path], source: "app audio capture")
                case .failure(let error):
                    self.logs += "❌ App audio recording failed: \(error.localizedDescription)\n"
                    self.appendPersistentLog("❌ App audio recording failed: \(error.localizedDescription)\n")
                }
            })
        }
    }

    func stopAppAudioCapture() {
        appAudioCapture.stop()
    }

    func startLiveCapture() {
        guard let target = selectedCaptureApp else {
            logs += "⚠️ Select an application first.\n"
            return
        }
        guard !liveAppCapture.isCapturing, !liveAppCapture.isFinishing else { return }
        let outputDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/CanaryTranscripts/LiveCaptures", isDirectory: true)
        let config = LiveCaptureConfig(
            windowDuration: 5,
            overlapDuration: 0,
            profileID: selectedProfileID,
            runtime: runtime,
            model: model,
            language: language,
            includeMicrophone: captureMicrophone,
            outputDirectory: outputDirectory.path
        )
        do {
            _ = try config.validated()
        } catch {
            logs += "❌ Invalid Live Capture configuration: \(error.localizedDescription)\n"
            return
        }

        liveTranscriptAccumulator = LiveTranscriptAccumulator()
        liveTranscript = ""
        liveExportBaseURL = outputDirectory.appendingPathComponent("live-\(Int(Date().timeIntervalSince1970)).canary")
        liveTranscriptionWorker.stop()
        liveTranscriptionWorker = LiveTranscriptionWorker()
        isLiveTranscribing = true
        logs += "Stage: starting Live Capture with 5-second segments.\n"

        Task {
            await liveAppCapture.start(
                target: target,
                segmentDuration: config.windowDuration,
                includeMicrophone: config.includeMicrophone,
                microphoneDeviceID: selectedMicrophoneID,
                outputDirectory: outputDirectory,
                onLog: { [weak self] text in
                    DispatchQueue.main.async {
                        self?.logs += text
                        self?.appendPersistentLog(text)
                    }
                },
                onSegmentReady: { [weak self] index, url, duration in
                    guard let self else { return }
                    let start = Double(index) * config.windowDuration
                    self.logs += "Stage: transcribing live segment \(index + 1)\n"
                    self.liveTranscriptionWorker.submit(
                        segmentURL: url,
                        index: index,
                        start: start,
                        end: start + max(0, duration),
                        config: config
                    ) { [weak self] result in
                        guard let self else { return }
                        switch result {
                        case .success(let segment):
                            if self.liveTranscriptAccumulator.append(segment) {
                                self.liveTranscript = self.liveTranscriptAccumulator.renderTimestamped()
                                self.persistLiveTranscript(config: config)
                            }
                        case .failure(let error):
                            self.logs += "⚠️ Live segment transcription failed: \(error.localizedDescription)\n"
                        }
                    }
                },
                onFinished: { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.isLiveTranscribing = false
                        switch result {
                        case .success:
                            self.logs += "Live Capture stopped.\n"
                        case .failure(let error):
                            self.logs += "❌ Live Capture failed: \(error.localizedDescription)\n"
                        }
                    }
                }
            )
        }
    }

    private func persistLiveTranscript(config: LiveCaptureConfig) {
        guard let base = liveExportBaseURL, !liveTranscriptAccumulator.segments.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
            let textURL = base.appendingPathExtension("txt")
            let jsonURL = base.appendingPathExtension("json")
            let markdownURL = base.appendingPathExtension("md")
            try liveTranscriptAccumulator.renderTimestamped().write(to: textURL, atomically: true, encoding: .utf8)
            let payload: [String: Any] = [
                "live_capture": true,
                "profile": config.profileID,
                "runtime": config.runtime,
                "model": config.model,
                "language": config.language,
                "include_microphone": config.includeMicrophone,
                "segments": liveTranscriptAccumulator.segments.map {
                    ["index": $0.index, "start": $0.start, "end": $0.end, "text": $0.text]
                },
                "text": liveTranscriptAccumulator.text
            ]
            let json = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            try json.write(to: jsonURL, options: Data.WritingOptions.atomic)
            let frontMatter = TranscriptionFrontMatter(
                source: base.lastPathComponent,
                profile: config.profileID,
                runtime: config.runtime,
                model: config.model,
                language: config.language,
                date: ISO8601DateFormatter().string(from: Date())
            ).render()
            let markdown = frontMatter + "\n# Live Transcript\n\n" + liveTranscriptAccumulator.renderTimestamped() + "\n"
            try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
        } catch {
            logs += "⚠️ Could not persist live transcript: \(error.localizedDescription)\n"
        }
    }

    func stopLiveCapture() {
        liveAppCapture.stop()
        liveTranscriptionWorker.stop()
        isLiveTranscribing = false
    }

    func applySelectedProfile() {
        let profile = selectedProfile
        runtime = profile.runtime
        model = profile.model
        language = profile.language
        chunkDuration = profile.chunkDuration
        logs += "Profile selected: \(profile.title) → runtime=\(profile.runtime), model=\(profile.model)\n"
    }

    func parsedSpeakerAliases() -> [String: String] {
        parseSpeakerAliasesText(speakerAliasesText)
    }

    func chooseAudioFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = []
        panel.message = "Select audio/video files for Canary Transcriber"
        if panel.runModal() == .OK {
            let newPaths = panel.urls.map { normalizeUserPath($0.standardizedFileURL.path) }
            addAudioPaths(newPaths, source: "picker")
        }
    }

    func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard !isRunning else {
            logs += "⚠️ Cannot add files during transcription.\n"
            return false
        }

        let fileURLType = UTType.fileURL.identifier
        let matchingProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(fileURLType) }
        guard !matchingProviders.isEmpty else { return false }

        for provider in matchingProviders {
            provider.loadItem(forTypeIdentifier: fileURLType, options: nil) { item, error in
                if let error {
                    DispatchQueue.main.async {
                        self.logs += "⚠️ Drop error: \(error.localizedDescription)\n"
                    }
                    return
                }

                guard let path = self.decodeDroppedFilePath(item) else {
                    DispatchQueue.main.async {
                        self.logs += "⚠️ Drop: could not read file URL.\n"
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.addAudioPaths([path], source: "drag&drop")
                }
            }
        }
        return true
    }

    func decodeDroppedFilePath(_ item: NSSecureCoding?) -> String? {
        if let url = item as? URL {
            return normalizeUserPath(url.standardizedFileURL.path)
        }
        if let data = item as? Data,
           let raw = String(data: data, encoding: .utf8),
           let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return normalizeUserPath(url.standardizedFileURL.path)
        }
        if let string = item as? String,
           let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return normalizeUserPath(url.standardizedFileURL.path)
        }
        return nil
    }

    func addAudioPaths(_ rawPaths: [String], source: String) {
        let fm = FileManager.default
        let existing = Set(files.map { $0.path })
        var additions: [AudioFileItem] = []
        var skippedDirectories = 0
        var skippedDuplicates = 0

        for rawPath in rawPaths {
            let path = normalizeUserPath(rawPath)
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                skippedDirectories += 1
                continue
            }
            if existing.contains(path) || additions.contains(where: { $0.path == path }) {
                skippedDuplicates += 1
                continue
            }
            additions.append(AudioFileItem(path: path))
        }

        if !additions.isEmpty {
            files.append(contentsOf: additions)
            for item in additions { queueSession(for: item.path) }
        }
        logs += "Added files (\(source)): \(additions.count)"
        if skippedDuplicates > 0 { logs += ", duplicates skipped: \(skippedDuplicates)" }
        if skippedDirectories > 0 { logs += ", directories skipped: \(skippedDirectories)" }
        logs += "\n"
    }

    func choosePython() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        if panel.runModal() == .OK, let url = panel.url {
            pythonPath = normalizeUserPath(url.standardizedFileURL.path)
        }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = normalizeUserPath(url.standardizedFileURL.path)
        }
    }

    func chooseMarkdownOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            markdownOutputFolder = normalizeUserPath(url.standardizedFileURL.path)
        }
    }

    func removeSelectedFile() {
        guard let selectedFileID else { return }
        files.removeAll { $0.id == selectedFileID }
        self.selectedFileID = nil
    }

    func startBatch() {
        guard !isRunning else { return }

        let cleanPython = normalizeUserPath(pythonPath)
        pythonPath = cleanPython
        guard FileManager.default.isExecutableFile(atPath: cleanPython) else {
            logs += "❌ Python is not executable: \(cleanPython)\n"
            logs += "   Set the Python venv path, e.g. ~/venvs/canary-mlx/bin/python\n"
            return
        }

        let normalizedFiles = files.map { item in
            AudioFileItem(path: normalizeUserPath(item.path), status: "queued")
        }
        files = normalizedFiles
        let missing = normalizedFiles.filter { !FileManager.default.fileExists(atPath: $0.path) }
        if !missing.isEmpty {
            logs += "❌ Files not found:\n"
            for item in missing { logs += "   \(item.path)\n" }
            return
        }

        let cleanOutput = normalizeUserPath(outputFolder)
        outputFolder = cleanOutput
        if !writeNextToSource {
            do {
                try FileManager.default.createDirectory(atPath: cleanOutput, withIntermediateDirectories: true)
            } catch {
                logs += "❌ Cannot create output folder: \(error.localizedDescription)\n"
                return
            }
        }

        var cleanMarkdownOutput: String?
        if separateMarkdownOutput {
            let markdownDir = normalizeUserPath(markdownOutputFolder)
            markdownOutputFolder = markdownDir
            do {
                try FileManager.default.createDirectory(atPath: markdownDir, withIntermediateDirectories: true)
            } catch {
                logs += "❌ Cannot create markdown output folder: \(error.localizedDescription)\n"
                return
            }
            cleanMarkdownOutput = markdownDir
        }

        let chunk = Double(chunkDuration.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30.0
        let speakerCountText = diarizationSpeakerCount.trimmingCharacters(in: .whitespacesAndNewlines)
        let forcedSpeakerCount = Int(speakerCountText).flatMap { $0 > 0 ? $0 : nil }
        let config = BatchConfig(
            files: normalizedFiles.map { $0.path },
            outputDir: writeNextToSource ? nil : cleanOutput,
            markdownOutputDir: cleanMarkdownOutput,
            writeNextToSource: writeNextToSource,
            profileID: selectedProfileID,
            runtime: runtime,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedProfile.model : model.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedProfile.language : language.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamps: timestamps,
            chunkDuration: chunk <= 0 ? nil : chunk,
            overlapDuration: chunk <= 0 ? 0 : 2.0,
            diarization: diarizationEnabled,
            speakerCount: diarizationEnabled ? forcedSpeakerCount : nil,
            speakerAliases: diarizationEnabled ? parsedSpeakerAliases() : [:]
        )
        do {
            _ = try config.validated()
        } catch {
            logs += "❌ Invalid transcription configuration: \(error.localizedDescription)\n"
            return
        }

        refreshQueuedSessions(for: config)

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("canary-transcriber-\(UUID().uuidString).json")
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL)
            currentConfigPath = configURL.path
        } catch {
            logs += "❌ Cannot write temp config: \(error.localizedDescription)\n"
            return
        }

        batchResultAccumulator.start(paths: config.files)
        lastBatchResult = nil
        runPython(configURL: configURL, pythonPath: cleanPython, config: config)
    }

    func runPython(configURL: URL, pythonPath: String, config: BatchConfig) {
        let script = #"""
import json
import shutil
import subprocess
import sys
import tempfile
import traceback
import wave
from datetime import datetime
from pathlib import Path

FFMPEG_TIMEOUT_SECONDS = 600
FFMPEG_CHUNK_TIMEOUT_SECONDS = 180

try:
    cfg = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    files = [Path(p).expanduser() for p in cfg["files"]]
    output_dir = Path(cfg["outputDir"]).expanduser() if cfg.get("outputDir") else None
    markdown_output_dir = Path(cfg["markdownOutputDir"]).expanduser() if cfg.get("markdownOutputDir") else None
    write_next_to_source = bool(cfg.get("writeNextToSource", True))
    model_id = cfg.get("model") or "qfuxa/canary-mlx"
    runtime = cfg.get("runtime") or "canary_mlx"
    profile_id = cfg.get("profileID") or "custom"
    language = cfg.get("language") or "ru"
    timestamps = bool(cfg.get("timestamps", False))
    chunk_duration = cfg.get("chunkDuration", 30.0)
    overlap_duration = float(cfg.get("overlapDuration", 2.0))
    diarization_enabled = bool(cfg.get("diarization", False))
    speaker_count = cfg.get("speakerCount")
    try:
        speaker_count = int(speaker_count) if speaker_count else None
    except Exception:
        speaker_count = None
    speaker_aliases = cfg.get("speakerAliases") or {}
    if not isinstance(speaker_aliases, dict):
        speaker_aliases = {}
    speaker_aliases = {str(k): str(v).strip() for k, v in speaker_aliases.items() if str(k).strip() and str(v).strip()}

    def emit(kind, **payload):
        payload["kind"] = kind
        print("CANARY_EVENT " + json.dumps(payload, ensure_ascii=False, default=str), flush=True)

    # Test-only protocol fixture mode. It executes this embedded script's real
    # event emitter without importing an STT runtime or touching audio files.
    if cfg.get("_eventFixtures") is not None:
        for fixture in cfg.get("_eventFixtures") or []:
            fixture = dict(fixture)
            kind = str(fixture.pop("kind"))
            emit(kind, **fixture)
        raise SystemExit(0)

    def output_paths(audio_path):
        base_dir = audio_path.parent if write_next_to_source else output_dir
        base_dir.mkdir(parents=True, exist_ok=True)
        stem = audio_path.stem
        md_dir = markdown_output_dir if markdown_output_dir is not None else base_dir
        md_dir.mkdir(parents=True, exist_ok=True)
        return base_dir / f"{stem}.canary.txt", base_dir / f"{stem}.canary.json", md_dir / f"{stem}.canary.md"

    def resolve_ffmpeg():
        candidates = [
            shutil.which("ffmpeg"),
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
        ]
        for c in candidates:
            if c and Path(c).exists():
                return c
        raise RuntimeError("ffmpeg not found. Install with: brew install ffmpeg")

    def wav_duration_seconds(path):
        with wave.open(str(path), "rb") as wf:
            frames = wf.getnframes()
            rate = wf.getframerate()
            return frames / float(rate)

    def make_wav_chunks(audio_path, work_dir, seconds):
        ffmpeg = resolve_ffmpeg()
        normalized = work_dir / "normalized.wav"
        print(f"Stage: ffmpeg normalize -> {normalized}", flush=True)
        subprocess.run([
            ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
            "-i", str(audio_path),
            "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
            str(normalized),
        ], check=True, timeout=FFMPEG_TIMEOUT_SECONDS, stdin=subprocess.DEVNULL)

        duration = wav_duration_seconds(normalized)
        # nil chunkDuration explicitly disables fixed chunking: transcribe the
        # normalized file once. overlapDuration is only meaningful with fixed
        # chunking and is rejected at the Swift boundary when chunking is nil.
        if seconds is None:
            print(f"Stage: fixed chunking disabled; using full normalized audio ({duration:.1f}s)", flush=True)
            return [(0, 0.0, normalized)], duration, duration
        chunk_seconds = float(seconds)
        if chunk_seconds <= 0:
            raise ValueError("chunk duration must be positive or null")
        chunks = []
        start = 0.0
        idx = 0
        while start < duration:
            out = work_dir / f"chunk_{idx:04d}.wav"
            subprocess.run([
                ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
                "-ss", f"{start:.3f}", "-i", str(normalized),
                "-t", f"{chunk_seconds:.3f}",
                "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
                str(out),
            ], check=True, timeout=FFMPEG_CHUNK_TIMEOUT_SECONDS, stdin=subprocess.DEVNULL)
            if out.exists() and out.stat().st_size > 44:
                chunks.append((idx, start, out))
            idx += 1
            step = chunk_seconds - overlap_duration
            if step <= 0:
                raise ValueError("overlap duration must be smaller than chunk duration")
            start += step
        print(f"Stage: prepared {len(chunks)} wav chunks; duration={duration:.1f}s chunk={chunk_seconds:.1f}s", flush=True)
        return chunks, duration, chunk_seconds

    def make_transcriber(runtime_name, model_name):
        print(f"Stage: runtime preflight profile={profile_id} runtime={runtime_name} model={model_name}", flush=True)
        if runtime_name == "canary_mlx":
            try:
                from canary_mlx import load_model
            except Exception as exc:
                raise RuntimeError("Python package canary-mlx is required for runtime=canary_mlx. Install: python -m pip install canary-mlx") from exc
            print(f"Stage: load_model({model_name})", flush=True)
            model_obj = load_model(model_name)
            print("Stage: model loaded", flush=True)
            def transcribe(path):
                try:
                    result = model_obj.transcribe(str(path), language=language, timestamps=timestamps)
                    return result.text if hasattr(result, "text") else str(result)
                finally:
                    import mlx.core as mx
                    mx.clear_cache()
            return transcribe

        if runtime_name == "mlx_whisper":
            try:
                import mlx_whisper
            except Exception as exc:
                raise RuntimeError("Python package mlx-whisper is required for Whisper profiles. Install: python -m pip install mlx-whisper") from exc
            print("Stage: mlx_whisper ready", flush=True)
            def transcribe(path):
                kwargs = {"path_or_hf_repo": model_name}
                if language:
                    kwargs["language"] = language
                try:
                    try:
                        result = mlx_whisper.transcribe(str(path), **kwargs)
                    except TypeError:
                        kwargs.pop("language", None)
                        result = mlx_whisper.transcribe(str(path), **kwargs)
                finally:
                    import mlx.core as mx
                    mx.clear_cache()
                if isinstance(result, dict):
                    return str(result.get("text", ""))
                return result.text if hasattr(result, "text") else str(result)
            return transcribe

        if runtime_name == "mlx_audio_cli":
            try:
                import mlx.core as mx
                from mlx_audio.stt.generate import generate_transcription
                from mlx_audio.stt.utils import load_model as load_stt_model
            except Exception as exc:
                raise RuntimeError("Python package mlx-audio is required for Parakeet/Canary v2/Voxtral profiles. Install: python -m pip install 'mlx-audio[stt]' or python -m pip install mlx-audio") from exc
            print(f"Stage: load_model({model_name}) via mlx-audio", flush=True)
            model_obj = load_stt_model(model_name)
            print("Stage: mlx-audio model loaded", flush=True)

            def transcribe(path):
                with tempfile.TemporaryDirectory(prefix="mlx-audio-out-") as out_tmp:
                    out_stub = str(Path(out_tmp) / "transcript")
                    kwargs = {}
                    if language:
                        kwargs["language"] = language
                        kwargs["gen_kwargs"] = {"source_lang": language, "target_lang": language}
                    try:
                        segments = generate_transcription(
                            model=model_obj,
                            audio=str(path),
                            output_path=out_stub,
                            format="txt",
                            **kwargs,
                        )
                    finally:
                        mx.clear_cache()
                    text = getattr(segments, "text", None)
                    if text is None:
                        raise RuntimeError("mlx-audio returned no text for this segment.")
                    return text
            return transcribe

        raise RuntimeError(f"Unknown runtime: {runtime_name}. Supported: canary_mlx, mlx_whisper, mlx_audio_cli")

    def make_diarizer():
        emit("stage", name="diarization_model_loading")
        try:
            import torch, os
            from pyannote.audio import Pipeline
            token_file = os.path.expanduser("~/.cache/huggingface/token")
            if not os.path.exists(token_file):
                warning = "HuggingFace token not found; diarization disabled for this batch. Continuing speakerless."
                emit("warning", message=warning)
                print("WARNING: " + warning, flush=True)
                return None
            token = open(token_file).read().strip()
            if not token:
                warning = "HuggingFace token is empty; diarization disabled for this batch. Continuing speakerless."
                emit("warning", message=warning)
                print("WARNING: " + warning, flush=True)
                return None
            print("Stage: loading pyannote/speaker-diarization-3.1...", flush=True)
            pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1", token=token)
            if torch.backends.mps.is_available():
                pipeline.to(torch.device("mps"))
                print("Stage: diarization pipeline on MPS", flush=True)
            else:
                print("Stage: diarization pipeline on CPU", flush=True)

            def diarize(wav_path):
                emit("stage", name="diarization_running")
                import torchaudio
                waveform, sr = torchaudio.load(wav_path)
                if waveform.shape[0] > 1:
                    waveform = waveform.mean(dim=0, keepdim=True)
                if waveform.shape[-1] < sr * 10:
                    warning = "Audio is shorter than 10 seconds; skipping diarization and continuing speakerless."
                    emit("warning", message=warning)
                    return []
                kwargs = {"waveform": waveform, "sample_rate": sr}
                if speaker_count:
                    print(f"Stage: diarization forced speakers={speaker_count}", flush=True)
                    result = pipeline(kwargs, num_speakers=speaker_count)
                else:
                    result = pipeline(kwargs)
                segments = []
                for segment, _, label in result.speaker_diarization.itertracks(yield_label=True):
                    segments.append({"speaker": label, "start": round(segment.start, 3), "end": round(segment.end, 3)})
                emit("stage", name="diarization_completed", segments=len(segments))
                if torch.backends.mps.is_available():
                    torch.mps.empty_cache()
                return segments

            return diarize
        except Exception as exc:
            warning = f"Diarization initialization failed ({exc}); continuing speakerless."
            emit("warning", message=warning)
            print("WARNING: " + warning, flush=True)
            return None

    def extract_wav_segment(source_wav, output_wav, start, end):
        ffmpeg = resolve_ffmpeg()
        duration = max(0.0, float(end) - float(start))
        subprocess.run([
            ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
            "-ss", f"{float(start):.3f}", "-i", str(source_wav),
            "-t", f"{duration:.3f}",
            "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
            str(output_wav),
        ], check=True, timeout=FFMPEG_CHUNK_TIMEOUT_SECONDS, stdin=subprocess.DEVNULL)
        return output_wav

    def merge_speaker_segments(segments, max_seconds, min_seconds=0.6, max_gap=0.8):
        if not segments:
            return []
        max_seconds = float(max_seconds or 30.0)
        merged = []
        for seg in sorted(segments, key=lambda s: (s["start"], s["end"])):
            start = float(seg["start"])
            end = float(seg["end"])
            if end - start < min_seconds:
                continue
            speaker = seg["speaker"]
            if merged and merged[-1]["speaker"] == speaker:
                gap = start - float(merged[-1]["end"])
                candidate_duration = end - float(merged[-1]["start"])
                if 0 <= gap <= max_gap and candidate_duration <= max_seconds:
                    merged[-1]["end"] = round(end, 3)
                    continue
            # Split very long same-speaker regions so ASR still works like normal chunks.
            cur = start
            while end - cur > max_seconds:
                merged.append({"speaker": speaker, "start": round(cur, 3), "end": round(cur + max_seconds, 3)})
                cur += max_seconds
            if end - cur >= min_seconds:
                merged.append({"speaker": speaker, "start": round(cur, 3), "end": round(end, 3)})
        return merged

    def summarize_speakers(diarize_segments, transcription_segments):
        summary = {}
        for seg in diarize_segments or []:
            speaker = str(seg.get("speaker") or "SPEAKER_UNKNOWN")
            start = float(seg.get("start", 0.0))
            end = float(seg.get("end", start))
            row = summary.setdefault(speaker, {"speaker": speaker, "segments": 0, "seconds": 0.0, "chars": 0, "alias": ""})
            row["segments"] += 1
            row["seconds"] += max(0.0, end - start)

        for seg in transcription_segments or []:
            speaker = str(seg.get("speaker") or "SPEAKER_UNKNOWN")
            text = str(seg.get("text") or "")
            row = summary.setdefault(speaker, {"speaker": speaker, "segments": 0, "seconds": 0.0, "chars": 0, "alias": ""})
            row["chars"] += len(text.strip())

        rows = sorted(summary.values(), key=lambda row: (-row["seconds"], row["speaker"]))
        for row in rows:
            row["seconds"] = round(row["seconds"], 3)
            row["alias"] = speaker_aliases.get(row["speaker"], "")
        return rows

    def yaml_scalar(value):
        value = str(value)
        if value and all(ch.isalnum() or ch in "-_.:/" for ch in value):
            return value
        return json.dumps(value, ensure_ascii=False)

    def markdown_inline(value):
        value = str(value).replace("\\", "\\\\")
        for char in ["`", "*", "_", "[", "]", "|"]:
            value = value.replace(char, "\\" + char)
        return value.replace("\r\n", "\n").replace("\r", "\n").replace("\n", " ")

    def markdown_text(value):
        lines = str(value).replace("\r\n", "\n").replace("\r", "\n").split("\n")
        return "  \n".join(markdown_inline(line) for line in lines)

    def markdown_cell(value):
        return markdown_inline(value)

    def format_hms(seconds):
        total = max(0, int(float(seconds or 0)))
        return f"{total // 3600:02d}:{(total % 3600) // 60:02d}:{total % 60:02d}"

    def build_markdown(audio_path, text, profile_id, runtime, model_id, language, diarization_enabled, diarize_segments, transcription_segments, speaker_summary, speaker_count):
        md_fields = [
            f"source: {yaml_scalar(audio_path.name)}",
            f"profile: {yaml_scalar(profile_id)}",
            f"runtime: {yaml_scalar(runtime)}",
            f"model: {yaml_scalar(model_id)}",
            f"language: {yaml_scalar(language)}",
            f"date: {datetime.now().isoformat()}",
        ]

        if diarization_enabled and diarize_segments is not None:
            md_fields.append("diarization: pyannote/speaker-diarization-3.1")
            if speaker_count:
                md_fields.append(f"speaker_count: {speaker_count}")
            md_fields.append(f"speakers: {len(speaker_summary)}")
            md_fields.append(f"diarization_segments: {len(diarize_segments)}")

        workspace_enabled = bool(diarization_enabled and diarize_segments is not None and speaker_summary and transcription_segments)
        if workspace_enabled:
            md_fields.append("meeting_workspace: true")

        md_content = "---\n" + "\n".join(md_fields) + "\n---\n\n"

        if workspace_enabled:
            md_content += f"# Transcript: {markdown_inline(audio_path.name)}\n\n"
            md_content += "## Speakers\n\n"
            md_content += "| Speaker | Segments | Duration | Alias |\n|---|---:|---:|---|\n"
            for row in speaker_summary:
                alias = str(row.get("alias") or "")
                display_speaker = f"{alias} ({row['speaker']})" if alias else row["speaker"]
                md_content += f"| {markdown_cell(display_speaker)} | {row['segments']} | {format_hms(row['seconds'])} | {markdown_cell(alias)} |\n"

            md_content += "\n## Transcript\n\n"
            transcript_lines = []
            for seg in transcription_segments or []:
                speaker = str(seg.get("speaker") or "SPEAKER_UNKNOWN")
                start = float(seg.get("start", 0.0))
                end = float(seg.get("end", start))
                seg_text = str(seg.get("text") or "").strip()
                if not seg_text:
                    continue
                display_speaker = speaker_aliases.get(speaker, speaker)
                if display_speaker == speaker:
                    transcript_lines.append(f"**{markdown_inline(speaker)}** [{format_hms(start)} - {format_hms(end)}]: {markdown_text(seg_text)}")
                else:
                    transcript_lines.append(f"**{markdown_inline(display_speaker + ' (' + speaker + ')')}** [{format_hms(start)} - {format_hms(end)}]: {markdown_text(seg_text)}")

            if transcript_lines:
                md_content += "\n\n".join(transcript_lines) + "\n\n"
            elif text.strip():
                # Fallback: preserve the actual transcript even when diarization segments
                # don't carry per-segment text. This avoids empty .md exports.
                md_content += markdown_text(text.strip()) + "\n\n"

            md_content += "## Summary\n\n- \n\n## Decisions\n\n- \n\n## Action items\n\n- [ ] \n\n## Open questions\n\n- \n"
        else:
            md_content += f"# Transcript: {markdown_inline(audio_path.name)}\n\n{markdown_text(text)}\n"

        return md_content

    print(f"Stage: STT preflight; files={len(files)} profile={profile_id} runtime={runtime}", flush=True)
    for p in files:
        if not p.exists():
            raise FileNotFoundError(f"audio file not found: {p}")
    if output_dir is not None:
        output_dir.mkdir(parents=True, exist_ok=True)

    transcribe_chunk = make_transcriber(runtime, model_id)
    diarize_func = make_diarizer() if diarization_enabled else None

    def is_memory_failure(error):
        message = str(error).lower()
        return "insufficient memory" in message or "outofmemory" in message or "out of memory" in message

    def transcribe_with_bounded_retry(path, start, end, work_dir, label):
        try:
            return transcribe_chunk(path).strip()
        except RuntimeError as error:
            duration = max(0.0, float(end) - float(start))
            if not is_memory_failure(error) or duration <= 5.0:
                raise
            midpoint = start + duration / 2.0
            print(f"WARNING: MLX memory failure for {label}; retrying as two smaller chunks ({duration:.1f}s -> {duration / 2.0:.1f}s)", flush=True)
            try:
                import mlx.core as mx
                mx.clear_cache()
            except Exception:
                pass
            retry_text = []
            for retry_index, (retry_start, retry_end) in enumerate(((start, midpoint), (midpoint, end))):
                retry_path = Path(work_dir) / f"{label}_retry_{retry_index:02d}.wav"
                subprocess.run([
                    ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
                    "-ss", str(retry_start), "-t", str(max(0.01, retry_end - retry_start)),
                    "-i", str(Path(work_dir) / "normalized.wav"),
                    "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(retry_path)
                ], check=True, timeout=FFMPEG_CHUNK_TIMEOUT_SECONDS, stdin=subprocess.DEVNULL)
                retry_text.append(transcribe_chunk(retry_path).strip())
            return "\n".join(text for text in retry_text if text).strip()

    ok = 0
    failed = 0
    for index, audio_path in enumerate(files, 1):
        emit("file_started", path=str(audio_path), index=index, total=len(files))
        print(f"Stage: transcribe [{index}/{len(files)}] {audio_path}", flush=True)
        txt_path, json_path, md_path = output_paths(audio_path)
        try:
            parts = []
            chunk_records = []
            diarize_segments = None
            transcription_segments = None
            with tempfile.TemporaryDirectory(prefix="canary-transcriber-") as tmp:
                chunks, duration, effective_chunk = make_wav_chunks(audio_path, Path(tmp), chunk_duration)
                normalized = Path(tmp) / "normalized.wav"

                # Run diarization on normalized WAV (created by make_wav_chunks)
                if diarize_func:
                    emit("stage", name="diarization_running", file=str(audio_path))
                    try:
                        diarize_segments = diarize_func(normalized)
                        print(f"Stage: diarization found {len(diarize_segments)} speaker segments", flush=True)
                        for seg in diarize_segments:
                            print(f"  {seg['speaker']}: {seg['start']:.1f}s - {seg['end']:.1f}s", flush=True)
                        transcription_segments = merge_speaker_segments(diarize_segments, effective_chunk)
                        print(f"Stage: merged into {len(transcription_segments)} speaker transcription segments", flush=True)
                    except Exception as exc:
                        warning = f"Diarization failed for {audio_path.name} ({exc}); continuing speakerless."
                        emit("warning", message=warning)
                        print("WARNING: " + warning, flush=True)
                        diarize_segments = None
                        transcription_segments = None

                if transcription_segments:
                    emit("stage", name="speaker_segment_transcription", file=str(audio_path), total=len(transcription_segments))
                    for segment_index, seg in enumerate(transcription_segments):
                        speaker_label = seg["speaker"]
                        segment_start = float(seg["start"])
                        segment_end = float(seg["end"])
                        segment_path = Path(tmp) / f"speaker_segment_{segment_index:04d}.wav"
                        extract_wav_segment(normalized, segment_path, segment_start, segment_end)
                        print(f"Stage: STT speaker segment {segment_index + 1}/{len(transcription_segments)} speaker={speaker_label} start={segment_start:.1f}s end={segment_end:.1f}s runtime={runtime}", flush=True)
                        segment_text = transcribe_with_bounded_retry(segment_path, segment_start, segment_end, tmp, f"speaker_segment_{segment_index:04d}")
                        if segment_text:
                            parts.append(f"[{speaker_label}]: {segment_text}")
                        chunk_records.append({
                            "index": segment_index,
                            "start": segment_start,
                            "end": segment_end,
                            "path": str(segment_path.name),
                            "speaker": speaker_label,
                            "chars": len(segment_text),
                            "text": segment_text,
                        })
                else:
                    for chunk_index, chunk_start, chunk_path in chunks:
                        print(f"Stage: STT chunk {chunk_index + 1}/{len(chunks)} start={chunk_start:.1f}s runtime={runtime}", flush=True)
                        chunk_text = transcribe_with_bounded_retry(chunk_path, chunk_start, min(chunk_start + effective_chunk, duration), tmp, f"chunk_{chunk_index:04d}")
                        if chunk_text:
                            parts.append(chunk_text)
                        chunk_records.append({
                            "index": chunk_index,
                            "start": chunk_start,
                            "end": min(chunk_start + effective_chunk, duration),
                            "path": str(chunk_path.name),
                            "speaker": None,
                            "chars": len(chunk_text),
                            "text": chunk_text,
                        })

            text = "\n".join(parts).strip()
            emit("stage", name="workspace_writing", file=str(audio_path))
            txt_path.write_text(text, encoding="utf-8")
            speaker_summary = summarize_speakers(diarize_segments, transcription_segments)
            md_content = build_markdown(audio_path, text, profile_id, runtime, model_id, language, diarization_enabled, diarize_segments, transcription_segments, speaker_summary, speaker_count)
            md_path.write_text(md_content, encoding="utf-8")
            payload = {
                "audio": str(audio_path),
                "profile": profile_id,
                "runtime": runtime,
                "model": model_id,
                "language": language,
                "timestamps": timestamps,
                "manual_chunking": chunk_duration is not None,
                "chunk_duration": chunk_duration,
                "overlap_duration": overlap_duration if chunk_duration is not None else 0,
                "diarization": diarization_enabled,
                "speaker_count": speaker_count,
                "meeting_workspace": bool(diarization_enabled and diarize_segments is not None and speaker_summary and transcription_segments),
                "text": text,
                "chunks": chunk_records,
            }
            if diarization_enabled and diarize_segments is not None:
                payload["diarization_segments"] = diarize_segments
                payload["transcription_segments"] = transcription_segments or []
                payload["speaker_summary"] = speaker_summary
                payload["speaker_aliases"] = {row["speaker"]: row.get("alias", "") for row in speaker_summary}
            json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
            ok += 1
            emit("file_done", path=str(audio_path), txt=str(txt_path), json=str(json_path), md=str(md_path), chars=len(text))
            print(f"Transcript saved: {txt_path} (chars={len(text)})", flush=True)
            if len(text.strip()) == 0:
                print("Warning: selected STT profile returned empty text for this file. Check runtime dependencies, language/audio format, or try another profile.", flush=True)
        except RuntimeError as e:
            msg = str(e)
            if "Insufficient Memory" in msg or "OutOfMemory" in msg or "out of memory" in msg.lower():
                msg = "MLX runtime ran out of Metal memory. Try smaller Chunk sec, e.g. 15 or 10. Original: " + msg
            failed += 1
            emit("file_failed", path=str(audio_path), error=msg)
            print(f"ERROR transcribing {audio_path}: {msg}", flush=True)
        except Exception as e:
            failed += 1
            emit("file_failed", path=str(audio_path), error=str(e))
            print(f"ERROR transcribing {audio_path}: {e}", flush=True)
            traceback.print_exc()

    emit("batch_done", ok=ok, failed=failed, total=len(files))
    print(f"Batch complete: ok={ok}, failed={failed}, total={len(files)}", flush=True)
    raise SystemExit(0 if failed == 0 else 2)
except KeyboardInterrupt:
    print("Interrupted", flush=True)
    raise
except Exception as e:
    print(f"FATAL: {e}", flush=True)
    traceback.print_exc()
    raise SystemExit(1)
"""#

        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        let guiSafePath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existingPath = env["PATH"], !existingPath.isEmpty {
            env["PATH"] = guiSafePath + ":" + existingPath
        } else {
            env["PATH"] = guiSafePath
        }

        let request = ProcessRequest(
            executablePath: pythonPath,
            arguments: ["-u", "-c", script, configURL.path],
            environment: env
        )

        let batchHeader = """

=== MLX batch transcription ===
Python: \(pythonPath)
Profile: \(config.profileID)
Runtime: \(config.runtime)
Model: \(config.model)
Language: \(config.language)
Chunk duration: \(config.chunkDuration.map { String($0) } ?? "off")
Diarization: \(config.diarization ? "yes (pyannote/speaker-diarization-3.1)" : "off")
Speakers: \(config.speakerCount.map { String($0) } ?? "auto")
Files: \(config.files.count)
Output: \(config.writeNextToSource ? "next to source files" : (config.outputDir ?? ""))
Markdown output: \(config.markdownOutputDir ?? "same as output")
PATH: \(env["PATH"] ?? "")
Persistent log: \(persistentLogPath())

"""
        logs += batchHeader
        appendPersistentLog(batchHeader)

        do {
            isRunning = true
            let task = try processRunner.start(
                request,
                onOutput: { event in
                    DispatchQueue.main.async {
                        self.appendProcessOutput(event.text)
                    }
                },
                onTermination: { finished in
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.processTask = nil
                        self.lastBatchResult = self.batchResultAccumulator.finish(
                            stopped: finished.terminationStatus == 15,
                            fallbackMessage: finished.terminationStatus == 15 ? "Batch stopped by user." : "No completion event was received for this file."
                        )
                        if let currentConfigPath = self.currentConfigPath {
                            try? FileManager.default.removeItem(atPath: currentConfigPath)
                            self.currentConfigPath = nil
                        }
                        if finished.terminationStatus == 0 {
                            self.logs += "\n✅ Batch completed successfully.\n"
                            self.appendPersistentLog("\n✅ Batch completed successfully.\n")
                        } else if finished.terminationStatus == 15 {
                            self.logs += "\n⏹️ Batch stopped by user.\n"
                            self.appendPersistentLog("\n⏹️ Batch stopped by user.\n")
                        } else {
                            let reason = String(describing: finished.terminationReason)
                            let message = "\n⚠️ Batch completed with errors (code \(finished.terminationStatus), reason \(reason)).\n"
                            self.logs += message
                            self.appendPersistentLog(message)
                        }
                        let exitLine = "---\nExit code: \(finished.terminationStatus)\n"
                        self.logs += exitLine
                        self.appendPersistentLog(exitLine)
                    }
                }
            )
            processTask = task
            logs += "Started PID: \(task.processIdentifier)\n"
        } catch {
            isRunning = false
            processTask = nil
            logs += "❌ Cannot start Python: \(error.localizedDescription)\n"
        }
    }

    func stopBatch() {
        guard let processTask else { return }
        logs += "\nStopping PID: \(processTask.processIdentifier)...\n"
        processTask.terminate()
    }

    func appendProcessOutput(_ chunk: String) {
        for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if text.hasPrefix("CANARY_EVENT ") {
                handleEventLine(String(text.dropFirst("CANARY_EVENT ".count)))
            } else if !text.isEmpty {
                logs += text + "\n"
                appendPersistentLog(text + "\n")
                lastProgressLine = text
            }
        }
    }

    func handleEventLine(_ jsonText: String) {
        guard let event = TranscriptionEventParser.parseLine("CANARY_EVENT \(jsonText)") else {
            logs += "CANARY_EVENT parse failed: \(jsonText)\n"
            return
        }

        switch event {
        case .fileStarted(let path, _):
            updateStatus(path: path, status: "running")
            currentProcessingPath = path
            logStartIndexByPath[path] = logs.endIndex
            updateSession(path: path) { $0.status = .processing }
        case .fileCompleted(let path, let textPath, let jsonPath, let markdownPath, let chars):
            updateStatus(path: path, status: "done")
            batchResultAccumulator.recordSucceeded(path: path)
            let charSuffix = chars.map { ", chars=\($0)" } ?? ""
            logs += "✅ Done: \(textPath ?? "")\(charSuffix)\n"
            if currentProcessingPath == path { currentProcessingPath = nil }
            updateSession(path: path) {
                $0.status = .done
                $0.textPath = textPath
                $0.jsonPath = jsonPath
                $0.markdownPath = markdownPath
            }
        case .fileFailed(let path, let message):
            updateStatus(path: path, status: "failed")
            batchResultAccumulator.recordFailed(path: path, message: message)
            logs += "❌ Failed: \(path) — \(message)\n"
            if currentProcessingPath == path { currentProcessingPath = nil }
            updateSession(path: path) {
                $0.status = .failed
                $0.errorMessage = message
            }
        case .batchCompleted(_, let message):
            logs += "Batch summary: \(message ?? "completed")\n"
        case .warning(let message):
            logs += "⚠️ \(message)\n"
        case .error(let message, let code):
            let suffix = code.map { " (code \($0))" } ?? ""
            logs += "❌ \(message)\(suffix)\n"
        case .stage(let name, let file):
            let suffix = file.map { " — \($0)" } ?? ""
            let line = "Stage: \(name)\(suffix)"
            logs += "\(line)\n"
            lastProgressLine = line
        case .chunkCompleted(let index, let start, let chars):
            let line = "Chunk \(index) at \(start)s completed (chars=\(chars))"
            logs += "\(line)\n"
            lastProgressLine = line
        case .batchStarted:
            break
        case .unknown(let kind, let payload):
            let details = payload.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            logs += "⚠️ Unknown CANARY_EVENT kind '\(kind)'\(details.isEmpty ? "" : " (\(details))")\n"
        }
    }

    func updateStatus(path: String, status: String) {
        if let idx = files.firstIndex(where: { $0.path == path }) {
            files[idx].status = status
        }
    }


    func openOutputLocation() {
        if writeNextToSource {
            if let first = files.first {
                NSWorkspace.shared.open(URL(fileURLWithPath: first.path).deletingLastPathComponent())
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents"))
            }
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: normalizeUserPath(outputFolder), isDirectory: true))
        }
    }

    func colorForStatus(_ status: String) -> Color {
        switch status {
        case "done": return .green
        case "running": return .blue
        case "failed": return .red
        default: return .secondary
        }
    }

    func normalizeUserPath(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\\ ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.hasPrefix("file://"), let url = URL(string: s) {
            return url.path
        }
        if s.hasPrefix("~/") {
            return URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(String(s.dropFirst(2)))
                .path
        }
        if !s.hasPrefix("/"), let slash = s.firstIndex(of: "/") {
            s = String(s[slash...])
        }
        return s
    }

    func bringAppToFront() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            guard let window = NSApp.windows.first else { return }
            let minimumSize = NSSize(width: 1080, height: 820)
            let preferredSize = NSSize(width: 1120, height: 900)
            window.minSize = minimumSize
            var frame = window.frame
            if frame.width < minimumSize.width || frame.height < minimumSize.height {
                let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
                let newWidth = min(max(frame.width, preferredSize.width), screenFrame.width)
                let newHeight = min(max(frame.height, preferredSize.height), screenFrame.height)
                frame.size = NSSize(width: newWidth, height: newHeight)
                frame.origin.x = screenFrame.midX - newWidth / 2
                frame.origin.y = screenFrame.midY - newHeight / 2
                window.setFrame(frame, display: true, animate: false)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func persistentLogPath() -> String {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/CanaryTranscripts/canary-transcriber.log")
            .path
    }

    func appendPersistentLog(_ text: String) {
        let url = URL(fileURLWithPath: persistentLogPath())
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = Data(text.utf8)
            if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // Do not break the UI if filesystem logging fails.
        }
    }

    static func defaultCanaryPythonPath() -> String {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["CANARY_MLX_PYTHON_BIN"], !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit
        }
        let cwd = FileManager.default.currentDirectoryPath
        let candidates = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("venvs/canary-mlx/bin/python").path,
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("venvs/canary-mlx/bin/python").path,
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".venvs/canary-mlx/bin/python").path,
            URL(fileURLWithPath: cwd).appendingPathComponent(".venv-canary/bin/python").path,
            URL(fileURLWithPath: cwd).appendingPathComponent(".venv/bin/python").path
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? candidates[0]
    }

    // MARK: - Dependency checks

    func checkDependencies() {
        ffmpegStatus = .checking
        pythonStatus = .checking

        DispatchQueue.global(qos: .userInitiated).async {
            // Check ffmpeg
            let ffCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            let ffFound = ffCandidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
            DispatchQueue.main.async { self.ffmpegStatus = ffFound ? .present : .missing }

            // Check Python venv
            let py = self.pythonPath
            if FileManager.default.isExecutableFile(atPath: py) {
                let runtime = self.runtime
                let importCheck: String
                switch runtime {
                case "mlx_audio_cli":
                    importCheck = "import mlx_audio"
                case "mlx_whisper":
                    importCheck = "import mlx_whisper"
                case "canary_mlx":
                    importCheck = "import canary_mlx"
                default:
                    importCheck = "import mlx_audio"
                }
                let task = Process()
                task.executableURL = URL(fileURLWithPath: py)
                task.arguments = ["-c", importCheck]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                do {
                    try task.run()
                    task.waitUntilExit()
                    DispatchQueue.main.async { self.pythonStatus = task.terminationStatus == 0 ? .present : .missing }
                } catch {
                    DispatchQueue.main.async { self.pythonStatus = .missing }
                }
            } else {
                DispatchQueue.main.async { self.pythonStatus = .missing }
            }

            // Check if the selected model is cached
            self.checkModelCache()
        }
    }

    func checkModelCache() {
        let modelID = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedProfile.model : model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else { return }

        let py = pythonPath
        guard FileManager.default.isExecutableFile(atPath: py) else { return }

        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: py)
        task.arguments = ["-c", """
from pathlib import Path
import sys
model_id = sys.argv[1]
cache = Path.home() / ".cache" / "huggingface" / "hub"
model_dir = cache / ("models--" + model_id.replace("/", "--"))
if not model_dir.exists():
    print("ABSENT")
    sys.exit(0)
found = list(model_dir.rglob("*.safetensors")) + list(model_dir.rglob("*.bin")) + list(model_dir.rglob("*.msgpack"))
if not found:
    print("ABSENT")
    sys.exit(0)
ref_file = model_dir / "refs" / "main"
local_revision = ref_file.read_text(encoding="utf-8").strip() if ref_file.exists() else ""
try:
    from huggingface_hub import model_info
    remote = model_info(model_id)
    remote_revision = getattr(remote, "sha", "") or ""
    if local_revision and remote_revision and local_revision == remote_revision:
        print("CACHED")
    else:
        print("UPDATABLE")
except Exception:
    print("CACHED")
""", modelID]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                self.modelDownloadStatus[modelID] = output == "CACHED" ? .downloaded : .missing
            }
        } catch {
            DispatchQueue.main.async { self.modelDownloadStatus[modelID] = .missing }
        }
    }

    func installFFmpeg() {
        guard !isInstallingFFmpeg else { return }
        isInstallingFFmpeg = true
        logs += "Stage: installing ffmpeg via Homebrew...\n"
        appendPersistentLog("Stage: installing ffmpeg via Homebrew...\n")

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
            task.arguments = ["install", "ffmpeg"]
            task.standardOutput = pipe
            task.standardError = pipe
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    self.logs += output + "\n"
                    self.appendPersistentLog(output + "\n")
                    if task.terminationStatus == 0 {
                        self.ffmpegStatus = .present
                        self.logs += "✅ ffmpeg installed.\n"
                    } else {
                        self.logs += "❌ ffmpeg install failed (code \(task.terminationStatus)). Install manually: brew install ffmpeg\n"
                    }
                    self.isInstallingFFmpeg = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.logs += "❌ Could not start brew: \(error.localizedDescription)\n"
                    self.logs += "   Install ffmpeg manually: brew install ffmpeg\n"
                    self.isInstallingFFmpeg = false
                }
            }
        }
    }

    func setupPythonEnvironment() {
        guard !isSettingUpPython else { return }
        isSettingUpPython = true
        let venvDir = NSHomeDirectory() + "/venvs/canary-mlx"
        let pythonBin = "/usr/bin/python3"
        logs += "Stage: creating venv at \(venvDir)...\n"
        appendPersistentLog("Stage: creating venv at \(venvDir)...\n")

        DispatchQueue.global(qos: .userInitiated).async {
            let createTask = Process()
            let createPipe = Pipe()
            createTask.executableURL = URL(fileURLWithPath: pythonBin)
            createTask.arguments = ["-m", "venv", venvDir]
            createTask.standardOutput = createPipe
            createTask.standardError = createPipe
            do {
                try createTask.run()
                createTask.waitUntilExit()
                let output = String(data: createPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async { self.logs += output + "\n" }

                guard createTask.terminationStatus == 0 else {
                    DispatchQueue.main.async {
                        self.logs += "❌ Could not create venv. Create it manually:\n   python3 -m venv \(venvDir)\n"
                        self.isSettingUpPython = false
                    }
                    return
                }

                let venvPython = venvDir + "/bin/python"

                // Install packages
                let packages = ["mlx-audio[stt]", "mlx-whisper", "canary-mlx", "huggingface_hub"]
                let installTask = Process()
                let installPipe = Pipe()
                installTask.executableURL = URL(fileURLWithPath: venvPython)
                installTask.arguments = ["-m", "pip", "install"] + packages + ["--quiet"]
                installTask.standardOutput = installPipe
                installTask.standardError = installPipe

                DispatchQueue.main.async { self.logs += "Stage: installing packages... (may take several minutes)\n" }
                try installTask.run()
                installTask.waitUntilExit()
                let pipOutput = String(data: installPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    if installTask.terminationStatus == 0 {
                        self.pythonPath = venvPython
                        self.pythonStatus = .present
                        self.logs += "✅ Venv created and packages installed: \(venvPython)\n"
                    } else {
                        self.logs += pipOutput + "\n"
                        self.logs += "❌ pip install failed. Install packages manually:\n   \(venvPython) -m pip install mlx-audio mlx-whisper canary-mlx huggingface-hub\n"
                    }
                    self.isSettingUpPython = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.logs += "❌ Error: \(error.localizedDescription). Create the venv manually.\n"
                    self.isSettingUpPython = false
                }
            }
        }
    }

    func downloadModel(_ modelID: String) {
        guard !isDownloadingModel, !modelID.isEmpty else { return }
        isDownloadingModel = true
        modelDownloadStatus[modelID] = .downloading
        logs += "Stage: downloading model \(modelID) via huggingface_hub...\n"
        appendPersistentLog("Stage: downloading model \(modelID) via huggingface_hub...\n")

        let py = pythonPath
        guard FileManager.default.isExecutableFile(atPath: py) else {
            logs += "❌ Python venv not found. Set up the environment first.\n"
            modelDownloadStatus[modelID] = .missing
            isDownloadingModel = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: py)
            task.arguments = ["-c", """
import sys
try:
    from huggingface_hub import snapshot_download
    print("Stage: downloading " + \(modelID.debugDescription) + " to HuggingFace cache...", flush=True)
    snapshot_download(\(modelID.debugDescription), resume_download=True, local_files_only=False)
    print("DONE", flush=True)
except KeyboardInterrupt:
    print("INTERRUPTED", flush=True)
    sys.exit(1)
except Exception as e:
    print(f"FAILED: {e}", flush=True)
    sys.exit(1)
"""]
            task.standardOutput = Pipe()
            task.standardError = task.standardOutput
            do {
                try task.run()
                task.waitUntilExit()
                if let pipe = task.standardOutput as? Pipe {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    DispatchQueue.main.async {
                        self.logs += output
                        self.appendPersistentLog(output)
                        if task.terminationStatus == 0 && output.contains("DONE") {
                            self.modelDownloadStatus[modelID] = .downloaded
                            self.logs += "✅ Model \(modelID) downloaded.\n"
                        } else {
                            self.modelDownloadStatus[modelID] = .missing
                        }
                        self.isDownloadingModel = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.modelDownloadStatus[modelID] = .missing
                        self.isDownloadingModel = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.logs += "❌ Model download error: \(error.localizedDescription)\n"
                    self.modelDownloadStatus[modelID] = .missing
                    self.isDownloadingModel = false
                }
            }
        }
    }

}
