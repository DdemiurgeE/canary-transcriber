import SwiftUI

struct ControlsPanelView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        HStack(spacing: 8) {
            Button(viewModel.isRunning ? "Transcribing..." : "Transcribe") { viewModel.startBatch() }
                .disabled(viewModel.isRunning || viewModel.files.isEmpty)

            Button("Stop") { viewModel.stopBatch() }
                .disabled(!viewModel.isRunning)

            Button("Open output") { viewModel.openOutputLocation() }

            Button("Clear viewModel.logs") { viewModel.logs = "" }
        }
    }


}
