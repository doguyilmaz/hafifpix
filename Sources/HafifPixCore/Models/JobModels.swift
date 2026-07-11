import Foundation

public struct JobID: Hashable, Sendable {
    public let raw: UUID
    public init() { raw = UUID() }
}

public enum JobStatus: Sendable, Equatable {
    case pending
    case running(step: String)
    case optimized(originalBytes: Int64, newBytes: Int64)
    /// Converted to another format; the output is a sibling file.
    case converted(originalBytes: Int64, newBytes: Int64, outputURL: URL)
    case alreadyOptimal(bytes: Int64)
    case reverted(bytes: Int64)
    case failed(message: String)

    public var isFinished: Bool {
        switch self {
        case .pending, .running: false
        default: true
        }
    }
}

/// Event emitted by the engine as a job progresses. Delivered on the main actor.
public struct JobEvent: Sendable {
    public let id: JobID
    public let status: JobStatus

    public init(id: JobID, status: JobStatus) {
        self.id = id
        self.status = status
    }
}

/// A file accepted into the queue, resolved and format-detected.
public struct JobRequest: Sendable {
    public let id: JobID
    public let url: URL
    public let format: ImageFormat

    public init(id: JobID = JobID(), url: URL, format: ImageFormat) {
        self.id = id
        self.url = url
        self.format = format
    }
}
