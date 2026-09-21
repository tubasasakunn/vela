import Foundation

public struct PermissionSnapshot: Codable {
    public let states: [String: Bool]
    public let checkedAt: Date
    public init(states: [VelaPermission: Bool], checkedAt: Date = .now) {
        self.states = Dictionary(uniqueKeysWithValues: states.map { ($0.key.cliName, $0.value) })
        self.checkedAt = checkedAt
    }

    public func isGranted(_ permission: VelaPermission) -> Bool {
        states[permission.cliName] == true
    }

    public var grantedCount: Int {
        VelaPermission.allCases.count(where: isGranted)
    }

    public var nextMissingPermission: VelaPermission? {
        VelaPermission.allCases.first { !isGranted($0) }
    }
}

public enum PermissionStatusStore {
    private static var url: URL { VelaPaths.applicationSupport.appending(path: "permissions.json") }
    public static func write(_ states: [VelaPermission: Bool]) {
        try? FileManager.default.createDirectory(at: VelaPaths.applicationSupport, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(PermissionSnapshot(states: states)) else { return }
        try? data.write(to: url, options: .atomic)
    }
    public static func read() -> PermissionSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PermissionSnapshot.self, from: data)
    }
}
