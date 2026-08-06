import SwiftUI

/// Presentation helpers for DependencyPanelView, split out of TranscriptionViewModel.swift
/// to keep that file under SwiftLint's type_body_length limit.
extension TranscriptionViewModel {
    func statusDot(_ status: DependencyStatus) -> some View {
        Circle()
            .fill(statusDotColor(status))
            .frame(width: 10, height: 10)
    }

    func statusDotColor(_ status: DependencyStatus) -> Color {
        switch status {
        case .present, .downloaded: return .green
        case .checking, .downloading, .updatable: return .orange
        case .missing: return .red
        case .unknown: return .gray
        }
    }

    func ffmpegStatusLabel(_ status: DependencyStatus) -> String {
        switch status {
        case .unknown, .checking: return "Checking..."
        case .present: return "Installed"
        case .missing: return "Not found"
        case .downloaded, .downloading: return ""
        case .updatable: return ""
        }
    }

    func pythonStatusLabel(_ status: DependencyStatus) -> String {
        switch status {
        case .unknown, .checking: return "Checking..."
        case .present: return "Ready"
        case .missing: return "Not found — setup venv"
        case .downloaded, .downloading: return ""
        case .updatable: return ""
        }
    }
}
