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

public struct ContentView: View {
    @ObservedObject private var viewModel: TranscriptionViewModel

    public init(viewModel: TranscriptionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        LibraryView(viewModel: viewModel)
    }
}
