import Carbon
import Foundation

/// System-wide keyboard shortcuts that work from any app without Accessibility permission.
///
/// `NSEvent` global key monitors silently receive nothing unless the app is trusted for
/// Accessibility, which Moi never asks for — so shortcuts built on them only worked while
/// Moi was frontmost. Carbon hot keys are delivered regardless. One application-level
/// handler routes each press to its action by ID, so shortcuts can't steal each other's presses.
@MainActor
final class HotKeyCenter {
    enum ID: UInt32 {
        case notchGlance = 1
        case pocket = 2
        case command = 3
        case voice = 4
    }

    static let shared = HotKeyCenter()

    private var actions: [UInt32: () -> Void] = [:]
    private var releases: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    private init() {}

    /// Replaces any existing registration for `id`. Returns false if the combination is
    /// already taken by another app.
    @discardableResult
    func register(_ id: ID, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void, release: (() -> Void)? = nil) -> Bool {
        installHandlerIfNeeded()
        unregister(id)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: 0x4D4F4941, id: id.rawValue), GetApplicationEventTarget(), 0, &reference) // MOIA
        guard status == noErr, let reference else { return false }
        references[id.rawValue] = reference
        actions[id.rawValue] = action
        releases[id.rawValue] = release
        return true
    }

    func unregister(_ id: ID) {
        if let reference = references.removeValue(forKey: id.rawValue) { UnregisterEventHotKey(reference) }
        actions[id.rawValue] = nil
        releases[id.rawValue] = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let callback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            Task { @MainActor in if released { HotKeyCenter.shared.releases[id]?() } else { HotKeyCenter.shared.actions[id]?() } }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 2, &types, nil, &eventHandler)
    }
}
