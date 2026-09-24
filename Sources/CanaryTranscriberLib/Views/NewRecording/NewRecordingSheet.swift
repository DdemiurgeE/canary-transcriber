import SwiftUI

private enum RecordingSource: String, CaseIterable, Identifiable {
    case capture = "Capture App"
    case importFile = "Import File"
    var id: String { rawValue }
}

struct NewRecordingSheet: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @Binding var isPresented: Bool
    @Binding var isExpanded: Bool
    @State private var source: RecordingSource = .capture

    private var recordingActive: Bool {
        viewModel.appAudioCapture.isRecording
    }

    private var finishing: Bool {
        viewModel.appAudioCapture.isFinishing
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedPanel
            } else if recordingActive || finishing {
                compactStatusBar
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
        .onChange(of: recordingActive) { _, isRecording in
            if isRecording {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded = false
                }
            }
        }
        .onChange(of: finishing) { _, isFinishing in
            if isFinishing {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded = false
                }
            }
        }
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("New Recording", systemImage: "waveform.badge.plus")
                    .font(.title3.weight(.semibold))
                Spacer()
                if recordingActive || finishing {
                    Text(finishing ? "Finishing…" : "Recording…")
                        .font(.caption)
                        .foregroundStyle(finishing ? Color.secondary : Color.red)
                }
                Button {
                    if recordingActive || finishing {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isExpanded = false
                        }
                    } else {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .help("Collapse recording panel")
                Button {
                    if recordingActive || finishing {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isExpanded = false
                        }
                    } else {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close recording panel")
            }

            Picker("", selection: $source) {
                ForEach(RecordingSource.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            switch source {
            case .capture:
                AppAudioCaptureView(viewModel: viewModel)
            case .importFile:
                importTab
            }

            HStack(spacing: 8) {
                Text("Profile")
                Picker("", selection: $viewModel.selectedProfileID) {
                    ForEach(viewModel.profiles) { profile in
                        Text(profile.title).tag(profile.id)
                    }
                }
                .labelsHidden()
                .frame(width: 260)
                .onChange(of: viewModel.selectedProfileID) { viewModel.applySelectedProfile() }

                Text("Language")
                TextField("ru", text: $viewModel.language)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)

                Spacer()
                SettingsLink {
                    Text("Advanced Settings")
                        .font(.caption)
                }
            }

            Divider()

            HStack {
                Button(recordingActive || finishing ? "Collapse" : "Close") {
                    if recordingActive || finishing {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isExpanded = false
                        }
                    } else {
                        isPresented = false
                    }
                }
                Spacer()
                if recordingActive || finishing {
                    Button("Stop recording") {
                        viewModel.stopAppAudioCapture()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!recordingActive)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.2))
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private var compactStatusBar: some View {
        activeRecordingStatusBar
    }

    private var activeRecordingStatusBar: some View {
        HStack(spacing: 10) {
            Image(systemName: finishing ? "hourglass" : "record.circle")
                .foregroundStyle(finishing ? Color.secondary : Color.red)
                .symbolEffect(.pulse, isActive: recordingActive)

            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 1) {
                Text(finishing ? "Finishing recording" : "Recording app audio")
                    .font(.callout.weight(.semibold))
                Text(finishing ? "Mixing audio — click to show details" : "Click to show recording details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if recordingActive {
                Button {
                    viewModel.stopAppAudioCapture()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .help("Stop recording")
            }

            Image(systemName: "chevron.up")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.22)) {
                isExpanded = true
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.2))
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }


    private var importTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Add files") { viewModel.chooseAudioFiles() }
                Text("Selected: \(viewModel.files.count)")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text("Files land in the Library queue — start Transcribe from there.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
