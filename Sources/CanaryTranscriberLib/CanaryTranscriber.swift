import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import AudioToolbox
import ScreenCaptureKit
import CanaryTranscriberCore

struct AudioFileItem: Identifiable, Hashable {
    let id = UUID()
    let path: String
    var status: String = "pending"

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: AudioFileItem, rhs: AudioFileItem) -> Bool { lhs.id == rhs.id }
}

struct TranscriptionProfile: Identifiable, Hashable {
    let id: String
    let title: String
    let runtime: String
    let model: String
    let language: String
    let chunkDuration: String
    let details: String
}


struct CaptureAppTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let processID: pid_t

    var title: String {
        let bundle = bundleIdentifier.isEmpty ? "unknown bundle" : bundleIdentifier
        return "\(name) (pid \(processID), \(bundle))"
    }
}

struct MicrophoneDeviceTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let modelID: String
    let manufacturer: String

    var title: String {
        let vendor = manufacturer.isEmpty ? "" : " — \(manufacturer)"
        return "\(name)\(vendor)"
    }
}

enum DependencyStatus {
    case unknown
    case checking
    case present
    case missing
    case downloaded
    case downloading
    case updatable
}

struct FastTooltipModifier: ViewModifier {
    let text: String
    @State private var show = false
    private let delay: Double = 0.35

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if show {
                    Text(text)
                        .font(.caption)
                        .padding(6)
                        .background(.regularMaterial)
                        .cornerRadius(4)
                        .fixedSize()
                        .offset(y: 32)
                        .transition(.opacity.animation(.easeInOut(duration: 0.1)))
                }
            }
            .onHover { hovering in
                if hovering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        show = true
                    }
                } else {
                    show = false
                }
            }
    }
}

extension View {
    func fastTooltip(_ text: String) -> some View {
        modifier(FastTooltipModifier(text: text))
    }
}

public struct ContentView: View {
    @StateObject private var viewModel: TranscriptionViewModel

    public init() {
        _viewModel = StateObject(wrappedValue: TranscriptionViewModel())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView(viewModel: viewModel)
            DependencyPanelView(viewModel: viewModel)
            SettingsView(viewModel: viewModel)
            AppAudioCaptureView(viewModel: viewModel)
            FilesView(viewModel: viewModel)
            ControlsPanelView(viewModel: viewModel)
            LogView(viewModel: viewModel)
        }
        .padding(16)
        .frame(minWidth: 1080, idealWidth: 1120, minHeight: 820, idealHeight: 900)
        .onAppear {
            viewModel.bringAppToFront()
            viewModel.refreshCaptureApps()
            viewModel.refreshMicrophones()
            viewModel.checkDependencies()
        }
    }
}
