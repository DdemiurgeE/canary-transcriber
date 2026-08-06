import SwiftUI

/// Prompt shown before (re-)running diarization on a specific recording: lets the user
/// confirm language, speaker count, and optionally pre-assign speaker names for this run.
struct DiarizationRunPrompt: View {
    @Binding var language: String
    @Binding var speakerCount: String
    @Binding var aliasesText: String
    var onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Run diarization")
                .font(.headline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Language").font(.caption).foregroundStyle(.secondary)
                    TextField("ru", text: $language)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speakers").font(.caption).foregroundStyle(.secondary)
                    TextField("auto", text: $speakerCount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Speaker names (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $aliasesText)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 280, height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                Text("One line per speaker: SPEAKER_00 = Alice")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Run", action: onRun)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
