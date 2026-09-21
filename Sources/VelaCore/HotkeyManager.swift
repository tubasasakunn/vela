import Carbon.HIToolbox
import Foundation

public final class HotkeyManager {
    public var onAction: ((VelaAction) -> Void)?
    private var hotkeys: [EventHotKeyRef] = []
    private var actions: [UInt32: VelaAction] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
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
    public func register(_ configurations: [HotkeyConfiguration]) {
        unregisterAll(); actions.removeAll(); nextID = 1
        for config in configurations {
            guard let parsed = parse(config.keys) else { continue }
            let id = nextID; nextID += 1
            var reference: EventHotKeyRef?
            let hotkeyID = EventHotKeyID(signature: OSType(0x56454C41), id: id) // VELA
            let status = RegisterEventHotKey(parsed.keyCode, parsed.modifiers, hotkeyID, GetEventDispatcherTarget(), 0, &reference)
            if status == noErr, let reference { hotkeys.append(reference); actions[id] = config.action }
        }
    }
    private func unregisterAll() { hotkeys.forEach { UnregisterEventHotKey($0) }; hotkeys.removeAll() }
    private func parse(_ keys: [String]) -> (keyCode: UInt32, modifiers: UInt32)? {
        var modifiers: UInt32 = 0; var key: String?
        for raw in keys.map({ $0.lowercased() }) {
            switch raw {
            case "command", "cmd": modifiers |= UInt32(cmdKey)
            case "option", "alt": modifiers |= UInt32(optionKey)
            case "control", "ctrl": modifiers |= UInt32(controlKey)
            case "shift": modifiers |= UInt32(shiftKey)
            default: key = raw
            }
        }
        guard let key, let code = keyCodes[key] else { return nil }
        return (code, modifiers)
    }
    private let keyCodes: [String: UInt32] = [
        "space": 49, "tab": 48, "return": 36, "escape": 53,
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}
