import Foundation
import os

/// Central diagnostics facade for the app.
///
/// Two things make this useful for chasing a crash:
///
/// 1. Every message is emitted to the unified log *as it happens*, so the Xcode
///    console already holds a complete ordered trail by the time the process
///    stops — including for Swift traps (`fatalError`, force-unwrap of `nil`,
///    array out of bounds), which no handler is able to intercept. The last
///    `→` line without a matching `←` is the operation that died.
/// 2. The same messages are kept in a bounded ring buffer, so the trail can be
///    re-dumped on demand. When Xcode breaks on a red line, run this in LLDB:
///
///        (lldb) e -l swift -- GameLogger.dumpBreadcrumbs()
///
/// Values are logged `.public` on purpose: this is a children's game with no
/// sensitive data, and redacted `<private>` output defeats the point. Player
/// names are the one exception and are never logged.
enum GameLogger {
    static let subsystem = "PadawanAdventures"

    /// One category per subsystem area, so Console.app can filter to a slice.
    enum Category: String, CaseIterable, Sendable {
        case lifecycle
        case flow
        case session
        case config
        case world
        case combat
        case audio
        case sprites
    }

    // MARK: - Emitting

    static func debug(
        _ category: Category,
        _ message: @autoclosure () -> String
    ) {
        let text = message()
        logger(category).debug("\(text, privacy: .public)")
        record(category, "·", text, location: nil)
    }

    static func info(
        _ category: Category,
        _ message: @autoclosure () -> String
    ) {
        let text = message()
        logger(category).info("\(text, privacy: .public)")
        record(category, "·", text, location: nil)
    }

    /// A breadcrumb on the crash trail. Use for state transitions worth seeing
    /// in the last few lines before a crash.
    static func mark(
        _ category: Category,
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line
    ) {
        let text = message()
        let where_ = location(file, line)
        logger(category).notice("\(text, privacy: .public) [\(where_, privacy: .public)]")
        record(category, "•", text, location: where_)
    }

    static func error(
        _ category: Category,
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line
    ) {
        let text = message()
        let where_ = location(file, line)
        logger(category).error("\(text, privacy: .public) [\(where_, privacy: .public)]")
        record(category, "!", text, location: where_)
    }

    /// Unrecoverable-but-survivable condition. Also logged in release builds,
    /// unlike `assertionFailure`.
    static func fault(
        _ category: Category,
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line
    ) {
        let text = message()
        let where_ = location(file, line)
        logger(category).fault("\(text, privacy: .public) [\(where_, privacy: .public)]")
        record(category, "✖", text, location: where_)
    }

    // MARK: - Scoped steps

    /// Brackets `body` with enter/exit breadcrumbs and reports its duration.
    ///
    /// If the process dies inside `body`, the console shows the `→ enter` with
    /// no matching `← exit`, which names the failing operation exactly.
    @discardableResult
    static func step<T>(
        _ category: Category,
        _ name: String,
        file: String = #fileID,
        line: Int = #line,
        _ body: () throws -> T
    ) rethrows -> T {
        let where_ = location(file, line)
        enter(category, name, where_)
        let started = DispatchTime.now()
        do {
            let value = try body()
            exit(category, name, where_, started)
            return value
        } catch {
            failed(category, name, where_, started, error)
            throw error
        }
    }

    @discardableResult
    static func step<T>(
        _ category: Category,
        _ name: String,
        file: String = #fileID,
        line: Int = #line,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let where_ = location(file, line)
        enter(category, name, where_)
        let started = DispatchTime.now()
        do {
            let value = try await body()
            exit(category, name, where_, started)
            return value
        } catch {
            failed(category, name, where_, started, error)
            throw error
        }
    }

    private static func enter(_ category: Category, _ name: String, _ where_: String) {
        logger(category).notice("→ \(name, privacy: .public) [\(where_, privacy: .public)]")
        record(category, "→", name, location: where_)
    }

    private static func exit(
        _ category: Category,
        _ name: String,
        _ where_: String,
        _ started: DispatchTime
    ) {
        let ms = milliseconds(since: started)
        logger(category).notice("← \(name, privacy: .public) (\(ms, privacy: .public)ms)")
        record(category, "←", "\(name) (\(ms)ms)", location: where_)
    }

    private static func failed(
        _ category: Category,
        _ name: String,
        _ where_: String,
        _ started: DispatchTime,
        _ error: Error
    ) {
        let ms = milliseconds(since: started)
        logger(category).error(
            "✖ \(name, privacy: .public) threw \(String(describing: error), privacy: .public) (\(ms, privacy: .public)ms)"
        )
        record(category, "✖", "\(name) threw \(error) (\(ms)ms)", location: where_)
    }

