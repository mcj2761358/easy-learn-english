import AVFoundation

// Silence Sendable warnings for AVAssetExportSession used in local async operations.
extension AVAssetExportSession: @unchecked Sendable {}
