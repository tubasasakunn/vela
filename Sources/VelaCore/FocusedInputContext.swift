import AppKit
import ApplicationServices
import AppKit
import Foundation

/// Describes only the purpose of the currently focused editable control. It
/// intentionally never reads AXValue, so typed text is not sent to a model.
public struct FocusedInputContext: Equatable, Sendable {
    public let applicationName: String
    public let bundleIdentifier: String?
    public let role: String
    public let label: String

    public init(applicationName: String, bundleIdentifier: String?, role: String, label: String) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.label = label
    }
}

public enum FocusedInputInspector {
    public static func inspect() -> Result<FocusedInputContext, FocusedInputError> {
        guard AXIsProcessTrusted() else { return .failure(.accessibilityNotAllowed) }
        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue else { return .failure(.noFocusedInput) }
        let element = unsafeBitCast(focusedValue, to: AXUIElement.self)
        let role = string(element, attribute: kAXRoleAttribute) ?? ""
        let subrole = string(element, attribute: kAXSubroleAttribute) ?? ""
        guard role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole else {
            return .failure(.noFocusedInput)
        }
        // Secure fields must never be candidates, even though their label is often safe.
        guard subrole != kAXSecureTextFieldSubrole else { return .failure(.secureInput) }

        let strings = contextStrings(for: element)
        guard !strings.isEmpty else { return .failure(.noDescription) }

        var applicationValue: CFTypeRef?
        let application = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &applicationValue) == .success
            ? applicationValue.map { unsafeBitCast($0, to: AXUIElement.self) }
            : nil
        let pid = application.flatMap { processIdentifier(of: $0) }
        let running = pid.flatMap(NSRunningApplication.init(processIdentifier:))
        return .success(.init(
            applicationName: running?.localizedName ?? "Current application",
            bundleIdentifier: running?.bundleIdentifier,
            role: role,
            label: strings.joined(separator: " · ")
        ))
    }

    private static func contextStrings(for element: AXUIElement) -> [String] {
        // AXTitle and AXDescription are usually the accessible form label;
        // placeholder/help fill gaps in browsers and Electron applications.
        let attributes = [
            kAXTitleAttribute as String,
            kAXDescriptionAttribute as String,
            kAXHelpAttribute as String,
            "AXPlaceholderValue",
            kAXRoleDescriptionAttribute as String,
        ]
        var result: [String] = []
        for attribute in attributes {
            if let value = string(element, attribute: attribute), !value.isEmpty { result.append(value) }
        }
        var parentValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentValue) == .success,
           let parentValue {
            let parent = unsafeBitCast(parentValue, to: AXUIElement.self)
            for attribute in [kAXTitleAttribute as String, kAXDescriptionAttribute as String, kAXHelpAttribute as String] {
                if let value = string(parent, attribute: attribute), !value.isEmpty { result.append(value) }
            }
        }
        return Array(NSOrderedSet(array: result)) as? [String] ?? result
    }

    private static func string(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        return value as? String
    }

    private static func processIdentifier(of application: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(application, &pid) == .success ? pid : nil
    }
}

public enum FocusedInputError: LocalizedError, Equatable {
    case accessibilityNotAllowed
    case noFocusedInput
    case noDescription
    case secureInput

    public var errorDescription: String? {
        switch self {
        case .accessibilityNotAllowed: return "Vela needs Accessibility permission to inspect the focused input."
        case .noFocusedInput: return "Focus a text input field, then try again."
        case .noDescription: return "This input field does not expose a label or description."
        case .secureInput: return "Vela does not offer contextual paste in secure text fields."
        }
    }
}
