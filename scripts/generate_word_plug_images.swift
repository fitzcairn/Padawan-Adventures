// Deprecated entry point — prefer `generate_word_images.swift`.
// Kept so existing docs/commands still work.
import Foundation

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
let script = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("generate_word_images.swift")
task.arguments = [script.path] + Array(CommandLine.arguments.dropFirst())
task.standardOutput = FileHandle.standardOutput
task.standardError = FileHandle.standardError
try task.run()
task.waitUntilExit()
exit(task.terminationStatus)
