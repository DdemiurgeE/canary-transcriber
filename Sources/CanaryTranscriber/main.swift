import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers

@main
struct CanaryTranscriberApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1120, height: 900)
    }
}

struct AudioFileItem: Identifiable, Hashable {
    let id = UUID()
    var path: String
    var status: String = "queued"
}

struct BatchConfig: Codable {
    let files: [String]
    let outputDir: String?
    let writeNextToSource: Bool
    let profileID: String
    let runtime: String
    let model: String
    let language: String
    let timestamps: Bool
    let chunkDuration: Double?
    let overlapDuration: Double
}

struct TranscriptionProfile: Identifiable, Hashable {
    let id: String
    let title: String
    let runtime: String
    let model: String
    let language: String
    let chunkDuration: String
    let details: String
}

struct ContentView: View {
    @State private var files: [AudioFileItem] = []
    @State private var selectedFileID: AudioFileItem.ID?
    @State private var logs: String = "Готово. Добавь аудиофайлы и нажми Transcribe.\n"

    @State private var pythonPath: String = Self.defaultCanaryPythonPath()
    @State private var selectedProfileID: String = "multilingual-canary-v2"
    @State private var runtime: String = "mlx_audio_cli"
    @State private var model: String = "CogniSoftOrg/canary-1b-v2-mlx-bf16"
    @State private var language: String = "ru"
    @State private var chunkDuration: String = "30"
    @State private var timestamps: Bool = false
    @State private var writeNextToSource: Bool = true
    @State private var outputFolder: String = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/CanaryTranscripts").path

