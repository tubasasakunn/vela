import Darwin
import Foundation

enum TerminalUI {
    static var isInteractive: Bool {
        isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
    }

    static func heading(_ text: String) {
        print("\n\(style("✦  \(text)", code: "1;36"))")
    }

    static func success(_ text: String) {
        print("\(style("✓", code: "32"))  \(text)")
    }

    static func detail(_ text: String) {
        print("\(style("│", code: "2"))  \(text)")
    }

    static func action(_ text: String) {
        print("\(style("→", code: "36"))  \(text)")
    }

    static func warning(_ text: String) {
        print("\(style("!", code: "33"))  \(text)")
    }

    static func spinner(frame: Int, text: String) {
        guard isInteractive else { return }
        let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        print("\r\u{001B}[2K\(style(frames[frame % frames.count], code: "36"))  \(text)", terminator: "")
        fflush(stdout)
    }

    static func clearLine() {
        guard isInteractive else { return }
        print("\r\u{001B}[2K", terminator: "")
        fflush(stdout)
    }

    static func style(_ text: String, code: String) -> String {
        guard isInteractive, ProcessInfo.processInfo.environment["NO_COLOR"] == nil else { return text }
        return "\u{001B}[\(code)m\(text)\u{001B}[0m"
    }
}
