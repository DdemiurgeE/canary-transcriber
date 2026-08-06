import SwiftUI
import AppKit
import CanaryTranscriber
import Sparkle

@main
struct CanaryTranscriberApp: App {
    @StateObject private var viewModel = TranscriptionViewModel()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowResizability(.automatic)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
                Button("About Canary Transcriber") {
                    let credits = NSAttributedString(
                        string: """
Canary Transcriber — macOS GUI for batch transcription of audio/video files using local MLX STT runtimes.

Profiles:
• fast-parakeet-v3: NVIDIA Parakeet TDT 0.6B v3 via mlx-audio
• fast-whisper-turbo: Whisper large-v3-turbo via mlx-whisper
• accurate-whisper-large-v3: Whisper large-v3-mlx via mlx-whisper
• multilingual-canary-v2: CogniSoftOrg/canary-1b-v2-mlx-bf16 via mlx-audio
• realtime-voxtral-mini: Voxtral Mini 4B Realtime via mlx-audio

Features: ScreenCaptureKit per-app audio capture, AVAudioEngine microphone recording, mic-priority ffmpeg mix, automated dependency setup, model download via HuggingFace Hub.

License: MIT
""",
                        attributes: [.font: NSFont.systemFont(ofSize: 11)]
                    )
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [.credits: credits]
                    )
                }
            }
        }

        Settings {
            SettingsRootView(viewModel: viewModel)
        }
    }
}