    // MARK: - Breadcrumbs

    /// Bounded so a long session cannot grow memory without limit.
    private static let breadcrumbLimit = 250

    private struct Breadcrumb {
        let timestamp: Date
        let category: Category
        let glyph: String
        let message: String
        let location: String?
        let onMainThread: Bool
    }

    private static let breadcrumbs = OSAllocatedUnfairLock<[Breadcrumb]>(initialState: [])

    private static func record(
        _ category: Category,
        _ glyph: String,
        _ message: String,
        location: String?
    ) {
        let crumb = Breadcrumb(
            timestamp: Date(),
            category: category,
            glyph: glyph,
            message: message,
            location: location,
            onMainThread: Thread.isMainThread
        )
        breadcrumbs.withLock { store in
            store.append(crumb)
            if store.count > breadcrumbLimit {
                store.removeFirst(store.count - breadcrumbLimit)
            }
        }
    }

    /// The recorded trail, oldest first, one line per breadcrumb.
    static func breadcrumbTrail() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withTime, .withFractionalSeconds, .withColonSeparatorInTime]
        return breadcrumbs.withLock { $0 }
            .map { crumb in
                let time = formatter.string(from: crumb.timestamp)
                let thread = crumb.onMainThread ? "main" : "bg"
                let site = crumb.location.map { " [\($0)]" } ?? ""
                return "\(time) \(crumb.glyph) [\(crumb.category.rawValue)/\(thread)] \(crumb.message)\(site)"
            }
            .joined(separator: "\n")
    }

    /// Prints the trail to stderr. Safe to call from LLDB at a breakpoint.
    @discardableResult
    static func dumpBreadcrumbs() -> String {
        let trail = breadcrumbTrail()
        FileHandle.standardError.write(Data(
            "\n===== GameLogger breadcrumbs =====\n\(trail)\n==================================\n".utf8
        ))
        return trail
    }

    static func clearBreadcrumbs() {
        breadcrumbs.withLock { $0.removeAll(keepingCapacity: true) }
    }

    // MARK: - Crash handlers

    private static let handlersInstalled = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// Installs best-effort handlers that surface the breadcrumb trail when the
    /// process is about to die. Call once, as early as possible.
    ///
    /// Swift runtime traps raise `SIGTRAP`/`SIGILL` and, under a debugger, LLDB
    /// takes them first — so these handlers mostly matter for untethered runs.
    /// The console trail (above) is what pinpoints a trap while debugging.
    static func installCrashHandlers() {
        let alreadyInstalled = handlersInstalled.withLock { installed -> Bool in
            defer { installed = true }
            return installed
        }
        guard !alreadyInstalled else { return }

        NSSetUncaughtExceptionHandler { exception in
            GameLogger.fault(
                .lifecycle,
                "uncaught \(exception.name.rawValue): \(exception.reason ?? "no reason")"
            )
            GameLogger.fault(
                .lifecycle,
                "stack: \(exception.callStackSymbols.joined(separator: " | "))"
            )
            GameLogger.dumpBreadcrumbs()
        }

        for signalNumber in [SIGABRT, SIGILL, SIGTRAP, SIGSEGV, SIGBUS, SIGFPE] {
            signal(signalNumber, { received in
                // Signal context: only async-signal-safe calls are legal here,
                // so this writes a fixed marker and hands back to the default
                // handler. The trail itself is already in the console.
                let marker = "\n*** GameLogger: fatal signal — see breadcrumbs above ***\n"
                _ = marker.withCString { pointer in
                    write(STDERR_FILENO, pointer, strlen(pointer))
                }
                signal(received, SIG_DFL)
                raise(received)
            })
        }

        mark(.lifecycle, "crash handlers installed")
    }

    // MARK: - Internals

    private static let loggers: [Category: Logger] = Dictionary(
        uniqueKeysWithValues: Category.allCases.map {
            ($0, Logger(subsystem: subsystem, category: $0.rawValue))
        }
    )

    private static func logger(_ category: Category) -> Logger {
        loggers[category] ?? Logger(subsystem: subsystem, category: category.rawValue)
    }

    private static func location(_ file: String, _ line: Int) -> String {
        let name = file.split(separator: "/").last.map(String.init) ?? file
        return "\(name):\(line)"
    }

    private static func milliseconds(since start: DispatchTime) -> String {
        let nanos = DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds
        return String(format: "%.1f", Double(nanos) / 1_000_000)
    }
}
