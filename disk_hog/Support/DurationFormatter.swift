import Foundation

enum DurationFormatter {
    static func scanDuration(_ duration: TimeInterval) -> String {
        let totalSeconds: Int = max(0, Int(duration.rounded()))
        let seconds: Int = totalSeconds % Metrics.secondsPerMinute
        let totalMinutes: Int = totalSeconds / Metrics.secondsPerMinute
        let minutes: Int = totalMinutes % Metrics.minutesPerHour
        let hours: Int = totalMinutes / Metrics.minutesPerHour

        if hours > 0 {
            return "\(hours):\(twoDigitString(minutes)):\(twoDigitString(seconds))"
        }

        return "\(minutes):\(twoDigitString(seconds))"
    }

    private static func twoDigitString(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}

private enum DurationFormatterMetrics {
    static let secondsPerMinute: Int = 60
    static let minutesPerHour: Int = 60
}

private typealias Metrics = DurationFormatterMetrics
