import AhkMacCore
import CoreGraphics
import Foundation

/// Runs macros one at a time on a background queue, FIFO, so `sleep`
/// never blocks the event-tap callback.
final class MacroRunner {
    private let queue = DispatchQueue(label: "ahkmac.macro")
    private let source: CGEventSource?

    init(source: CGEventSource?) {
        self.source = source
    }

    func run(_ macro: MacroDef) {
        queue.async {
            for step in macro.steps { self.perform(step) }
        }
    }

    private func perform(_ step: MacroStep) {
        switch step {
        case .key(let chord):
            EventSynthesis.postChord(chord, source: source)
        case .text(let text):
            EventSynthesis.postText(text, source: source)
        case .sleep(let ms):
            Thread.sleep(forTimeInterval: Double(ms) / 1000)
        case .run(let command):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.terminationHandler = { p in
                if p.terminationStatus != 0 {
                    log("macro run '\(command)' exited \(p.terminationStatus)")
                }
            }
            do { try process.run() } catch {  // fire and forget: don't wait
                log("macro run '\(command)' failed to start: \(error.localizedDescription)")
            }
        }
    }
}
