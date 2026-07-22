import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        GroupBox("Settings") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Profile")
                        .frame(width: 120, alignment: .leading)
                    Picker("Profile", selection: $viewModel.selectedProfileID) {
                        ForEach(viewModel.profiles) { profile in
                            Text(profile.title).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)
                    .onChange(of: viewModel.selectedProfileID) { viewModel.applySelectedProfile() }
                    Text(viewModel.selectedProfile.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack {
                    Text("Python venv")
                        .frame(width: 120, alignment: .leading)
                    TextField("/path/to/venv/bin/python", text: $viewModel.pythonPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose") { viewModel.choosePython() }
                }

                HStack {
                    Text("Runtime")
                        .frame(width: 120, alignment: .leading)
                    Picker("Runtime", selection: $viewModel.runtime) {
                        Text("mlx-audio CLI").tag("mlx_audio_cli")
                        Text("mlx-whisper").tag("mlx_whisper")
                        Text("canary-mlx legacy").tag("canary_mlx")
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    Text("Lang")
                    TextField("ru", text: $viewModel.language)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)

                    Text("Chunk sec")
                    TextField("30", text: $viewModel.chunkDuration)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)

                    Toggle("viewModel.timestamps", isOn: $viewModel.timestamps)
                        .toggleStyle(.checkbox)
                }

                Toggle("Save alongside source file", isOn: $viewModel.writeNextToSource)
                    .toggleStyle(.checkbox)

                HStack {
                    Text("Model")
                        .frame(width: 120, alignment: .leading)
                    Text(viewModel.model.isEmpty ? viewModel.selectedProfile.model : viewModel.model)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack {
                    Text("Output folder")
                        .frame(width: 120, alignment: .leading)
                    TextField("/path/to/output", text: $viewModel.outputFolder)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.writeNextToSource)
                    Button("Choose") { viewModel.chooseOutputFolder() }
                        .disabled(viewModel.writeNextToSource)
                }

                HStack(spacing: 8) {
                    Toggle("Speaker diarization (pyannote)", isOn: $viewModel.diarizationEnabled)
                        .toggleStyle(.checkbox)
                    Text("Speakers")
                        .foregroundStyle(.secondary)
                    TextField("auto", text: $viewModel.diarizationSpeakerCount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .disabled(!viewModel.diarizationEnabled)
                }

                if viewModel.diarizationEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Speaker aliases")
                            .foregroundStyle(.secondary)
                        TextEditor(text: $viewModel.speakerAliasesText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 72, maxHeight: 96)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                        Text("One mapping per line: SPEAKER_00 = Alice")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }




}
