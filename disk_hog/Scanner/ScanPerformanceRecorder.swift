import Foundation

nonisolated final class ScanPerformanceRecorder: @unchecked Sendable {
    static let shared: ScanPerformanceRecorder = ScanPerformanceRecorder()

    private let lock: NSLock
    private var appName: String
    private var rootPath: String
    private var createdAt: String
    private var metrics: [String: ScanPerformanceMetric]

    private init() {
        self.lock = NSLock()
        self.appName = ""
        self.rootPath = ""
        self.createdAt = ""
        self.metrics = [:]
    }

    var defaultOutputURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("diskhog-scan-profile.json")
    }

    func reset(appName: String, rootPath: String) {
        lock.lock()
        self.appName = appName
        self.rootPath = rootPath
        self.createdAt = ISO8601DateFormatter().string(from: Date())
        self.metrics = [:]
        lock.unlock()
    }

    func addTime(_ metricName: String, seconds: TimeInterval) {
        lock.lock()
        var metric: ScanPerformanceMetric = metrics[metricName] ?? ScanPerformanceMetric()
        metric.seconds += seconds
        metric.count += Metrics.singleCount
        metrics[metricName] = metric
        lock.unlock()
    }

    func addCount(_ metricName: String, count: UInt64 = Metrics.singleCount) {
        lock.lock()
        var metric: ScanPerformanceMetric = metrics[metricName] ?? ScanPerformanceMetric()
        metric.count += count
        metrics[metricName] = metric
        lock.unlock()
    }

    func setValue(_ metricName: String, value: UInt64) {
        lock.lock()
        var metric: ScanPerformanceMetric = metrics[metricName] ?? ScanPerformanceMetric()
        metric.value = value
        metrics[metricName] = metric
        lock.unlock()
    }

    func write(to outputURL: URL? = nil) throws -> URL {
        let destinationURL: URL = outputURL ?? defaultOutputURL

        lock.lock()
        let snapshot: ScanPerformanceReport = ScanPerformanceReport(
            schema: Metrics.schemaName,
            app: appName,
            rootPath: rootPath,
            createdAt: createdAt,
            metrics: metrics
        )
        lock.unlock()

        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data = try encoder.encode(snapshot)
        try data.write(to: destinationURL, options: [.atomic])
        return destinationURL
    }

    func measure<T>(
        _ metricName: String,
        operation: () throws -> T
    ) rethrows -> T {
        let startTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        defer {
            addTime(metricName, seconds: CFAbsoluteTimeGetCurrent() - startTime)
        }

        return try operation()
    }
}

nonisolated private struct ScanPerformanceReport: Encodable {
    let schema: String
    let app: String
    let rootPath: String
    let createdAt: String
    let metrics: [String: ScanPerformanceMetric]
}

nonisolated private struct ScanPerformanceMetric: Encodable {
    var seconds: TimeInterval
    var count: UInt64
    var value: UInt64?

    init(
        seconds: TimeInterval = 0,
        count: UInt64 = 0,
        value: UInt64? = nil
    ) {
        self.seconds = seconds
        self.count = count
        self.value = value
    }
}

nonisolated private enum ScanPerformanceRecorderMetrics {
    static let schemaName: String = "diskhog-scan-profile-v1"
    static let singleCount: UInt64 = 1
}

private typealias Metrics = ScanPerformanceRecorderMetrics
