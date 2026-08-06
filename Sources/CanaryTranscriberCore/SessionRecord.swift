import Foundation

public struct SessionRecord: Codable, Equatable, Identifiable {
    public enum Status: String, Codable, Equatable {
        case queued
        case processing
        case done
        case failed
    }

    public let id: UUID
    public var sourceAudioPath: String
    public var displayName: String
    public var createdAt: Date
    public var profileID: String
    public var runtime: String
    public var model: String
    public var language: String
    public var diarizationEnabled: Bool
    public var speakerCount: Int?
    public var status: Status
    public var errorMessage: String?
    public var textPath: String?
    public var jsonPath: String?
    public var markdownPath: String?
    public var logExcerpt: String

    public init(
        id: UUID = UUID(),
        sourceAudioPath: String,
        displayName: String,
        createdAt: Date,
        profileID: String,
        runtime: String,
        model: String,
        language: String,
        diarizationEnabled: Bool,
        speakerCount: Int? = nil,
        status: Status = .queued,
        errorMessage: String? = nil,
        textPath: String? = nil,
        jsonPath: String? = nil,
        markdownPath: String? = nil,
        logExcerpt: String = ""
    ) {
        self.id = id
        self.sourceAudioPath = sourceAudioPath
        self.displayName = displayName
        self.createdAt = createdAt
        self.profileID = profileID
        self.runtime = runtime
        self.model = model
        self.language = language
        self.diarizationEnabled = diarizationEnabled
        self.speakerCount = speakerCount
        self.status = status
        self.errorMessage = errorMessage
        self.textPath = textPath
        self.jsonPath = jsonPath
        self.markdownPath = markdownPath
        self.logExcerpt = logExcerpt
    }
}
