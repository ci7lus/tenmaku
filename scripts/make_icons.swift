#!/usr/bin/env swift
// Generate menu bar icons in Bundle/Assets.xcassets from the SVGs in assets/.
// scripts/build.sh compiles assets/Tenmaku.icon directly for AppIcon.
// Usage: swift scripts/make_icons.swift
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent()
let sources = root.appendingPathComponent("assets")
let catalog = root.appendingPathComponent("Bundle/Assets.xcassets")

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

// Crop to the width of the artwork to avoid empty space in the menu bar.
func makeStatusImage(source: String, name: String) throws {
    var svg = try String(contentsOf: sources.appendingPathComponent(source), encoding: .utf8)
    guard let range = svg.range(of: #"viewBox="0 0 1024 1024" width="1024" height="1024""#) else {
        fatalError("\(source) has an unexpected viewBox")
    }
    svg.replaceSubrange(range, with: #"viewBox="112 112 800 800" width="18" height="18""#)
    let set = catalog.appendingPathComponent("\(name).imageset")
    try? FileManager.default.removeItem(at: set)
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    let file = "\(name).svg"
    try svg.write(to: set.appendingPathComponent(file), atomically: true, encoding: .utf8)
    try writeJSON([
        "images": [["filename": file, "idiom": "universal"]],
        "info": ["author": "xcode", "version": 1],
        "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"],
    ], to: set.appendingPathComponent("Contents.json"))
}

try makeStatusImage(source: "icon.svg", name: "StatusClosed")
try makeStatusImage(source: "icon_open.svg", name: "StatusOpen")