    @State private var isRunning = false
    @State private var process: Process?
    @State private var currentConfigPath: String?
    @State private var isFileDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            settingsPanel
            filePanel
            controlsPanel
            logPanel
        }
        .padding(16)
        .frame(minWidth: 1080, idealWidth: 1120, minHeight: 820, idealHeight: 900)
        .onAppear { bringAppToFront() }
    }

    private var profiles: [TranscriptionProfile] {
        [
            TranscriptionProfile(
                id: "fast-parakeet-v3",
                title: "fast — Parakeet v3",
                runtime: "mlx_audio_cli",
                model: "mlx-community/parakeet-tdt-0.6b-v3",
                language: "ru",
                chunkDuration: "30",
                details: "Быстрый MLX STT по умолчанию: NVIDIA Parakeet TDT 0.6B v3 через mlx-audio."
            ),
            TranscriptionProfile(
                id: "fast-whisper-turbo",
                title: "fast — Whisper Turbo",
                runtime: "mlx_whisper",
                model: "mlx-community/whisper-large-v3-turbo",
                language: "ru",
                chunkDuration: "30",
                details: "Быстрый Whisper-compatible профиль через mlx-whisper."
            ),
            TranscriptionProfile(
                id: "accurate-whisper-large-v3",
                title: "accurate — Whisper large-v3",
                runtime: "mlx_whisper",
                model: "mlx-community/whisper-large-v3-mlx",
                language: "ru",
                chunkDuration: "30",
                details: "Максимально проверенный universal baseline для качества и сложного аудио."
            ),
            TranscriptionProfile(
                id: "multilingual-canary-v2",
                title: "multilingual European — Canary 1B v2",
                runtime: "mlx_audio_cli",
                model: "CogniSoftOrg/canary-1b-v2-mlx-bf16",
                language: "ru",
                chunkDuration: "30",
                details: "Canary 1B v2 для 25 европейских языков; ASR/translation test path через mlx-audio."
            ),
            TranscriptionProfile(
                id: "realtime-voxtral-mini",
                title: "realtime — Voxtral Mini Realtime",
                runtime: "mlx_audio_cli",
                model: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit",
                language: "ru",
                chunkDuration: "30",
                details: "Streaming/realtime-oriented модель; в этом batch UI запускается по файлам через mlx-audio."
            )
        ]
    }

    private var selectedProfile: TranscriptionProfile {
        profiles.first(where: { $0.id == selectedProfileID }) ?? profiles[0]
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Canary Transcriber")
                    .font(.title2).bold()
                Text("macOS GUI для транскрипции выбранных аудиофайлов через MLX-профили: Parakeet, Whisper, Canary, Voxtral")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isRunning {
                ProgressView()
                    .controlSize(.small)
                Text("running")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var settingsPanel: some View {
        GroupBox("Настройки") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text("Profile")
                        .frame(width: 120, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Profile", selection: $selectedProfileID) {
                            ForEach(profiles) { profile in
                                Text(profile.title).tag(profile.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 360)
                        .onChange(of: selectedProfileID) { applySelectedProfile() }

                        Text(selectedProfile.details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    Text("Python venv")
                        .frame(width: 120, alignment: .leading)
                    TextField("/path/to/venv/bin/python", text: $pythonPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose") { choosePython() }
                }

                HStack {
                    Text("Model")
                        .frame(width: 120, alignment: .leading)
                    TextField("model id", text: $model)
                        .textFieldStyle(.roundedBorder)

                    Text("Runtime")
                    Picker("Runtime", selection: $runtime) {
                        Text("mlx-audio CLI").tag("mlx_audio_cli")
                        Text("mlx-whisper").tag("mlx_whisper")
                        Text("canary-mlx legacy").tag("canary_mlx")
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    Text("Lang")
                    TextField("ru", text: $language)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)

                    Text("Chunk sec")
                    TextField("30", text: $chunkDuration)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)

                    Toggle("timestamps", isOn: $timestamps)
                        .toggleStyle(.checkbox)
                }

                Toggle("Сохранять транскрипт рядом с исходным файлом", isOn: $writeNextToSource)
                    .toggleStyle(.checkbox)

                HStack {
                    Text("Output folder")
                        .frame(width: 120, alignment: .leading)
                    TextField("/path/to/output", text: $outputFolder)
                        .textFieldStyle(.roundedBorder)
                        .disabled(writeNextToSource)
                    Button("Choose") { chooseOutputFolder() }
                        .disabled(writeNextToSource)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var filePanel: some View {
        GroupBox("Файлы") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Add files") { chooseAudioFiles() }
                        .disabled(isRunning)
                    Button("Remove selected") { removeSelectedFile() }
                        .disabled(isRunning || selectedFileID == nil)
                    Button("Clear list") { files.removeAll() }
                        .disabled(isRunning || files.isEmpty)
                    Text("Выбрано: \(files.count)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Можно перетащить аудио/видео файлы сюда")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isFileDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    isFileDropTargeted ? Color.accentColor : Color.secondary.opacity(files.isEmpty ? 0.45 : 0.15),
                                    style: StrokeStyle(lineWidth: isFileDropTargeted ? 2 : 1, dash: files.isEmpty ? [6, 5] : [])
                                )
                        )

                    List(selection: $selectedFileID) {
                        ForEach(files) { item in
                            HStack {
                                Text(item.status)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 90, alignment: .leading)
                                    .foregroundStyle(colorForStatus(item.status))
                                Text(item.path)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .tag(item.id)
                        }
                    }
                    .opacity(files.isEmpty ? 0.35 : 1)
                    .padding(4)

                    if files.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform.badge.plus")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(isFileDropTargeted ? Color.accentColor : Color.secondary)
                            Text(isFileDropTargeted ? "Отпусти файлы, чтобы добавить" : "Перетащи сюда аудио/видео файлы")
                                .font(.headline)
                            Text("или нажми Add files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 180, idealHeight: 210, maxHeight: 240)
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL], isTargeted: $isFileDropTargeted, perform: handleFileDrop(providers:))
            }
            .padding(.vertical, 4)
        }
    }

    private var controlsPanel: some View {
        HStack(spacing: 8) {
            Button(isRunning ? "Transcribing..." : "Transcribe") { startBatch() }
                .disabled(isRunning || files.isEmpty)

            Button("Stop") { stopBatch() }
                .disabled(!isRunning)

            Button("Open output") { openOutputLocation() }

            Button("Clear logs") { logs = "" }
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Логи")
                .font(.headline)
            ScrollView {
                Text(logs)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180, idealHeight: 220, maxHeight: .infinity)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func applySelectedProfile() {
        let profile = selectedProfile
        runtime = profile.runtime
        model = profile.model
        language = profile.language
        chunkDuration = profile.chunkDuration
        logs += "Profile selected: \(profile.title) → runtime=\(profile.runtime), model=\(profile.model)\n"
    }

    private func chooseAudioFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = []
        panel.message = "Выбери аудиофайлы для транскрипции через Canary-MLX"
        if panel.runModal() == .OK {
            let newPaths = panel.urls.map { normalizeUserPath($0.standardizedFileURL.path) }
            addAudioPaths(newPaths, source: "picker")
        }
    }

    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard !isRunning else {
            logs += "⚠️ Нельзя добавлять файлы во время транскрибации.\n"
            return false
        }

        let fileURLType = UTType.fileURL.identifier
        let matchingProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(fileURLType) }
        guard !matchingProviders.isEmpty else { return false }

        for provider in matchingProviders {
            provider.loadItem(forTypeIdentifier: fileURLType, options: nil) { item, error in
                if let error {
                    DispatchQueue.main.async {
                        logs += "⚠️ Drop error: \(error.localizedDescription)\n"
                    }
                    return
                }

                guard let path = decodeDroppedFilePath(item) else {
                    DispatchQueue.main.async {
                        logs += "⚠️ Drop: не смог прочитать file URL.\n"
                    }
                    return
                }

                DispatchQueue.main.async {
                    addAudioPaths([path], source: "drag&drop")
                }
            }
        }
        return true
    }

    private func decodeDroppedFilePath(_ item: NSSecureCoding?) -> String? {
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

    private func addAudioPaths(_ rawPaths: [String], source: String) {
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
        }
        logs += "Added files (\(source)): \(additions.count)"
        if skippedDuplicates > 0 { logs += ", duplicates skipped: \(skippedDuplicates)" }
        if skippedDirectories > 0 { logs += ", directories skipped: \(skippedDirectories)" }
        logs += "\n"
    }

    private func choosePython() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        if panel.runModal() == .OK, let url = panel.url {
            pythonPath = normalizeUserPath(url.standardizedFileURL.path)
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = normalizeUserPath(url.standardizedFileURL.path)
        }
    }

    private func removeSelectedFile() {
        guard let selectedFileID else { return }
        files.removeAll { $0.id == selectedFileID }
        self.selectedFileID = nil
    }

    private func startBatch() {
        guard !isRunning else { return }

        let cleanPython = normalizeUserPath(pythonPath)
        pythonPath = cleanPython
        guard FileManager.default.isExecutableFile(atPath: cleanPython) else {
            logs += "❌ Python is not executable: \(cleanPython)\n"
            logs += "   Укажи venv с canary-mlx, например /Users/pavelpalnikov/venvs/canary-mlx/bin/python\n"
            return
        }

        let normalizedFiles = files.map { item in
            AudioFileItem(path: normalizeUserPath(item.path), status: "queued")
        }
        files = normalizedFiles
        let missing = normalizedFiles.filter { !FileManager.default.fileExists(atPath: $0.path) }
        if !missing.isEmpty {
            logs += "❌ Не найдены файлы:\n"
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

        let chunk = Double(chunkDuration.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30.0
        let config = BatchConfig(
            files: normalizedFiles.map { $0.path },
            outputDir: writeNextToSource ? nil : cleanOutput,
            writeNextToSource: writeNextToSource,
            profileID: selectedProfileID,
            runtime: runtime,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedProfile.model : model.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedProfile.language : language.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamps: timestamps,
            chunkDuration: chunk <= 0 ? nil : chunk,
            overlapDuration: 2.0
        )

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

        runPython(configURL: configURL, pythonPath: cleanPython, config: config)
    }

    private func runPython(configURL: URL, pythonPath: String, config: BatchConfig) {
        let script = #"""
import json
import shutil
import subprocess
import sys
import tempfile
import traceback
import wave
from pathlib import Path

try:
    cfg = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    files = [Path(p).expanduser() for p in cfg["files"]]
    output_dir = Path(cfg["outputDir"]).expanduser() if cfg.get("outputDir") else None
    write_next_to_source = bool(cfg.get("writeNextToSource", True))
    model_id = cfg.get("model") or "qfuxa/canary-mlx"
    runtime = cfg.get("runtime") or "canary_mlx"
    profile_id = cfg.get("profileID") or "custom"
    language = cfg.get("language") or "ru"
    timestamps = bool(cfg.get("timestamps", False))
    chunk_duration = cfg.get("chunkDuration", 30.0)
    overlap_duration = float(cfg.get("overlapDuration", 2.0))

    def emit(kind, **payload):
        payload["kind"] = kind
        print("CANARY_EVENT " + json.dumps(payload, ensure_ascii=False, default=str), flush=True)

    def output_paths(audio_path):
        base_dir = audio_path.parent if write_next_to_source else output_dir
        base_dir.mkdir(parents=True, exist_ok=True)
        stem = audio_path.stem
        return base_dir / f"{stem}.canary.txt", base_dir / f"{stem}.canary.json"

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
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(audio_path),
            "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
            str(normalized),
        ], check=True)

        duration = wav_duration_seconds(normalized)
        chunk_seconds = float(seconds or 30.0)
        if chunk_seconds <= 0:
            chunk_seconds = 30.0
        chunks = []
        start = 0.0
        idx = 0
        while start < duration:
            out = work_dir / f"chunk_{idx:04d}.wav"
            subprocess.run([
                ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                "-ss", f"{start:.3f}", "-i", str(normalized),
                "-t", f"{chunk_seconds:.3f}",
                "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
                str(out),
            ], check=True)
            if out.exists() and out.stat().st_size > 44:
                chunks.append((idx, start, out))
            idx += 1
            start += chunk_seconds
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
                result = model_obj.transcribe(str(path), language=language, timestamps=timestamps)
                return result.text if hasattr(result, "text") else str(result)
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
                    result = mlx_whisper.transcribe(str(path), **kwargs)
                except TypeError:
                    kwargs.pop("language", None)
                    result = mlx_whisper.transcribe(str(path), **kwargs)
                if isinstance(result, dict):
                    return str(result.get("text", ""))
                return result.text if hasattr(result, "text") else str(result)
            return transcribe

        if runtime_name == "mlx_audio_cli":
            try:
                import mlx_audio  # noqa: F401
            except Exception as exc:
                raise RuntimeError("Python package mlx-audio is required for Parakeet/Canary v2/Voxtral profiles. Install: python -m pip install 'mlx-audio[stt]' or python -m pip install mlx-audio") from exc
            print("Stage: mlx_audio CLI ready", flush=True)
            def transcribe(path):
                with tempfile.TemporaryDirectory(prefix="mlx-audio-out-") as out_tmp:
                    out_dir = Path(out_tmp)
                    out_file = out_dir / "transcript.txt"
                    cmd = [
                        sys.executable, "-m", "mlx_audio.stt.generate",
                        "--model", model_name,
                        "--audio", str(path),
                        "--output-path", str(out_file),
                        "--format", "txt",
                    ]
                    if language:
                        cmd.extend(["--language", language])
                    proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                    output = proc.stdout or ""
                    if proc.returncode != 0:
                        # Some mlx-audio versions do not accept --language; retry without it.
                        if "--language" in cmd:
                            cmd = [x for x in cmd if x not in ["--language", language]]
                            proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                            output = proc.stdout or ""
                    if proc.returncode != 0:
                        raise RuntimeError(f"mlx-audio CLI failed with code {proc.returncode}: {output[-4000:]}")
                    text_candidates = []
                    for candidate in sorted(out_dir.rglob("*")):
                        if candidate.is_file() and candidate.suffix.lower() in {".txt", ".text", ".md"}:
                            text_candidates.append(candidate.read_text(encoding="utf-8", errors="ignore"))
                        elif candidate.is_file() and candidate.suffix.lower() == ".json":
                            try:
                                data = json.loads(candidate.read_text(encoding="utf-8", errors="ignore"))
                                if isinstance(data, dict):
                                    for key in ["text", "transcription", "transcript"]:
                                        if data.get(key):
                                            text_candidates.append(str(data[key]))
                            except Exception:
                                pass
                    joined = "\n".join(t.strip() for t in text_candidates if t.strip()).strip()
                    if joined:
                        return joined
                    # Last resort: return stdout after removing event/progress noise.
                    return "\n".join(line for line in output.splitlines() if line.strip() and not line.startswith("Stage:"))
            return transcribe

        raise RuntimeError(f"Unknown runtime: {runtime_name}. Supported: canary_mlx, mlx_whisper, mlx_audio_cli")

    print(f"Stage: STT preflight; files={len(files)} profile={profile_id} runtime={runtime}", flush=True)
    for p in files:
        if not p.exists():
            raise FileNotFoundError(f"audio file not found: {p}")
    if output_dir is not None:
        output_dir.mkdir(parents=True, exist_ok=True)

    transcribe_chunk = make_transcriber(runtime, model_id)

    ok = 0
    failed = 0
    for index, audio_path in enumerate(files, 1):
        emit("file_started", path=str(audio_path), index=index, total=len(files))
        print(f"Stage: transcribe [{index}/{len(files)}] {audio_path}", flush=True)
        txt_path, json_path = output_paths(audio_path)
        try:
            parts = []
            chunk_records = []
            with tempfile.TemporaryDirectory(prefix="canary-transcriber-") as tmp:
                chunks, duration, effective_chunk = make_wav_chunks(audio_path, Path(tmp), chunk_duration)
                for chunk_index, chunk_start, chunk_path in chunks:
                    print(f"Stage: STT chunk {chunk_index + 1}/{len(chunks)} start={chunk_start:.1f}s runtime={runtime}", flush=True)
                    chunk_text = transcribe_chunk(chunk_path)
                    chunk_text = chunk_text.strip()
                    if chunk_text:
                        parts.append(chunk_text)
                    chunk_records.append({
                        "index": chunk_index,
                        "start": chunk_start,
                        "path": str(chunk_path.name),
                        "chars": len(chunk_text),
                        "text": chunk_text,
                    })

            text = "\n".join(parts).strip()
            txt_path.write_text(text, encoding="utf-8")
            payload = {
                "audio": str(audio_path),
                "profile": profile_id,
                "runtime": runtime,
                "model": model_id,
                "language": language,
                "timestamps": timestamps,
                "manual_chunking": True,
                "chunk_duration": chunk_duration,
                "overlap_duration": 0,
                "text": text,
                "chunks": chunk_records,
            }
            json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
            ok += 1
            emit("file_done", path=str(audio_path), txt=str(txt_path), json=str(json_path), chars=len(text))
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

        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = ["-u", "-c", script, configURL.path]
        proc.standardOutput = pipe
        proc.standardError = pipe
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        let guiSafePath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existingPath = env["PATH"], !existingPath.isEmpty {
            env["PATH"] = guiSafePath + ":" + existingPath
        } else {
            env["PATH"] = guiSafePath
        }
        proc.environment = env

        let batchHeader = """

=== MLX batch transcription ===
Python: \(pythonPath)
Profile: \(config.profileID)
Runtime: \(config.runtime)
Model: \(config.model)
Language: \(config.language)
Chunk duration: \(config.chunkDuration.map { String($0) } ?? "off")
Files: \(config.files.count)
Output: \(config.writeNextToSource ? "next to source files" : (config.outputDir ?? ""))
PATH: \(env["PATH"] ?? "")
Persistent log: \(persistentLogPath())
"""
        logs += batchHeader
        appendPersistentLog(batchHeader)

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                appendProcessOutput(chunk)
            }
        }

        proc.terminationHandler = { finished in
            DispatchQueue.main.async {
                self.isRunning = false
                self.process = nil
                if let currentConfigPath {
                    try? FileManager.default.removeItem(atPath: currentConfigPath)
                    self.currentConfigPath = nil
                }
                if finished.terminationStatus == 0 {
                    self.logs += "\n✅ Batch завершён успешно.\n"
                    self.appendPersistentLog("\n✅ Batch завершён успешно.\n")
                } else if finished.terminationStatus == 15 {
                    self.logs += "\n⏹️ Batch остановлен пользователем.\n"
                    self.appendPersistentLog("\n⏹️ Batch остановлен пользователем.\n")
                } else {
                    let reason = String(describing: finished.terminationReason)
                    let message = "\n⚠️ Batch завершился с ошибками (code \(finished.terminationStatus), reason \(reason)).\n"
                    self.logs += message
                    self.appendPersistentLog(message)
                }
                let exitLine = "---\nExit code: \(finished.terminationStatus)\n"
                self.logs += exitLine
                self.appendPersistentLog(exitLine)
            }
            pipe.fileHandleForReading.readabilityHandler = nil
        }

        do {
            isRunning = true
            try proc.run()
            process = proc
            logs += "Started PID: \(proc.processIdentifier)\n"
        } catch {
            isRunning = false
            process = nil
            logs += "❌ Cannot start Python: \(error.localizedDescription)\n"
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func stopBatch() {
        guard let process else { return }
        logs += "\nОстанавливаю PID: \(process.processIdentifier)...\n"
        process.terminate()
    }

    private func appendProcessOutput(_ chunk: String) {
        for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if text.hasPrefix("CANARY_EVENT ") {
                handleEventLine(String(text.dropFirst("CANARY_EVENT ".count)))
            } else if !text.isEmpty {
                logs += text + "\n"
                appendPersistentLog(text + "\n")
            }
        }
    }

    private func handleEventLine(_ jsonText: String) {
        guard let data = jsonText.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = payload["kind"] as? String else {
            logs += "CANARY_EVENT parse failed: \(jsonText)\n"
            return
        }

        switch kind {
        case "file_started":
            if let path = payload["path"] as? String {
                updateStatus(path: path, status: "running")
            }
        case "file_done":
            if let path = payload["path"] as? String {
                updateStatus(path: path, status: "done")
            }
            let txt = payload["txt"] as? String ?? ""
            let chars = payload["chars"] as? Int ?? 0
            logs += "✅ Done: \(txt) (chars=\(chars))\n"
        case "file_failed":
            if let path = payload["path"] as? String {
                updateStatus(path: path, status: "failed")
            }
            logs += "❌ Failed: \(payload["path"] ?? "") — \(payload["error"] ?? "unknown")\n"
        case "batch_done":
            logs += "Batch summary: ok=\(payload["ok"] ?? 0), failed=\(payload["failed"] ?? 0), total=\(payload["total"] ?? 0)\n"
        default:
            logs += "Event: \(jsonText)\n"
        }
    }

    private func updateStatus(path: String, status: String) {
        if let idx = files.firstIndex(where: { $0.path == path }) {
            files[idx].status = status
        }
    }

    private func openOutputLocation() {
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

    private func colorForStatus(_ status: String) -> Color {
        switch status {
        case "done": return .green
        case "running": return .blue
        case "failed": return .red
        default: return .secondary
        }
    }

    private func normalizeUserPath(_ raw: String) -> String {
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

    private func bringAppToFront() {
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

    private func persistentLogPath() -> String {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/CanaryTranscripts/canary-transcriber.log")
            .path
    }

    private func appendPersistentLog(_ text: String) {
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

    private static func defaultCanaryPythonPath() -> String {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["CANARY_MLX_PYTHON_BIN"], !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit
        }
        let cwd = FileManager.default.currentDirectoryPath
        let candidates = [
            "/Users/pavelpalnikov/venvs/canary-mlx/bin/python",
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("venvs/canary-mlx/bin/python").path,
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".venvs/canary-mlx/bin/python").path,
            URL(fileURLWithPath: cwd).appendingPathComponent(".venv-canary/bin/python").path,
            URL(fileURLWithPath: cwd).appendingPathComponent(".venv/bin/python").path
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? candidates[0]
    }
}
