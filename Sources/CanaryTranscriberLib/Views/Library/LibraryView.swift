import SwiftUI
import UniformTypeIdentifiers
import CanaryTranscriberCore

struct LibraryView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @State private var searchText = ""
    @State private var showingNewRecording = false
    @State private var showingDiarizationSettings = false
    @State private var selectedIDs: Set<SessionRecord.ID> = []
    @State private var showingLogs = false
    @State private var logsPanelHeight: CGFloat = 180

    private var filteredSessions: [SessionRecord] {
        viewModel.librarySessions.filter { session in
            searchText.isEmpty || session.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedSessions: [(label: String, sessions: [SessionRecord])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredSessions) { session in
            calendar.startOfDay(for: session.createdAt)
        }
        return groups.keys.sorted(by: >).map { day in
            let label: String
            if calendar.isDateInToday(day) {
                label = "Today"
            } else if calendar.isDateInYesterday(day) {
                label = "Yesterday"
            } else {
                label = day.formatted(date: .abbreviated, time: .omitted)
            }
            let sessions = (groups[day] ?? []).sorted { $0.createdAt > $1.createdAt }
            return (label, sessions)
        }
    }

    var body: some View {
        NavigationStack {
            libraryList
                .navigationTitle("Library")
                .navigationDestination(for: SessionRecord.ID.self) { id in
                    if let session = viewModel.librarySessions.first(where: { $0.id == id }) {
                        SessionDetailView(viewModel: viewModel, sessionID: session.id)
                    }
                }
                .searchable(text: $searchText, placement: .toolbar, prompt: "Search sessions")
                .toolbar {
                    ToolbarItemGroup(placement: .automatic) {
                        if viewModel.isRunning {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Transcribing…").font(.caption)
                            }
                        }
                        if viewModel.appAudioCapture.isFinishing {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Finishing recording…").font(.caption)
                            }
                        }
                        Button("Add files") { viewModel.chooseAudioFiles() }
                            .disabled(viewModel.isRunning)
                        Button {
                            showingNewRecording = true
                        } label: {
                            Label("New Recording", systemImage: "plus.circle.fill")
                        }
                    }
                }
        }
        .sheet(isPresented: $showingNewRecording) {
            NewRecordingSheet(viewModel: viewModel, isPresented: $showingNewRecording)
        }
        .frame(minWidth: 1000, idealWidth: 1080, maxWidth: .infinity, minHeight: 720, idealHeight: 820, maxHeight: .infinity)
        .onAppear {
            viewModel.bringAppToFront()
            viewModel.refreshCaptureApps()
            viewModel.refreshMicrophones()
            viewModel.checkDependencies()
        }
    }

    @ViewBuilder
    private var libraryList: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(viewModel.isFileDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)

                if filteredSessions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(groupedSessions, id: \.label) { group in
                            Section(group.label) {
                                ForEach(group.sessions) { session in
                                    HStack(spacing: 10) {
                                        Button {
                                            toggleSelection(session.id)
                                        } label: {
                                            Image(systemName: selectedIDs.contains(session.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedIDs.contains(session.id) ? Color.accentColor : Color.secondary)
                                        }
                                        .buttonStyle(.plain)

                                        NavigationLink(value: session.id) {
                                            SessionRow(
                                                viewModel: viewModel,
                                                session: session,
                                                liveProgress: session.sourceAudioPath == viewModel.currentProcessingPath ? viewModel.lastProgressLine : nil
                                            )
                                        }
                                    }
                                    .swipeActions {
                                        Button("Delete", role: .destructive) {
                                            viewModel.removeSession(session.id)
                                        }
                                    }
                                    .contextMenu {
                                        Button(session.status == .processing ? "Stop & Delete" : "Delete", role: .destructive) {
                                            viewModel.removeSession(session.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $viewModel.isFileDropTargeted, perform: viewModel.handleFileDrop(providers:))

            if showingLogs {
                ResizableLogPanel(height: $logsPanelHeight, text: viewModel.logs.isEmpty ? "No log yet." : viewModel.logs)
            }

            actionBar
        }
    }

    private func toggleSelection(_ id: SessionRecord.ID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(viewModel.isFileDropTargeted ? Color.accentColor : Color.secondary)
            Text(viewModel.isFileDropTargeted ? "Release to add files" : "Nothing here yet")
                .font(.headline)
            Text("Drop audio/video here, or use Add files / New Recording")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Permanent action bar: acts on the checked sessions when any are selected,
    /// otherwise on the staged import queue (from Add files / New Recording).
    private var actionBar: some View {
        let hasSelection = !selectedIDs.isEmpty
        let count = hasSelection ? selectedIDs.count : viewModel.files.count
        let nothingToActOn = selectedIDs.isEmpty && viewModel.files.isEmpty

        return HStack(spacing: 8) {
            Text(hasSelection ? "Selected: \(count)" : "Ready to transcribe: \(count)")
                .foregroundStyle(.secondary)
            Spacer()
            Button(showingLogs ? "Hide logs" : "Logs") { showingLogs.toggle() }
            Button {
                showingDiarizationSettings = true
            } label: {
                Label(viewModel.diarizationEnabled ? "Speakers: \(viewModel.diarizationSpeakerCount)" : "Diarization", systemImage: "person.2")
            }
            .disabled(viewModel.isRunning)
            .popover(isPresented: $showingDiarizationSettings) {
                DiarizationQuickSettings(viewModel: viewModel)
            }
            Button(viewModel.isRunning ? "Transcribing..." : "Transcribe (\(count))") {
                if hasSelection {
                    viewModel.requeueForTranscription(sessionIDs: Array(selectedIDs), forceDiarization: false)
                    selectedIDs.removeAll()
                } else {
                    viewModel.startBatch()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isRunning || nothingToActOn)
            if viewModel.isRunning {
                Button("Stop") { viewModel.stopBatch() }
            }
            Button("Open output") {
                if hasSelection, let first = viewModel.librarySessions.first(where: { $0.id == selectedIDs.first }) {
                    viewModel.revealSessionOutput(first)
                } else {
                    viewModel.openOutputLocation()
                }
            }
            if hasSelection {
                Button("Delete (\(count))", role: .destructive) {
                    for id in selectedIDs {
                        viewModel.removeSession(id)
                    }
                    selectedIDs.removeAll()
                }
            }
            Button(hasSelection ? "Clear selection" : "Clear") {
                if hasSelection {
                    selectedIDs.removeAll()
                } else {
                    viewModel.clearQueuedFiles()
                }
            }
            .disabled(viewModel.isRunning && !hasSelection)
        }
        .padding(10)
        .background(.regularMaterial)
    }
}

private struct SessionRow: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    let session: SessionRecord
    var liveProgress: String?

    @State private var showingDiarizationPrompt = false
    @State private var draftLanguage: String
    @State private var draftSpeakerCount: String
    @State private var draftAliases: String

    init(viewModel: TranscriptionViewModel, session: SessionRecord, liveProgress: String?) {
        self.viewModel = viewModel
        self.session = session
        self.liveProgress = liveProgress
        _draftLanguage = State(initialValue: session.language)
        _draftSpeakerCount = State(initialValue: session.speakerCount.map(String.init) ?? "auto")
        _draftAliases = State(initialValue: viewModel.speakerAliasesText)
    }

    private var ext: String {
        URL(fileURLWithPath: session.sourceAudioPath).pathExtension.uppercased()
    }

    private var subtitle: String {
        var parts = [session.model]
        if session.diarizationEnabled {
            parts.append(session.speakerCount.map { "\($0) speakers" } ?? "diarization")
        }
        return parts.joined(separator: " · ")
    }

    private var hasOutput: Bool {
        session.jsonPath != nil || session.textPath != nil
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.75))
                .frame(width: 30, height: 30)
                .overlay(Text(ext).font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName).font(.body)
                if let liveProgress, !liveProgress.isEmpty {
                    Text(liveProgress)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            rowActions
            statusBadge
        }
        .padding(.vertical, 2)
    }

    private static let actionButtonWidth: CGFloat = 92

    private var rowActions: some View {
        HStack(spacing: 6) {
            actionButton("Diarization") {
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

            actionButton("Transcribe") {
                viewModel.requeueForTranscription(sessionIDs: [session.id], forceDiarization: false)
            }
            .disabled(viewModel.isRunning)

            actionButton("Stop") {
                viewModel.stopBatch()
            }
            .disabled(session.status != .processing)

            actionButton("Open output") {
                viewModel.revealSessionOutput(session)
            }
            .disabled(!hasOutput)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: Self.actionButtonWidth)
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch session.status {
            case .queued: return ("queued", .secondary)
            case .processing: return ("running", .orange)
            case .done: return ("done", .green)
            case .failed: return ("failed", .red)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .frame(width: 70)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

private struct DiarizationQuickSettings: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Diarization for this run")
                .font(.headline)

            Toggle("Speaker diarization (pyannote)", isOn: $viewModel.diarizationEnabled)

            HStack {
                Text("Language")
                TextField("ru", text: $viewModel.language)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text("Speakers")
                TextField("auto", text: $viewModel.diarizationSpeakerCount)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .disabled(!viewModel.diarizationEnabled)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Speaker aliases")
                    .foregroundStyle(.secondary)
                TextEditor(text: $viewModel.speakerAliasesText)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 280, height: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .disabled(!viewModel.diarizationEnabled)
                Text("One line per speaker: SPEAKER_00 = Alice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
