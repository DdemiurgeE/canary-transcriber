import Foundation

public enum TranscriptionEvent: Equatable {
    case batchStarted(totalFiles: Int)
    case fileStarted(path: String, index: Int)
    case stage(name: String, file: String?)
    case chunkCompleted(index: Int, start: Double, chars: Int)
    case fileCompleted(path: String, textPath: String?, jsonPath: String?, markdownPath: String?, chars: Int?)
    case fileFailed(path: String, message: String)
    case warning(message: String)
    case error(message: String, code: Int?)
    case batchCompleted(success: Bool, message: String?)
    case unknown(kind: String, payload: [String: String])
}

public enum TranscriptionEventParser {
    public enum ParseError: Error, Equatable {
        case invalidPrefix
        case invalidJSON
        case missingKind
    }

    private static let prefix = "CANARY_EVENT "

    public static func parseLine(_ line: String) -> TranscriptionEvent? {
        guard line.hasPrefix(prefix) else { return nil }
        return try? parse(line)
    }

    public static func parse(_ line: String) throws -> TranscriptionEvent {
        guard line.hasPrefix(prefix) else { throw ParseError.invalidPrefix }
        let json = String(line.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        guard let kind = payload["kind"] as? String, !kind.isEmpty else {
            throw ParseError.missingKind
        }

        switch kind {
        case "batch_start":
            return .batchStarted(totalFiles: int(payload, "total") ?? int(payload, "files") ?? 0)
        case "file_start", "file_started":
            return .fileStarted(path: string(payload, "file") ?? string(payload, "path") ?? "", index: int(payload, "index") ?? 0)
        case "stage":
            return .stage(name: string(payload, "name") ?? string(payload, "stage") ?? "", file: string(payload, "file") ?? string(payload, "path"))
        case "chunk_done":
            return .chunkCompleted(index: int(payload, "index") ?? 0, start: double(payload, "start") ?? 0, chars: int(payload, "chars") ?? 0)
        case "file_done":
            return .fileCompleted(
                path: string(payload, "file") ?? string(payload, "path") ?? "",
                textPath: string(payload, "txt"),
                jsonPath: string(payload, "json"),
                markdownPath: string(payload, "md"),
                chars: int(payload, "chars")
            )
        case "file_failed":
            return .fileFailed(path: string(payload, "file") ?? string(payload, "path") ?? "", message: string(payload, "error") ?? string(payload, "message") ?? "unknown")
        case "warning":
            return .warning(message: string(payload, "message") ?? "")
        case "error":
            return .error(message: string(payload, "message") ?? "", code: int(payload, "code"))
        case "batch_done":
            let failed = int(payload, "failed") ?? 0
            let success = bool(payload, "success") ?? (failed == 0)
            return .batchCompleted(success: success, message: string(payload, "message") ?? "ok=\(int(payload, "ok") ?? 0), failed=\(failed), total=\(int(payload, "total") ?? 0)")
        default:
            return .unknown(kind: kind, payload: payload.reduce(into: [:]) { result, item in
                if let value = item.value as? Bool { result[item.key] = value ? "true" : "false" }
                else if let value = item.value as? CustomStringConvertible { result[item.key] = value.description }
            })
        }
    }

    private static func string(_ payload: [String: Any], _ key: String) -> String? {
        payload[key] as? String
    }

    private static func int(_ payload: [String: Any], _ key: String) -> Int? {
        if let value = payload[key] as? Int { return value }
        if let value = payload[key] as? NSNumber { return value.intValue }
        return nil
    }

    private static func double(_ payload: [String: Any], _ key: String) -> Double? {
        if let value = payload[key] as? Double { return value }
        if let value = payload[key] as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func bool(_ payload: [String: Any], _ key: String) -> Bool? {
        if let value = payload[key] as? Bool { return value }
        if let value = payload[key] as? NSNumber { return value.boolValue }
        return nil
    }
}
