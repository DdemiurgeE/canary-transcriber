import SwiftUI

private enum RecordingSource: String, CaseIterable, Identifiable {
    case capture = "Capture App"
    case importFile = "Import File"
    var id: String { rawValue }
}

struct NewRecordingSheet: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @Binding var isPresented: Bool
    @State private var source: RecordingSource = .capture

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Recording")
                .font(.title3.weight(.semibold))

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
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 620)
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
