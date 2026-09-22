import Foundation

public enum VelaLaunchIntent {
    public static let showSetupArgument = "--vela-show-setup"

    public static func shouldShowSetup(arguments: [String]) -> Bool {
        arguments.contains(showSetupArgument)
    }
}

public enum ApplicationInstallationPolicy {
    public static func shouldOfferMove(
        bundleURL: URL,
        isOnReadOnlyVolume: Bool,
        applicationDirectories: [URL]
    ) -> Bool {
        isOnReadOnlyVolume && !isInstalled(bundleURL: bundleURL, applicationDirectories: applicationDirectories)
    }

    public static func isInstalled(bundleURL: URL, applicationDirectories: [URL]) -> Bool {
        let bundlePath = normalizedPath(bundleURL)
        return applicationDirectories.contains { directory in
            let directoryPath = normalizedPath(directory)
            return bundlePath == directoryPath || bundlePath.hasPrefix(directoryPath + "/")
        }
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
