import SwiftUI

/// Edit processing options for an already saved recording before starting a new run.
/// Dismissing the popover never changes the active batch configuration.
struct PostRecordingRunPrompt: View {
    @Binding var settings: PostRecordingRunSettings
    let profiles: [TranscriptionProfile]
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription settings").font(.headline)
            Picker("Profile", selection: $settings.profileID) {
                ForEach(profiles) { profile in
                    Text(profile.title).tag(profile.id)
                }
            }
            if let profile = profiles.first(where: { $0.id == settings.profileID }) {
                Text(profile.model).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Text("Language")
                TextField("ru", text: $settings.language)
                    .textFieldStyle(.roundedBorder).frame(width: 65)
                Text("Chunk sec")
                TextField("30", text: $settings.chunkDuration)
                    .textFieldStyle(.roundedBorder).frame(width: 65)
            }
            Toggle("Timestamps", isOn: $settings.timestamps)
            Toggle("Speaker diarization (pyannote)", isOn: $settings.diarization)
            if settings.diarization {
                HStack {
                    Text("Speakers")
                    TextField("auto", text: $settings.speakerCount)
                        .textFieldStyle(.roundedBorder).frame(width: 75)
                }
                Text("Speaker names (optional)").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $settings.aliasesText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 65)
                Text("One line per speaker: SPEAKER_00 = Alice")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Transcribe", action: onRun)
                    .buttonStyle(.borderedProminent)
                    .disabled(!settings.isValid || !profiles.contains(where: { $0.id == settings.profileID }))
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
