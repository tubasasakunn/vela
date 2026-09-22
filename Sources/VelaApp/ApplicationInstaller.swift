import AppKit
import VelaCore

final class ApplicationInstaller {
    private let fileManager = FileManager.default

    func installIfNeeded() -> Bool {
        let source = Bundle.main.bundleURL
        let applicationDirectories = fileManager.urls(
            for: .applicationDirectory,
            in: [.localDomainMask, .userDomainMask, .systemDomainMask]
        )
        let isReadOnly = (try? source.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? false
        guard ApplicationInstallationPolicy.shouldOfferMove(
            bundleURL: source,
            isOnReadOnlyVolume: isReadOnly,
            applicationDirectories: applicationDirectories
        ) else { return false }

        let destinationDirectory = preferredDestinationDirectory()
        let destination = destinationDirectory.appending(path: source.lastPathComponent, directoryHint: .isDirectory)
        guard confirmMove(destinationExists: fileManager.fileExists(atPath: destination.path)) else { return false }

        do {
            try install(source: source, destination: destination)
            try relaunch(from: destination)
            NSApp.terminate(nil)
            return true
        } catch {
            presentInstallationError(error)
            return false
        }
    }

    private func preferredDestinationDirectory() -> URL {
        let systemApplications = fileManager.urls(for: .applicationDirectory, in: .localDomainMask)[0]
        if fileManager.isWritableFile(atPath: systemApplications.path) {
            return systemApplications
        }

        let userApplications = fileManager.urls(for: .applicationDirectory, in: .userDomainMask)[0]
        try? fileManager.createDirectory(at: userApplications, withIntermediateDirectories: true)
        return userApplications
    }

    private func confirmMove(destinationExists: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = destinationExists ? "ApplicationsのVelaを更新します" : "VelaをApplicationsに移動します"
        alert.informativeText = destinationExists
            ? "既存のVelaを置き換えて自動で開き、AIセットアップを表示します。設定ファイルはそのまま残ります。"
            : "移動後にVelaを自動で開き、AIセットアップを始めます。"
        alert.addButton(withTitle: destinationExists ? "更新してセットアップ" : "移動してセットアップ")
        alert.addButton(withTitle: "ここでは使わない")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func install(source: URL, destination: URL) throws {
        if isRunning(destination) {
            throw InstallationError.destinationIsRunning
        }

        let staging = destination.deletingLastPathComponent()
            .appending(path: ".Vela.installing-\(UUID().uuidString).app", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: staging) }

        try fileManager.copyItem(at: source, to: staging)
        guard fileManager.isExecutableFile(atPath: staging.appending(path: "Contents/MacOS/Vela").path) else {
            throw InstallationError.copiedAppIsInvalid
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.moveItem(at: staging, to: destination)
    }

    private func isRunning(_ destination: URL) -> Bool {
        let destinationPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.contains { application in
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && application.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == destinationPath
        }
    }

    private func relaunch(from destination: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", destination.path, "--args", VelaLaunchIntent.showSetupArgument]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw InstallationError.relaunchFailed(task.terminationStatus)
        }
    }

    private func presentInstallationError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "VelaをApplicationsに移動できませんでした"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private enum InstallationError: LocalizedError {
    case destinationIsRunning
    case copiedAppIsInvalid
    case relaunchFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .destinationIsRunning:
            return "ApplicationsにあるVelaを終了してから、もう一度お試しください。"
        case .copiedAppIsInvalid:
            return "コピーしたアプリを検証できませんでした。"
        case let .relaunchFailed(status):
            return "移動は完了しましたが、Velaを開けませんでした（終了コード: \(status)）。ApplicationsからVelaを開いてください。"
        }
    }
}
