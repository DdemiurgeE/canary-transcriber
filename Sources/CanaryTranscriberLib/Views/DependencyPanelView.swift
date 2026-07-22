import SwiftUI

struct DependencyPanelView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        GroupBox("Dependencies & Models") {
            VStack(alignment: .leading, spacing: 8) {
                // ffmpeg
                HStack(spacing: 8) {
                    viewModel.statusDot(viewModel.ffmpegStatus)
                    Text("ffmpeg").frame(width: 90, alignment: .leading)
                    Text(viewModel.ffmpegStatusLabel(viewModel.ffmpegStatus)).foregroundStyle(.secondary)
                    Spacer()
                    switch viewModel.ffmpegStatus {
                    case .missing:
                        Button(viewModel.isInstallingFFmpeg ? "Installing..." : "Install ffmpeg") { viewModel.installFFmpeg() }
                            .disabled(viewModel.isInstallingFFmpeg)
                    default:
                        EmptyView()
                    }
                }

                // Python venv
                HStack(spacing: 8) {
                    viewModel.statusDot(viewModel.pythonStatus)
                    Text("Python venv").frame(width: 90, alignment: .leading)
                    Text(viewModel.pythonStatusLabel(viewModel.pythonStatus)).foregroundStyle(.secondary)
                    Spacer()
                    switch viewModel.pythonStatus {
                    case .missing:
                        Button(viewModel.isSettingUpPython ? "Setting up..." : "Setup venv") { viewModel.setupPythonEnvironment() }
                            .disabled(viewModel.isSettingUpPython || viewModel.isRunning)
                    default:
                        EmptyView()
                    }
                }

                Divider()

                // Selected viewModel.model
                let modelID = viewModel.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? viewModel.selectedProfile.model : viewModel.model.trimmingCharacters(in: .whitespacesAndNewlines)
                let modelStatus = viewModel.modelDownloadStatus[modelID] ?? .unknown
                HStack(spacing: 8) {
                    viewModel.statusDot(modelStatus)
                    Text("Model").frame(width: 90, alignment: .leading)
                    Text(modelID).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Spacer()
                    switch modelStatus {
                    case .downloaded:
                        Text("✓ cached").foregroundStyle(.green).font(.caption)
                    case .downloading:
                        ProgressView().controlSize(.small)
                    case .missing, .unknown:
                        Button(viewModel.isDownloadingModel ? "Downloading..." : "Download model") { viewModel.downloadModel(modelID) }
                            .disabled(viewModel.isDownloadingModel || viewModel.isRunning)
                    case .updatable:
                        HStack(spacing: 4) {
                            Text("update available").font(.caption).foregroundStyle(.orange)
                            Button("Update") { viewModel.downloadModel(modelID) }
                                .disabled(viewModel.isDownloadingModel || viewModel.isRunning)
                                .controlSize(.small)
                        }
                    case .checking:
                        Text("Checking...").foregroundStyle(.secondary).font(.caption)
                    case .present:
                        Text("✓ installed").foregroundStyle(.green).font(.caption)
                    }
                }

                Text("Dependencies: brew / pip / venv. Models download from HuggingFace Hub.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }


}
