import Foundation

public struct RuntimeInvocation: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public enum RuntimeInvocationBuilder {
    public static func make(
        runtime: String,
        model: String,
        audioPath: String,
        language: String,
        timestamps: Bool = false
    ) throws -> RuntimeInvocation {
        guard !model.isEmpty, !audioPath.isEmpty else {
            throw Error.missingRequiredValue
        }

        switch runtime {
        case "mlx_audio_cli":
            var arguments = ["-m", "mlx_audio.stt.generate", "--model", model, "--audio", audioPath]
            if !language.isEmpty {
                arguments += ["--language", language, "--gen-kwargs", "{\"source_lang\":\"\(language)\",\"target_lang\":\"\(language)\"}"]
            }
            if timestamps {
                arguments += ["--timestamps"]
            }
            return RuntimeInvocation(executable: "python", arguments: arguments)
        case "mlx_whisper":
            var arguments = ["-m", "mlx_whisper", "--model", model, "--audio", audioPath]
            if !language.isEmpty { arguments += ["--language", language] }
            if timestamps { arguments += ["--word_timestamps", "true"] }
            return RuntimeInvocation(executable: "python", arguments: arguments)
        case "canary_mlx":
            return RuntimeInvocation(
                executable: "python",
                arguments: ["-m", "canary_mlx", "--model", model, "--audio", audioPath, "--language", language]
            )
        default:
            throw Error.unsupportedRuntime(runtime)
        }
    }

    public enum Error: Swift.Error, Equatable, LocalizedError {
        case missingRequiredValue
        case unsupportedRuntime(String)

        public var errorDescription: String? {
            switch self {
            case .missingRequiredValue:
                return "Runtime invocation requires a model and audio path."
            case .unsupportedRuntime(let runtime):
                return "Unsupported runtime: \(runtime)"
            }
        }
    }
}
