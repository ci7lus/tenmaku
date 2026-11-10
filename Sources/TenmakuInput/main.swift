import AppKit
import ApplicationServices
import TenmakuShared

if CommandLine.arguments.contains(requestSessionInputAccessArgument) {
    _ = NSApplication.shared
    _ = CGRequestListenEventAccess()
    _ = CGRequestPostEventAccess()
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    exit(0)
}

let layer = EventTapInputLayer()
let listener = LayerListener(service: .sessionInput, layer: layer)
listener.resume()
exitWhenIdle { [layer] in layer.isIdle() }
RunLoop.main.run()
