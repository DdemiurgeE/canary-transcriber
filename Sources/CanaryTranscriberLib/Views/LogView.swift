import SwiftUI

struct LogView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Log")
                .font(.headline)
            ScrollView {
                Text(viewModel.logs)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180, idealHeight: 220, maxHeight: .infinity)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
    }




}
