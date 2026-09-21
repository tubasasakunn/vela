import Foundation
import VelaCore

extension VelaCLI {
    private struct LegacySnippet: Decodable {
        let id: String
        let title: String
        let content: String
        let folder: String?
    }
    static func snippets(_ arguments: ArraySlice<String>) throws {
        guard arguments.first == "import-clipy" else {
            TerminalUI.action("vela snippets import-clipy")
            return
        }
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/com.clipy-app.Clipy/sqlite.db")
        guard FileManager.default.fileExists(atPath: database.path) else {
            throw ConfigurationError.invalid("Clipy database was not found")
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-json", database.path,
            "SELECT s.id, s.title, s.content, f.title AS folder FROM snippets s LEFT JOIN snippetFolders f ON f.id = s.folderID ORDER BY f.\"index\", s.\"index\";",
        ]
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = try output.fileHandleForReading.readToEnd() else {
            throw ConfigurationError.invalid("Could not read Clipy snippets")
        }
        let records = try JSONDecoder().decode([LegacySnippet].self, from: data)
        let begin = "// Vela Clipy import begin"
        let end = "// Vela Clipy import end"
        let declarations = try records.map { snippet in
            let group = try snippet.folder.map(javascriptString) ?? "null"
            return "Vela.snippet({ id: \(try javascriptString("clipy-\(snippet.id)")), title: \(try javascriptString(snippet.title)), group: \(group), value: \(try javascriptString(snippet.content)), keywords: [] });"
        }.joined(separator: "\n")
        let block = "\(begin)\n\(declarations)\n\(end)"
        let configURL = VelaPaths.configuration.resolvingSymlinksInPath()
        var source = try String(contentsOf: configURL, encoding: .utf8)
        if let start = source.range(of: begin),
           let finish = source.range(of: end, range: start.lowerBound..<source.endIndex) {
            source.replaceSubrange(start.lowerBound..<finish.upperBound, with: block)
        } else {
            source += "\n\n\(block)\n"
        }
        try source.write(to: configURL, atomically: true, encoding: .utf8)
        DistributedNotificationCenter.default().post(name: VelaNotifications.reload, object: nil)
        TerminalUI.success("Clipy のスニペットを \(records.count) 件読み込みました")
        TerminalUI.detail(configURL.path)
    }
    private static func javascriptString(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value])
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }
}
