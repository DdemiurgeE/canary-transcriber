import SwiftUI

public struct SettingsRootView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    public init(viewModel: TranscriptionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView {
            GeneralSettingsView(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }

            ScrollView {
                DependencyPanelView(viewModel: viewModel)
                    .padding()
            }
            .frame(width: 520, height: 560)
            .tabItem { Label("Models", systemImage: "shippingbox") }
        }
    }
}
