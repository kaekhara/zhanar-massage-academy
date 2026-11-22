import Foundation

public struct LocalResumeCheckpoint: Codable, Equatable {
    public let positionSeconds: Double
    public let updatedAt: Date

    public init(positionSeconds: Double, updatedAt: Date) {
        self.positionSeconds = positionSeconds
        self.updatedAt = updatedAt
    }
}

/// Deterministic merge rules for the device and server copies of lesson resume state.
public enum ResumeCheckpointPolicy {
    /// Newer timestamps win. On a tie, the server copy is treated as canonical.
    public static func merge(
        local: [String: LocalResumeCheckpoint],
        server: [String: LocalResumeCheckpoint]
    ) -> [String: LocalResumeCheckpoint] {
        var merged = server.filter { isValid($0.value) }
        for (lessonID, checkpoint) in local where isValid(checkpoint) {
            guard let serverCheckpoint = merged[lessonID], serverCheckpoint.updatedAt >= checkpoint.updatedAt else {
                merged[lessonID] = checkpoint
                continue
            }
        }
        return merged
    }

    /// Returns valid device checkpoints that are missing or newer on the server.
    public static func checkpointsToUpload(
        local: [String: LocalResumeCheckpoint],
        server: [String: LocalResumeCheckpoint]
    ) -> [String: LocalResumeCheckpoint] {
        local.filter { lessonID, checkpoint in
            guard isValid(checkpoint) else { return false }
            guard let serverCheckpoint = server[lessonID], isValid(serverCheckpoint) else { return true }
            return checkpoint.updatedAt > serverCheckpoint.updatedAt
        }
    }

    private static func isValid(_ checkpoint: LocalResumeCheckpoint) -> Bool {
        checkpoint.positionSeconds.isFinite && checkpoint.positionSeconds >= 0 &&
            checkpoint.updatedAt.timeIntervalSince1970.isFinite
    }
}
