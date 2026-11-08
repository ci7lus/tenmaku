import AppKit
import TenmakuShared

final class CoverLayer: NSObject, ShieldLayer, @unchecked Sendable {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var engaged = false
    private var generation = 0

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
    }

    func preflight(reply: @escaping @Sendable (String?) -> Void) {
        reply(nil)
    }

    func engage(reply: @escaping @Sendable (String?) -> Void) {
        DispatchQueue.main.async { [self] in
            engaged = true
            reconcile()
            generation += 1
            #if TENMAKU_TEST_BUILD
            let current = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + testAutoReleaseSeconds) { [self] in
                if current == generation { stop() }
            }
            #endif
            reply(allCovered ? nil : "Could not cover all displays.")
        }
    }

    func release(reply: @escaping @Sendable (String?) -> Void) {
        DispatchQueue.main.async { [self] in
            stop()
            reply(nil)
        }
    }

    func takeUnlockRequest(reply: @escaping @Sendable (Bool) -> Void) {
        reply(false)
    }

    func takeEscapeRequest(reply: @escaping @Sendable (Bool) -> Void) {
        reply(false)
    }

    func sessionIsLocked(uid: UInt32, reply: @escaping @Sendable (Bool) -> Void) {
        reply(false)
    }

    func isEngaged(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in
            reply(engaged && allCovered)
        }
    }

    @MainActor
    private var allCovered: Bool {
        !windows.isEmpty && windows.count == NSScreen.screens.count && windows.values.allSatisfy { $0.isVisible }
    }

    @MainActor
    private func stop() {
        generation += 1
        engaged = false
        windows.values.forEach { $0.orderOut(nil) }
        windows = [:]
    }

    @MainActor
    private func reconcile() {
        guard engaged else { return }
        var current: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            current.insert(id)
            let window = windows[id] ?? makeWindow()
            windows[id] = window
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
        }
        for (id, window) in windows where !current.contains(id) {
            window.orderOut(nil)
            windows[id] = nil
        }
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        // A fully opaque window hides the windows beneath it in full-screen capture.
        window.isOpaque = false
        window.alphaValue = 0.999
        window.sharingType = .none
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }
}

let layer = CoverLayer()
let listener = LayerListener(service: .cover, layer: layer)
listener.resume()
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
