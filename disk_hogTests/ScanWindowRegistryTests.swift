import AppKit
import Testing
@testable import disk_hog

@MainActor
struct ScanWindowRegistryTests {
    @Test func sessionSnapshotExcludesReleasedWindowsAndSessions() {
        let registry = ScanWindowRegistry()
        let source = ScanSource(path: "/registry-fixture", displayName: "Fixture")
        var session: ScanSession? = ScanSession(source: source)
        weak var weakWindow: NSWindow?
        weak let weakSession = session
        autoreleasepool {
            let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            weakWindow = window
            registry.register(window, session: session!, for: source)
            #expect(registry.openSessions.count == 1)
            window.close()
        }
        #expect(weakWindow == nil)
        #expect(registry.openSessions.isEmpty)
        session = nil
        #expect(weakSession == nil)

        let retainedWindow = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        var releasedSession: ScanSession? = ScanSession(source: source)
        registry.register(retainedWindow, session: releasedSession!, for: source)
        releasedSession = nil
        #expect(registry.openSessions.isEmpty)
    }

    @Test func unregisteringOldWindowKeepsReplacementSession() {
        let registry = ScanWindowRegistry()
        let source = ScanSource(path: "/registry-fixture", displayName: "Fixture")
        let oldWindow = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        let newWindow = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        let oldSession = ScanSession(source: source)
        let newSession = ScanSession(source: source)
        registry.register(oldWindow, session: oldSession, for: source)
        registry.register(newWindow, session: newSession, for: source)
        registry.unregister(oldWindow, for: source)
        #expect(registry.openSessions.count == 1)
        #expect(registry.openSessions.first === newSession)
        registry.unregister(newWindow, for: source)
        #expect(registry.openSessions.isEmpty)
    }
}
