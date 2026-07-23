import AhkMacCore
import ApplicationServices
import CoreGraphics
import Foundation

let version = "0.2.0"
let usage = """
usage: ahkmac [--check] [--help] [--version] [config-path]

AutoHotkey-style key remapper and text expander for macOS.
Default config path: ~/.config/ahkmac.conf

  --check    parse the config and exit without starting the event tap

Send SIGHUP to reload the config while running.
"""

func loadConfig(atPath path: String) throws -> Config {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    return try ConfigParser.parse(text)
}

func fail(_ message: String) -> Never {
    log(message)
    if isatty(STDERR_FILENO) == 0 {
        // Launched from Finder: stderr goes nowhere, so surface the error visibly.
        _ = CFUserNotificationDisplayAlert(0, CFOptionFlags(kCFUserNotificationStopAlertLevel),
                                           nil, nil, nil,
                                           "ahkmac" as CFString, message as CFString,
                                           nil, nil, nil, nil)
    }
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") { print(usage); exit(0) }
if arguments.contains("--version") { print("ahkmac \(version)"); exit(0) }
var checkOnly = false
if let index = arguments.firstIndex(of: "--check") {
    checkOnly = true
    arguments.remove(at: index)
}
if let flag = arguments.first(where: { $0.hasPrefix("-") }) {
    fail("unknown option '\(flag)'\n\(usage)")
}
guard arguments.count <= 1 else {
    fail("too many arguments\n\(usage)")
}
let configPath = arguments.first
    ?? NSString(string: "~/.config/ahkmac.conf").expandingTildeInPath

let config: Config
do {
    config = try loadConfig(atPath: configPath)
} catch let error as ConfigError {
    fail("\(configPath): \(error)")
} catch {
    fail("cannot read \(configPath): \(error.localizedDescription)")
}
log("\(configPath): \(config.keymaps.count) keymaps, \(config.hotstrings.count) hotstrings")
if checkOnly { exit(0) }

let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
    // Poll instead of exiting so an app-bundle launch starts working right
    // after the user grants the permission, without a manual relaunch.
    log("waiting for accessibility permission (System Settings > Privacy & Security > Accessibility)…")
    while !AXIsProcessTrusted() { sleep(2) }
}

let remapper = Remapper(config: config, configPath: configPath)

let eventMask: CGEventMask =
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.keyUp.rawValue) |
    (1 << CGEventType.leftMouseDown.rawValue) |
    (1 << CGEventType.rightMouseDown.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: { _, type, event, refcon in
        Unmanaged<Remapper>.fromOpaque(refcon!).takeUnretainedValue()
            .handle(type: type, event: event)
    },
    userInfo: Unmanaged.passUnretained(remapper).toOpaque()
) else {
    fail("failed to create event tap (is accessibility permission granted?)")
}
remapper.eventTap = tap

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

signal(SIGHUP, SIG_IGN)
let reloadSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
reloadSource.setEventHandler { remapper.reload() }
reloadSource.resume()

// SIGINT/SIGTERM: the default disposition terminates the process and the
// system tears down the event tap, so no explicit handlers are needed.

log("running (send SIGHUP to reload, Ctrl-C to quit)")
CFRunLoopRun()
