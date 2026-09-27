import Foundation

struct TestResultSummary: Decodable {
    let passedTests: Int
    let failedTests: Int
    let skippedTests: Int
    let expectedFailures: Int?

    func formatted() throws -> String {
        guard [passedTests, failedTests, skippedTests, expectedFailures ?? 0].allSatisfy({ $0 >= 0 }) else {
            throw NSError(domain: "TestResultSummary", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid negative test count."])
        }
        var lines = ["Tests: \(passedTests) passed, \(failedTests) failed, \(skippedTests) skipped."]
        if let expectedFailures, expectedFailures > 0 {
            lines.append("Expected failures: \(expectedFailures) (accepted by the test runner).")
        }
        if skippedTests > 0 { lines.append("Warning: skipped tests were not verified.") }
        if passedTests == 0 && failedTests == 0 {
            lines.append("Warning: no passing or failing tests were reported.")
        }
        lines.append("Counts cover reported tests, not excluded/disabled tests or individual parameterized iterations.")
        return lines.joined(separator: "\n")
    }
}

func summary(_ data: Data) throws -> String {
    try JSONDecoder().decode(TestResultSummary.self, from: data).formatted()
}

do {
    if CommandLine.arguments.dropFirst() == ["--self-test"] {
        let cases: [(String, String)] = [
            (#"{"passedTests":257,"failedTests":0,"skippedTests":0}"#, "Tests: 257 passed, 0 failed, 0 skipped."),
            (#"{"passedTests":2,"failedTests":1,"skippedTests":3}"#, "Warning: skipped tests were not verified."),
            (#"{"passedTests":0,"failedTests":0,"skippedTests":1}"#, "Warning: no passing or failing tests were reported."),
            (#"{"passedTests":1,"failedTests":0,"skippedTests":0,"expectedFailures":2}"#, "Expected failures: 2")
        ]
        for (input, expected) in cases {
            guard try summary(Data(input.utf8)).contains(expected) else {
                throw NSError(domain: "TestResultSummaryTests", code: 1)
            }
        }
        for input in ["not json", #"{"passedTests":1}"#,
                      #"{"passedTests":-1,"failedTests":0,"skippedTests":0}"#] {
            var rejected = false
            do { _ = try summary(Data(input.utf8)) } catch { rejected = true }
            guard rejected else { throw NSError(domain: "TestResultSummaryTests", code: 2) }
        }
        print("Test result summary self-tests passed (7 cases).")
    } else {
        print(try summary(FileHandle.standardInput.readDataToEndOfFile()))
    }
} catch {
    FileHandle.standardError.write(Data("Test counts unavailable: \(error.localizedDescription)\n".utf8))
    exit(1)
}
