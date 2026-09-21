import Foundation
import OSLog

/// Always available in Console, including Release builds. Paths remain private.
nonisolated enum TreemapPerformance {
    @TaskLocal static var renderID: String = "direct"
    private static let logger = Logger(subsystem: "software.utilitybelt.diskhog", category: "TreemapPerformance")

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    static func started(_ request: TreemapRenderRequest, reason: String) {
        #if DEBUG
        let build = "Debug"
        #else
        let build = "Release"
        #endif
        logger.notice("render=\(renderID, privacy: .public) started reason=\(reason, privacy: .public) build=\(build, privacy: .public) width=\(request.width, privacy: .public) height=\(request.height, privacy: .public) scale=\(request.scale, privacy: .public) root=\(request.rootItem.path, privacy: .private)")
    }

    static func phase(_ phase: String, since start: TimeInterval, count: Int = 0) {
        let elapsed = now - start
        logger.notice("render=\(renderID, privacy: .public) phase=\(phase, privacy: .public) seconds=\(elapsed, format: .fixed(precision: 4), privacy: .public) count=\(count, privacy: .public)")
    }

    static func event(_ event: String) {
        logger.notice("render=\(renderID, privacy: .public) event=\(event, privacy: .public)")
    }
}
