import SwiftUI
import AppKit
import CanaryTranscriberCore

struct SessionDetailView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    let sessionID: SessionRecord.ID

    @State private var transcript: SessionTranscript?
    @State private var loadError: String?
    @State private var showingLog = false
    @State private var renamingSpeaker: String?
    @State private var aliasDraft: String = ""
    @State private var showingDiarizationPrompt = false
    @State private var draftLanguage: String = ""
    @State private var draftSpeakerCount: String = ""
    @State private var draftAliases: String = ""
    @State private var logDrawerHeight: CGFloat = 160
    @State private var logDrawerHeightAtDragStart: CGFloat?
    @State private var isResizeCursorPushed = false

    private var session: SessionRecord? {
        viewModel.librarySessions.first(where: { $0.id == sessionID })
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
                logDrawer(session)
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
                    Button("Re-run diarization") {
                        draftLanguage = session.language
                        draftSpeakerCount = session.speakerCount.map(String.init) ?? "auto"
                        draftAliases = viewModel.speakerAliasesText
                        showingDiarizationPrompt = true
                    }
                    .disabled(viewModel.isRunning)
                    .popover(isPresented: $showingDiarizationPrompt) {
                        DiarizationRunPrompt(language: $draftLanguage, speakerCount: $draftSpeakerCount, aliasesText: $draftAliases) {
                            viewModel.language = draftLanguage
                            viewModel.diarizationSpeakerCount = draftSpeakerCount
                            viewModel.speakerAliasesText = draftAliases
                            viewModel.requeueForTranscription(sessionIDs: [session.id], forceDiarization: true)
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
        .onChange(of: session.jsonPath) { transcript = nil; loadTranscriptIfNeeded(session) }
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
                    segmentRow(segment)
                }
            }
        } else if let loadError {
            Text(loadError).foregroundStyle(.secondary)
        } else if session.status == .processing || session.status == .queued {
            Text("Transcript will appear once processing finishes.").foregroundStyle(.secondary)
        } else if session.status == .failed {
            Text(session.errorMessage ?? "Transcription failed.").foregroundStyle(.red)
        } else {
            Text("No transcript data.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func segmentRow(_ segment: SessionTranscriptSegment) -> some View {
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
                    renamePopover(speaker)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(timeRange(segment)).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                Text(segment.text)
            }
        }
    }

    private func renamePopover(_ speaker: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rename speaker").font(.caption).foregroundStyle(.secondary)
            TextField(speaker, text: $aliasDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button("Save") {
                viewModel.setSpeakerAlias(aliasDraft, for: speaker)
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

    private func logDrawer(_ session: SessionRecord) -> some View {
        VStack(spacing: 0) {
            logDrawerHandle
            ScrollView {
                Text(session.status == .processing ? viewModel.logs : (session.logExcerpt.isEmpty ? "No log yet." : session.logExcerpt))
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(height: logDrawerHeight)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var logDrawerHandle: some View {
        ZStack {
            Rectangle().fill(Color.clear)
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 6)
            Capsule().fill(Color.secondary.opacity(0.5)).frame(width: 32, height: 3)
        }
        .frame(height: 10)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                pushResizeCursor()
            } else if logDrawerHeightAtDragStart == nil {
                popResizeCursor()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if logDrawerHeightAtDragStart == nil {
                        logDrawerHeightAtDragStart = logDrawerHeight
                        pushResizeCursor()
                    }
                    let proposed = (logDrawerHeightAtDragStart ?? logDrawerHeight) - value.translation.height
                    logDrawerHeight = min(max(proposed, 80), 500)
                }
                .onEnded { _ in
                    logDrawerHeightAtDragStart = nil
                    popResizeCursor()
                }
        )
    }

    private func pushResizeCursor() {
        guard !isResizeCursorPushed else { return }
        isResizeCursorPushed = true
        NSCursor.resizeUpDown.push()
    }

    private func popResizeCursor() {
        guard isResizeCursorPushed else { return }
        isResizeCursorPushed = false
        NSCursor.pop()
    }

    private func loadTranscriptIfNeeded(_ session: SessionRecord) {
        guard transcript == nil, loadError == nil, let jsonPath = session.jsonPath else { return }
        do {
            transcript = try SessionTranscript.load(from: URL(fileURLWithPath: jsonPath))
        } catch {
            loadError = "Couldn't read transcript: \(error.localizedDescription)"
        }
    }
}
