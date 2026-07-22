import SwiftUI

struct HeaderView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        HStack {
            if viewModel.isRunning {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("running")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 20)
    }


}
