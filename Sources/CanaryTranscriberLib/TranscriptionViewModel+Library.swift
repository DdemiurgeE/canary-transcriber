import Foundation
import AppKit
import CanaryTranscriberCore

/// Session library bookkeeping split out of TranscriptionViewModel.swift to keep that
/// file under SwiftLint's type_body_length limit.
extension TranscriptionViewModel {
    /// Called as soon as a file is staged (picker, drop, or a finished app-audio recording)
    /// so it shows up in the Library immediately, not only once Transcribe is pressed.
    func queueSession(for path: String) {
        activeSessionIDsByPath[path] = upsertSession(for: path, createdAt: Date(), config: nil)
        libraryStore.save(librarySessions)
    }

    /// Reconciles the queued rows with the config actually used for this run (settings may
    /// have changed since the file was staged). Re-transcribing/re-diarizing a file always
    /// updates its existing Library row in place — one row per source file, never a duplicate.
    func refreshQueuedSessions(for config: BatchConfig) {
        for path in config.files {
            activeSessionIDsByPath[path] = upsertSession(for: path, createdAt: Date(), config: config)
        }
        libraryStore.save(librarySessions)
    }

    private func upsertSession(for path: String, createdAt: Date, config: BatchConfig?) -> SessionRecord.ID {
        if let idx = librarySessions.firstIndex(where: { $0.sourceAudioPath == path }) {
            revertSnapshots[path] = librarySessions[idx]
            librarySessions[idx].createdAt = createdAt
            librarySessions[idx].profileID = config?.profileID ?? selectedProfileID
            librarySessions[idx].runtime = config?.runtime ?? runtime
            librarySessions[idx].model = config?.model ?? (model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedProfile.model : model)
            librarySessions[idx].language = config?.language ?? (language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedProfile.language : language)
            librarySessions[idx].diarizationEnabled = config?.diarization ?? diarizationEnabled
            librarySessions[idx].speakerCount = config?.speakerCount ?? Int(diarizationSpeakerCount.trimmingCharacters(in: .whitespacesAndNewlines))
            librarySessions[idx].status = .queued
            librarySessions[idx].errorMessage = nil
            return librarySessions[idx].id
        }
        let session = makeSessionRecord(path: path, createdAt: createdAt, config: config)
        librarySessions.append(session)
        return session.id
    }

    private func makeSessionRecord(path: String, createdAt: Date, config: BatchConfig? = nil) -> SessionRecord {
        SessionRecord(
            sourceAudioPath: path,
            displayName: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            createdAt: createdAt,
            profileID: config?.profileID ?? selectedProfileID,
            runtime: config?.runtime ?? runtime,
            model: config?.model ?? (model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedProfile.model : model),
            language: config?.language ?? (language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedProfile.language : language),
            diarizationEnabled: config?.diarization ?? diarizationEnabled,
            speakerCount: config?.speakerCount ?? Int(diarizationSpeakerCount.trimmingCharacters(in: .whitespacesAndNewlines)),
            status: .queued
        )
    }

    /// Removes a still-queued row (e.g. "Clear" on the batch bar) without touching history.
    func removeQueuedSession(for path: String) {
        guard let id = activeSessionIDsByPath[path] else { return }
        if let snapshot = revertSnapshots.removeValue(forKey: path), let idx = librarySessions.firstIndex(where: { $0.id == id }) {
            librarySessions[idx] = snapshot
        } else {
            librarySessions.removeAll { $0.id == id }
        }
        activeSessionIDsByPath[path] = nil
        logStartIndexByPath[path] = nil
        libraryStore.save(librarySessions)
    }

    func clearQueuedFiles() {
        for item in files {
            removeQueuedSession(for: item.path)
        }
        files.removeAll()
    }

    func removeSession(_ sessionID: SessionRecord.ID) {
        guard let session = librarySessions.first(where: { $0.id == sessionID }) else { return }
        if session.status == .queued || session.status == .processing {
            files.removeAll { $0.path == session.sourceAudioPath }
        }
        if isRunning, currentProcessingPath == session.sourceAudioPath {
            stopBatch()
        }
        librarySessions.removeAll { $0.id == sessionID }
        activeSessionIDsByPath[session.sourceAudioPath] = nil
        logStartIndexByPath[session.sourceAudioPath] = nil
        libraryStore.save(librarySessions)
    }

    /// A relaunch (crash, force-quit, manual restart) mid-batch leaves rows stuck on
    /// "processing"/"queued" forever, since nothing will ever emit their finishing event again.
    func reconcileStaleSessions() {
        var changed = false
        for idx in librarySessions.indices where librarySessions[idx].status == .processing || librarySessions[idx].status == .queued {
            librarySessions[idx].status = .failed
            librarySessions[idx].errorMessage = "Interrupted — the app was closed before transcription finished."
            changed = true
        }
        if changed {
            libraryStore.save(librarySessions)
        }
    }

    func updateSession(path: String, mutate: (inout SessionRecord) -> Void) {
        guard let sessionID = activeSessionIDsByPath[path],
              let idx = librarySessions.firstIndex(where: { $0.id == sessionID }) else { return }
        mutate(&librarySessions[idx])
        if let startIndex = logStartIndexByPath[path] {
            librarySessions[idx].logExcerpt = String(logs[startIndex...])
        }
        if librarySessions[idx].status == .done || librarySessions[idx].status == .failed {
            logStartIndexByPath[path] = nil
            activeSessionIDsByPath[path] = nil
        }
        libraryStore.save(librarySessions)
    }

    func setSpeakerAlias(_ alias: String, for speaker: String) {
        var aliases = parsedSpeakerAliases()
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            aliases.removeValue(forKey: speaker)
        } else {
            aliases[speaker] = trimmed
        }
        speakerAliasesText = SpeakerAliasPersistence.encode(aliases)
    }

    /// Re-queues one or more existing sessions for a fresh run, using the first session's
    /// profile for the whole batch (a run only ever has one active profile/config).
    func requeueForTranscription(sessionIDs: [SessionRecord.ID], forceDiarization: Bool) {
        guard !isRunning else { return }
        let sessions = librarySessions.filter { sessionIDs.contains($0.id) }
        guard !sessions.isEmpty else { return }
        files = sessions.map { AudioFileItem(path: $0.sourceAudioPath, status: "queued") }
        if let first = sessions.first {
            selectedProfileID = first.profileID
            applySelectedProfile()
        }
        if forceDiarization {
            diarizationEnabled = true
        }
        startBatch()
    }

    func requeueForDiarization(sessionID: SessionRecord.ID) {
        requeueForTranscription(sessionIDs: [sessionID], forceDiarization: true)
    }

    func revealSessionOutput(_ session: SessionRecord) {
        let path = session.jsonPath ?? session.textPath ?? session.sourceAudioPath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
