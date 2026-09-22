import Carbon.HIToolbox
import Foundation

struct HotkeyShortcut: Equatable {
    enum ParseError: LocalizedError, Equatable {
        case emptyPart
        case missingModifier
        case missingKey
        case repeatedModifier(String)
        case multipleKeys
        case unsupportedKey(String)

        var errorDescription: String? {
            switch self {
            case .emptyPart: return "empty shortcut parts are not allowed"
            case .missingModifier: return "at least one modifier is required"
            case .missingKey: return "a primary key is required"
            case let .repeatedModifier(modifier): return "modifier '\(modifier)' is repeated"
            case .multipleKeys: return "exactly one primary key is required"
            case let .unsupportedKey(key): return "key '\(key)' is not supported"
            }
        }
    }

    let keyCode: UInt32
    let modifiers: UInt32
    let canonicalSignature: String

    init(keys: [String]) throws {
        var modifierNames = Set<String>()
        var modifiers: UInt32 = 0
        var primaryKey: String?

        for part in keys {
            let token = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !token.isEmpty else { throw ParseError.emptyPart }
            if let modifier = Self.modifier(for: token) {
                guard modifierNames.insert(modifier.name).inserted else {
                    throw ParseError.repeatedModifier(modifier.name)
                }
                modifiers |= modifier.flag
            } else {
                guard primaryKey == nil else { throw ParseError.multipleKeys }
                primaryKey = token
            }
        }

        guard !modifierNames.isEmpty else { throw ParseError.missingModifier }
        guard let primaryKey else { throw ParseError.missingKey }
        guard let keyCode = Self.keyCodes[primaryKey] else { throw ParseError.unsupportedKey(primaryKey) }

        self.keyCode = keyCode
        self.modifiers = modifiers
        canonicalSignature = (Self.modifierOrder.filter(modifierNames.contains) + [primaryKey]).joined(separator: "+")
    }

    private static let modifierOrder = ["command", "option", "control", "shift"]

    private static func modifier(for token: String) -> (name: String, flag: UInt32)? {
        switch token {
        case "command", "cmd": return ("command", UInt32(cmdKey))
        case "option", "alt": return ("option", UInt32(optionKey))
        case "control", "ctrl": return ("control", UInt32(controlKey))
        case "shift": return ("shift", UInt32(shiftKey))
        default: return nil
        }
    }

    private static let keyCodes: [String: UInt32] = [
        "space": 49, "tab": 48, "return": 36, "escape": 53,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21,
        "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
        "[": 33, "]": 30,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}

public final class HotkeyManager {
    public var onAction: ((VelaAction) -> Void)?
    private var hotkeys: [EventHotKeyRef] = []
    private var actions: [UInt32: VelaAction] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private var registeredConfigurations: [HotkeyConfiguration] = []
    public init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotkeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
            if let action = manager.actions[hotkeyID.id] { manager.onAction?(action) }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
    deinit { unregisterAll(); if let eventHandler { RemoveEventHandler(eventHandler) } }
    public func register(_ configurations: [HotkeyConfiguration]) throws {
        let previousConfigurations = registeredConfigurations
        unregisterAll()
        do {
            try registerAll(configurations)
            registeredConfigurations = configurations
        } catch {
            unregisterAll()
            do {
                try registerAll(previousConfigurations)
                registeredConfigurations = previousConfigurations
            } catch {
                unregisterAll()
                registeredConfigurations = []
            }
            throw error
        }
    }

    private func registerAll(_ configurations: [HotkeyConfiguration]) throws {
        for config in configurations {
            let displayName = config.keys.joined(separator: "+")
            let shortcut: HotkeyShortcut
            do {
                shortcut = try HotkeyShortcut(keys: config.keys)
            } catch {
                throw ConfigurationError.invalidHotkey(displayName, error.localizedDescription)
            }
            let id = nextID; nextID += 1
            var reference: EventHotKeyRef?
            let hotkeyID = EventHotKeyID(signature: OSType(0x56454C41), id: id) // VELA
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotkeyID, GetEventDispatcherTarget(), 0, &reference)
            guard status == noErr, let reference else {
                throw ConfigurationError.hotkeyRegistrationFailed(shortcut.canonicalSignature, status)
            }
            hotkeys.append(reference)
            actions[id] = config.action
        }
    }

    private func unregisterAll() {
        hotkeys.forEach { UnregisterEventHotKey($0) }
        hotkeys.removeAll()
        actions.removeAll()
        nextID = 1
    }
}
