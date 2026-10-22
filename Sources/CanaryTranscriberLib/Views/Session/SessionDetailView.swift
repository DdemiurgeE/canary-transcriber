import SwiftUI
import AppKit
import CanaryTranscriberCore

struct SessionDetailView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    let sessionID: SessionRecord.ID

    @State private var transcript: SessionTranscript?
    @State private var loadError: String?
    @State private var plainFallbackText: String?
    @State private var showingLog = false
    @State private var renamingSpeaker: String?
    @State private var aliasDraft: String = ""
    @State private var showingDiarizationPrompt = false
    @State private var showingTranscriptionSettings = false
    @State private var runSettings = PostRecordingRunSettings(
        profileID: "", language: "ru", chunkDuration: "30", timestamps: false,
        diarization: false, speakerCount: "auto", aliasesText: ""
    )
    @State private var draftLanguage: String = ""
    @State private var draftSpeakerCount: String = ""
    @State private var draftAliases: String = ""
    @State private var logDrawerHeight: CGFloat = 160

    private var session: SessionRecord? {
        viewModel.librarySessions.first(where: { $0.id == sessionID })
    }

    static func shouldReloadTranscript(after status: SessionRecord.Status) -> Bool {
        status == .done || status == .failed
    }

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                Text("Session not found")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(_ session: SessionRecord) -> some View {
        VStack(spacing: 0) {
            decorativeWave

            ScrollView {
                transcriptBody(session)
                    .padding(16)
            }

            if showingLog {
                ResizableLogPanel(
                    height: $logDrawerHeight,
                    text: session.status == .processing ? viewModel.logs : (session.logExcerpt.isEmpty ? "No log yet." : session.logExcerpt)
                )
            }
        }
        .navigationTitle(session.displayName)
        .toolbar {
            ToolbarItemGroup {
                chip(session.profileID)
                if session.diarizationEnabled {
                    chip(session.speakerCount.map { "Diarization: \($0) speakers" } ?? "Diarization")
                }
                Spacer()
                Button("Log") { showingLog.toggle() }
                if session.status == .processing {
                    Button("Stop", role: .destructive) { viewModel.stopBatch() }
                } else {
                    Button("Transcribe…") {
                        runSettings = viewModel.postRecordingSettings(for: session)
                        showingTranscriptionSettings = true
                    }
                    .disabled(viewModel.isRunning)
                    .popover(isPresented: $showingTranscriptionSettings) {
                        PostRecordingRunPrompt(settings: $runSettings, profiles: viewModel.profiles) {
                            viewModel.requeueForTranscription(
                                sessionIDs: [session.id], forceDiarization: false, settings: runSettings
                            )
                            showingTranscriptionSettings = false
                        }
                    }
                    Button("Re-run diarization") {
                        draftLanguage = session.language
                        draftSpeakerCount = session.speakerCount.map(String.init) ?? "auto"
                        draftAliases = viewModel.speakerAliasesText
                        showingDiarizationPrompt = true
                    }
                    .disabled(viewModel.isRunning)
                    .popover(isPresented: $showingDiarizationPrompt) {
                        DiarizationRunPrompt(language: $draftLanguage, speakerCount: $draftSpeakerCount, aliasesText: $draftAliases) {
                            var settings = viewModel.postRecordingSettings(for: session)
                            settings.language = draftLanguage
                            settings.speakerCount = draftSpeakerCount
                            settings.aliasesText = draftAliases
                            settings.diarization = true
                            viewModel.requeueForTranscription(
                                sessionIDs: [session.id], forceDiarization: false, settings: settings
                            )
                            showingDiarizationPrompt = false
                        }
                    }
                    Button("Export") { viewModel.revealSessionOutput(session) }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.jsonPath == nil && session.textPath == nil)
                }
            }
        }
        .onAppear { loadTranscriptIfNeeded(session) }
        .onChange(of: session.status) {
            if session.status == .queued || session.status == .processing {
                transcript = nil
                loadError = nil
                plainFallbackText = nil
            } else if Self.shouldReloadTranscript(after: session.status) {
                transcript = nil
                loadError = nil
                plainFallbackText = nil
                loadTranscriptIfNeeded(session)
            }
        }
        .onChange(of: session.jsonPath) {
            transcript = nil
            loadError = nil
            plainFallbackText = nil
            loadTranscriptIfNeeded(session)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }

    private var decorativeWave: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<60, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 3, height: waveHeight(i))
            }
        }
        .frame(height: 40)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
    }

    private func waveHeight(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [14, 30, 20, 36, 10, 26]
        return pattern[index % pattern.count]
    }

    @ViewBuilder
    private func transcriptBody(_ session: SessionRecord) -> some View {
        if let transcript {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(transcript.displaySegments.enumerated()), id: \.offset) { _, segment in
                    segmentRow(segment, session: session)
                }
            }
        } else if let plainFallbackText {
            VStack(alignment: .leading, spacing: 8) {
                Text("Speaker-by-speaker breakdown isn't available for this session — showing the plain transcript instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(plainFallbackText)
            }
        } else if let loadError {
            VStack(alignment: .leading, spacing: 8) {
                Text(loadError).foregroundStyle(.secondary)
                Button("Transcribe…") {
                    runSettings = viewModel.postRecordingSettings(for: session)
                    showingTranscriptionSettings = true
                }
            }
        } else if session.status == .processing || session.status == .queued {
            Text("Transcript will appear once processing finishes.").foregroundStyle(.secondary)
        } else if session.status == .failed {
            Text(session.errorMessage ?? "Transcription failed.").foregroundStyle(.red)
        } else {
            Text("No transcript data.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func segmentRow(_ segment: SessionTranscriptSegment, session: SessionRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let speaker = segment.speaker {
                Button(displayName(for: speaker)) {
                    renamingSpeaker = speaker
                    aliasDraft = viewModel.parsedSpeakerAliases()[speaker] ?? ""
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(speakerColor(speaker).opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .popover(isPresented: Binding(
                    get: { renamingSpeaker == speaker },
                    set: { if !$0 { renamingSpeaker = nil } }
                )) {
                    renamePopover(speaker, session: session)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(timeRange(segment)).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                Text(segment.text)
            }
        }
    }

    private func renamePopover(_ speaker: String, session: SessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rename speaker").font(.caption).foregroundStyle(.secondary)
            TextField(speaker, text: $aliasDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Text("Also updates this session's .json/.md output.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Save") {
                viewModel.setSpeakerAlias(aliasDraft, for: speaker)
                if let transcript {
                    viewModel.rewriteOutputsAfterSpeakerRename(alias: aliasDraft, speaker: speaker, session: session, transcript: transcript)
                }
                renamingSpeaker = nil
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    private func displayName(for speaker: String) -> String {
        guard let alias = viewModel.parsedSpeakerAliases()[speaker], !alias.isEmpty else { return speaker }
        return "\(alias) (\(speaker))"
    }

    private func speakerColor(_ speaker: String) -> Color {
        let palette: [Color] = [.orange, .blue, .purple, .green, .pink]
        let index = abs(speaker.hashValue) % palette.count
        return palette[index]
    }

    private func timeRange(_ segment: SessionTranscriptSegment) -> String {
        "\(formatTime(segment.start)) – \(formatTime(segment.end))"
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func loadTranscriptIfNeeded(_ session: SessionRecord) {
        guard session.status == .done || session.status == .failed else { return }
        guard transcript == nil, loadError == nil, plainFallbackText == nil else { return }
        guard let jsonPath = session.jsonPath else {
            loadPlainFallback(session)
            return
        }
        do {
            transcript = try SessionTranscript.load(from: URL(fileURLWithPath: jsonPath))
        } catch {
            if !loadPlainFallback(session) {
                loadError = "Couldn't read transcript at \(jsonPath): \(error.localizedDescription)"
            }
        }
    }

    /// Falls back to the plain .txt output (no speaker structure) when the .canary.json is
    /// missing or unreadable — e.g. the output folder changed after the run that produced it.
    @discardableResult
    private func loadPlainFallback(_ session: SessionRecord) -> Bool {
        guard let textPath = session.textPath,
              let text = try? String(contentsOfFile: textPath, encoding: .utf8),
              !text.isEmpty else { return false }
        plainFallbackText = text
        return true
    }
}
