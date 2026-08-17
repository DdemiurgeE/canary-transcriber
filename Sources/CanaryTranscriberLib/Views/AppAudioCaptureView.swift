import SwiftUI

struct AppAudioCaptureView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        GroupBox("App Audio Capture — ScreenCaptureKit") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Picker("Application", selection: $viewModel.selectedCaptureAppID) {
                        Text(viewModel.captureApps.isEmpty ? "Press Refresh apps" : "Select an application").tag(Optional<CaptureAppTarget.ID>.none)
                        ForEach(viewModel.captureApps) { app in
                            Text(app.title).tag(Optional(app.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 400)
                    .disabled(viewModel.appAudioCapture.isRecording || viewModel.isRunning)

                    Button(viewModel.isRefreshingCaptureApps ? "Refreshing..." : "Refresh apps") { viewModel.refreshCaptureApps() }
                        .disabled(viewModel.isRefreshingCaptureApps || viewModel.appAudioCapture.isRecording || viewModel.isRunning)

                    Spacer()

                    HStack(spacing: 4) {
                        Button(action: { viewModel.startAppAudioCapture(withMic: false) }) {
                            Image(systemName: "app.badge")
                                .font(.title)
                        }
                        .help("Record app audio only (no microphone)")
                        .disabled(viewModel.appAudioCapture.isRecording || viewModel.isRunning || viewModel.selectedCaptureApp == nil)

                        Button(action: { viewModel.startAppAudioCapture(withMic: true) }) {
                            Image(systemName: "waveform.badge.mic")
                                .font(.title)
                        }
                        .help("Record app audio + microphone")
                        .disabled(viewModel.appAudioCapture.isRecording || viewModel.isRunning || viewModel.selectedCaptureApp == nil)

                        Button(action: { viewModel.stopAppAudioCapture() }) {
                            Image(systemName: "stop.fill")
                                .font(.title)
                        }
                        .help("Stop recording")
                        .disabled(!viewModel.appAudioCapture.isRecording)

                        Button(action: { viewModel.startLiveCapture() }) {
                            Image(systemName: "waveform.badge.plus")
                                .font(.title)
                        }
                        .help("Start live transcription of app audio")
                        .disabled(viewModel.liveAppCapture.isCapturing || viewModel.liveAppCapture.isFinishing || viewModel.selectedCaptureApp == nil)

                        Button(action: { viewModel.stopLiveCapture() }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.title)
                        }
                        .help("Stop live transcription")
                        .disabled(!viewModel.liveAppCapture.isCapturing)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                HStack(spacing: 8) {
                    Picker("Microphone", selection: $viewModel.selectedMicrophoneID) {
                        Text(viewModel.microphoneDevices.isEmpty ? "System default microphone" : "System default microphone").tag(Optional<MicrophoneDeviceTarget.ID>.none)
                        ForEach(viewModel.microphoneDevices) { mic in
                            Text(mic.title).tag(Optional(mic.id))
                        }
                    }
                    .frame(maxWidth: 360)
                    .disabled(!viewModel.captureMicrophone || viewModel.appAudioCapture.isRecording || viewModel.isRunning)

                    Button("Refresh mics") { viewModel.refreshMicrophones() }
                        .disabled(viewModel.appAudioCapture.isRecording || viewModel.isRunning)
                }

                if viewModel.isLiveTranscribing || !viewModel.liveTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Live Transcript")
                                .font(.headline)
                            if viewModel.isLiveTranscribing {
                                ProgressView().controlSize(.small)
                                Text("transcribing")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ScrollView {
                            Text(viewModel.liveTranscript.isEmpty ? "Waiting for the first audio window…" : viewModel.liveTranscript)
                                .font(.body.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 80, maxHeight: 180)
                        .padding(8)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                if viewModel.appAudioCapture.isFinishing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Finishing up — mixing app audio + microphone, this can take a moment for long recordings…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }


}
