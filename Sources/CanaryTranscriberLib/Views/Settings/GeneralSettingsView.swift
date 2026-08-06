import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        Form {
            Section("Profile") {
                HStack {
                    Picker("Profile", selection: $viewModel.selectedProfileID) {
                        ForEach(viewModel.profiles) { profile in
                            Text(profile.title).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: viewModel.selectedProfileID) { viewModel.applySelectedProfile() }
                    Text(viewModel.selectedProfile.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Model")
                    Text(viewModel.model.isEmpty ? viewModel.selectedProfile.model : viewModel.model)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Runtime") {
                HStack {
                    Text("Python venv")
                    TextField("/path/to/venv/bin/python", text: $viewModel.pythonPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose") { viewModel.choosePython() }
                }

                HStack {
                    Picker("Runtime", selection: $viewModel.runtime) {
                        Text("mlx-audio CLI").tag("mlx_audio_cli")
                        Text("mlx-whisper").tag("mlx_whisper")
                        Text("canary-mlx legacy").tag("canary_mlx")
                    }
                    .frame(width: 220)

                    Text("Lang")
                    TextField("ru", text: $viewModel.language)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)

                    Text("Chunk sec")
                    TextField("30", text: $viewModel.chunkDuration)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }

                Toggle("Timestamps", isOn: $viewModel.timestamps)
            }

            Section("Output") {
                Toggle("Save alongside source file", isOn: $viewModel.writeNextToSource)

                HStack {
                    Text("Output folder")
                    TextField("/path/to/output", text: $viewModel.outputFolder)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.writeNextToSource)
                    Button("Choose") { viewModel.chooseOutputFolder() }
                        .disabled(viewModel.writeNextToSource)
                }

                Toggle("Separate folder for .md", isOn: $viewModel.separateMarkdownOutput)

                HStack {
                    Text("Markdown folder")
                    TextField("/path/to/notes", text: $viewModel.markdownOutputFolder)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!viewModel.separateMarkdownOutput)
                    Button("Choose") { viewModel.chooseMarkdownOutputFolder() }
                        .disabled(!viewModel.separateMarkdownOutput)
                }
                Text("Useful if you want .md files to land straight in another vault (e.g. Obsidian) without touching .txt/.json.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Diarization defaults") {
                HStack(spacing: 8) {
                    Toggle("Speaker diarization (pyannote)", isOn: $viewModel.diarizationEnabled)
                    Text("Speakers")
                        .foregroundStyle(.secondary)
                    TextField("auto", text: $viewModel.diarizationSpeakerCount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .disabled(!viewModel.diarizationEnabled)
                }
                Text("Rename individual speakers from within a session by tapping their tag.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
    }
}
