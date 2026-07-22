import SwiftUI

struct FilesView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        GroupBox("Files") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Add viewModel.files") { viewModel.chooseAudioFiles() }
                        .disabled(viewModel.isRunning)
                    Button("Remove selected") { viewModel.removeSelectedFile() }
                        .disabled(viewModel.isRunning || viewModel.selectedFileID == nil)
                    Button("Clear list") { viewModel.files.removeAll() }
                        .disabled(viewModel.isRunning || viewModel.files.isEmpty)
                    Text("Selected: \(viewModel.files.count)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Drag & drop audio/video viewModel.files here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(viewModel.isFileDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    viewModel.isFileDropTargeted ? Color.accentColor : Color.secondary.opacity(viewModel.files.isEmpty ? 0.45 : 0.15),
                                    style: StrokeStyle(lineWidth: viewModel.isFileDropTargeted ? 2 : 1, dash: viewModel.files.isEmpty ? [6, 5] : [])
                                )
                        )

                    List(selection: $viewModel.selectedFileID) {
                        ForEach(viewModel.files) { item in
                            HStack {
                                Text(item.status)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 90, alignment: .leading)
                                    .foregroundStyle(viewModel.colorForStatus(item.status))
                                Text(item.path)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .tag(item.id)
                        }
                    }
                    .opacity(viewModel.files.isEmpty ? 0.35 : 1)
                    .padding(4)

                    if viewModel.files.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform.badge.plus")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(viewModel.isFileDropTargeted ? Color.accentColor : Color.secondary)
                            Text(viewModel.isFileDropTargeted ? "Release to add viewModel.files" : "Drop audio/video viewModel.files here")
                                .font(.headline)
                            Text("or click Add viewModel.files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 180, idealHeight: 210, maxHeight: 240)
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL], isTargeted: $viewModel.isFileDropTargeted, perform: viewModel.handleFileDrop(providers:))
            }
            .padding(.vertical, 4)
        }
    }


}
