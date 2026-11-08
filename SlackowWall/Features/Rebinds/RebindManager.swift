//
//  RebindManager.swift
//  SlackowWall
//

import AppKit
import Combine
@preconcurrency import CoreGraphics

/// Replaces keys and mouse buttons with other inputs, but only while a tracked Minecraft
/// instance is the frontmost app. Unlike the global shortcut monitor, this uses an active
/// CGEvent tap, so the original input never reaches the game.
///
/// Call `start()` once at launch. The tap is installed only while rebinds are enabled and
/// at least one is configured, and it follows profile and settings changes on its own.
@MainActor final class RebindManager {
    static let shared = RebindManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var settingsObserver: AnyCancellable?

    /// Rebinds currently pressed, keyed by the physical input that pressed them.
    /// Releases and key repeats use this snapshot instead of the live config, so changing
    /// focus or settings mid-press can't leave Minecraft thinking an output is still held.
    private var held: [RemapInput: KeyRebind] = [:]

    private init() {}

    func start() {
        settingsObserver = Settings.shared.$preferences
            .map { prefs in
                prefs.keybinds.rebindsEnabled
                    && prefs.keybinds.rebinds.contains { $0.enabled && $0.from != nil }
            }
            // No removeDuplicates: installTap is idempotent, and re-running it retries a
            // tap that failed before Accessibility permission was granted.
            .sink { [weak self] shouldRun in
                if shouldRun { self?.installTap() } else { self?.removeTap() }
            }
    }

    private func installTap() {
        guard eventTap == nil else { return }
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                // The tap's run loop source lives on the main run loop.
                return MainActor.assumeIsolated {
                    Unmanaged<RebindManager>.fromOpaque(refcon).takeUnretainedValue()
                        .handle(type: type, event: event)
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let eventTap else {
            LogManager.shared.appendLog("Failed to create rebind event tap")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        LogManager.shared.appendLog("Rebinds enabled")
    }

    private func removeTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        CFMachPortInvalidate(eventTap)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        self.eventTap = nil
        runLoopSource = nil
        releaseHeld()
        LogManager.shared.appendLog("Rebinds disabled")
    }

    /// Sends a release for every output still held, so turning rebinds off mid-press
    /// (for example with the toggle hotkey) can't leave a key stuck down in Minecraft.
    private func releaseHeld() {
        for rebind in held.values {
            guard let placeholder = CGEvent(source: nil) else { continue }
            Self.makeEvent(for: rebind, isDown: false, isRepeat: false, like: placeholder)?
                .post(tap: .cgSessionEventTap)
        }
        held.removeAll()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let original = Unmanaged.passUnretained(event)

        // macOS disables taps that respond too slowly. Releases may have slipped past
        // unmapped meanwhile, so release every held output before turning it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            releaseHeld()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return original
        }

        guard let (input, isDown) = Self.decode(type: type, event: event) else { return original }
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        // Assign even when nothing matches, so an entry whose release was never seen
        // (released in another app under Secure Input) can't be reused.
        if isDown && !isRepeat { held[input] = rebindForPress(of: input) }
        let rebind = held[input]
        if !isDown { held[input] = nil }

        // Every event, rebound or not, has to agree with held modifier rebinds.
        // Keep a copy first: shortcuts may need the physical key.
        let physical = event.copy()
        Self.applyHeldModifiers(held, to: event)

        // Shortcuts see the physical key when it's blocked (they'd see nothing otherwise),
        // or when the user wants shortcuts to ignore rebinds and this event was remapped
        // or had its modifiers changed. The global key monitor then skips the event that
        // reaches Minecraft; see `isRebindOutput`. Run after the tap returns: shortcuts
        // can be slow (resizing) or toggle the tap.
        let usePhysical = Settings[\.keybinds].shortcutsUsePhysicalKeys
        let modifiersChanged = event.flags != physical?.flags
        if case .key = input,
            rebind.map({ $0.to == nil || usePhysical }) ?? (usePhysical && modifiersChanged),
            let physical = physical.flatMap(NSEvent.init(cgEvent:))
        {
            if rebind == nil {
                event.setIntegerValueField(.eventSourceUserData, value: Self.outputMarker)
            }
            DispatchQueue.main.async { ShortcutManager.shared.handleGlobalKey(physical) }
        }
        guard let rebind else { return original }
        guard rebind.to != nil else { return nil }
        return Self.makeEvent(
            for: rebind, isDown: isDown, isRepeat: isRepeat, like: event
        ).map(Unmanaged.passRetained)
    }

    /// The rebind a new press of `input` should use, or nil to pass it through.
    private func rebindForPress(of input: RemapInput) -> KeyRebind? {
        guard let instance = frontmostInstance else { return nil }
        let candidates = Settings[\.keybinds].rebinds.filter { $0.enabled && $0.from == input }
        // Only read the game state when a rebind depends on it.
        let context =
            candidates.contains { $0.when != .always } ? Self.context(of: instance) : nil
        return Self.pick(from: candidates, context: context)
    }

    /// Makes other keys and clicks agree with held modifier rebinds: a rebound modifier
    /// source stops counting as held (so a blocked ⌘ can't make ⌘Q), and a modifier output
    /// starts counting as held (so G → Shift capitalizes). Applied after `decode`, which
    /// needs the physical flags.
    static func applyHeldModifiers(_ held: [RemapInput: KeyRebind], to event: CGEvent) {
        guard !held.isEmpty else { return }
        var flags = event.flags
        // Strip every source before adding any output, so swapped modifiers
        // (Ctrl → Shift with Shift → Ctrl) don't cancel each other.
        for case .key(let code) in held.keys {
            removeModifier(code, from: &flags)
        }
        for case .key(let code)? in held.values.map(\.to) {
            addModifier(code, to: &flags)
        }
        event.flags = flags
    }

    /// Sets a modifier key in `flags`, per-side bit included so `removeModifier` can tell
    /// sides apart. Does nothing for ordinary keys.
    private static func addModifier(_ code: KeyCode, to flags: inout CGEventFlags) {
        guard let mask = modifierMask(code) else { return }
        flags.insert(mask.union(deviceMask(code) ?? []))
    }

    /// Clears a modifier key from `flags`. The shared bit stays while the other side of
    /// the same modifier is still held. Does nothing for ordinary keys.
    private static func removeModifier(_ code: KeyCode, from flags: inout CGEventFlags) {
        guard let mask = modifierMask(code) else { return }
        flags.remove(deviceMask(code) ?? [])
        let siblingHeld =
            siblingModifier[code].flatMap(deviceMask).map(flags.contains) ?? false
        if !siblingHeld { flags.remove(mask) }
    }

    private var frontmostInstance: TrackedInstance? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        return TrackingManager.shared.trackedInstances.first { $0.pid == pid }
    }

    /// Whether the player is in the world or in a screen, or nil without State Output.
    /// Reads the state file directly instead of `updateState`, which logs every call;
    /// this runs inside the tap on every press of a conditional input.
    private static func context(of instance: TrackedInstance) -> RebindCondition? {
        guard instance.hasMod(.stateOutput),
            let data = FileManager.default.contents(atPath: instance.info.statePath),
            var byte = data.first
        else { return nil }
        // "inworld,..." keeps the detailed state at offset 11, as in `updateState`.
        if byte == 0x69, data.count > 11 { byte = data[data.startIndex + 11] }
        return InstanceState(rawValue: byte) == .unpaused ? .playing : .inMenu
    }

    /// Picks which of an input's rebinds applies: one for the current context beats `always`.
    /// With an unknown context, only `always` rebinds apply.
    static func pick(from candidates: [KeyRebind], context: RebindCondition?) -> KeyRebind? {
        candidates.first { context != nil && $0.when == context }
            ?? candidates.first { $0.when == .always }
    }

    /// Reads which input an event belongs to and whether it was pressed or released.
    static func decode(type: CGEventType, event: CGEvent) -> (RemapInput, Bool)? {
        switch type {
            case .keyDown, .keyUp:
                let code = KeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                return (.key(code), type == .keyDown)
            case .flagsChanged:
                let code = KeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                // Caps Lock reports only lock toggles, never a release, so it can't be held.
                guard code != .capsLock, let mask = modifierMask(code) else { return nil }
                // The per-side bit tells left and right apart (Right Shift held while
                // Left Shift is released still has the shared Shift bit).
                return (.key(code), event.flags.contains(deviceMask(code) ?? mask))
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                return (.mouse(event.getIntegerValueField(.mouseEventButtonNumber)), true)
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                return (.mouse(event.getIntegerValueField(.mouseEventButtonNumber)), false)
            default:
                return nil
        }
    }

    /// Sent for "type nothing". AppKit treats an empty string as unset and falls back to the
    /// key's own character, so send a C1 control character instead: GLFW drops code points
    /// 127-159 before they reach Minecraft's chat.
    static let silentCharacter = "\u{9F}"

    /// Tags events created by rebinds (in `eventSourceUserData`) so the shortcut monitor
    /// can tell them apart from physical input.
    static let outputMarker: Int64 = 0x534C_5752  // "SLWR"

    /// Whether an event seen by the global key monitor was produced by a rebind.
    static func isRebindOutput(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == outputMarker
    }

    /// A key code GLFW doesn't map, so Minecraft sees no game key for type-only rebinds
    /// while the event's characters still reach chat.
    static let unmappedKeyCode: KeyCode = 0x34

    /// Builds the event that replaces one press or release of `rebind`. Returns nil to drop
    /// the original: for blocked rebinds and for key repeats on a mouse output.
    static func makeEvent(
        for rebind: KeyRebind, isDown: Bool, isRepeat: Bool, like event: CGEvent
    ) -> CGEvent? {
        guard let output = rebind.to else { return nil }
        let source = CGEventSource(event: event)

        // Keep modifiers the player is holding (Shift for sneak, etc.). `handle` already
        // removed held modifier sources via `applyHeldModifiers`; doing it again here
        // would also remove the same modifier when another held rebind outputs it.
        var flags = event.flags

        switch output {
            case .key(let code):
                guard
                    let out = CGEvent(
                        keyboardEventSource: source, virtualKey: code, keyDown: isDown)
                else { return nil }
                if modifierMask(code) != nil {
                    // GLFW toggles a modifier on every flagsChanged, so a repeat would
                    // read as a release.
                    guard !isRepeat else { return nil }
                    out.type = .flagsChanged
                    // On release the rebind has already left `held`, so the normalized
                    // flags already say whether this modifier is still held some other way
                    // (physically, or by another rebind). Forced releases start empty.
                    if isDown { addModifier(code, to: &flags) }
                }
                out.flags = flags
                if isRepeat { out.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }

                // GLFW reads game input from the key code and chat input from the event's
                // characters, so setting them separately splits the two.
                let isModifier = modifierMask(code) != nil
                if isDown && !isModifier,
                    let characters = rebind.typedCharacters(shift: flags.contains(.maskShift))
                {
                    setCharacters(characters.isEmpty ? silentCharacter : characters, on: out)
                }
                if rebind.typeOnly && !isModifier {
                    // Freeze the characters before hiding the game key. AppKit applies
                    // Shift itself, so read them through NSEvent.
                    setCharacters(NSEvent(cgEvent: out)?.characters ?? characters(of: out), on: out)
                    out.setIntegerValueField(.keyboardEventKeycode, value: Int64(unmappedKeyCode))
                }
                out.setIntegerValueField(.eventSourceUserData, value: outputMarker)
                return out

            case .mouse(let button):
                guard !isRepeat else { return nil }
                let (type, cgButton): (CGEventType, CGMouseButton) =
                    switch button {
                        case 0: (isDown ? .leftMouseDown : .leftMouseUp, .left)
                        case 1: (isDown ? .rightMouseDown : .rightMouseUp, .right)
                        default: (isDown ? .otherMouseDown : .otherMouseUp, .center)
                    }
                guard
                    let out = CGEvent(
                        mouseEventSource: source, mouseType: type,
                        mouseCursorPosition: event.location, mouseButton: cgButton)
                else { return nil }
                out.setIntegerValueField(.mouseEventButtonNumber, value: button)
                out.setIntegerValueField(.mouseEventClickState, value: 1)
                out.flags = flags
                out.setIntegerValueField(.eventSourceUserData, value: outputMarker)
                return out
        }
    }

    private static func setCharacters(_ text: String, on event: CGEvent) {
        let utf16 = Array(text.utf16)
        event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
    }

    static func characters(of event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 32)
        event.keyboardGetUnicodeString(
            maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: length)
    }

    /// The CGEvent flag a modifier key sets while held, or nil for ordinary keys.
    private static func modifierMask(_ code: KeyCode) -> CGEventFlags? {
        // Help shares Insert's key code and is an ordinary key for rebinding.
        guard code != .help else { return nil }
        // NSEvent and CGEvent share bit values for device-independent modifier flags.
        return KeyCode.modifierFlags(code: code).map { CGEventFlags(rawValue: UInt64($0.rawValue)) }
    }

    /// Per-side modifier bits (IOKit's NX_DEVICE*KEYMASK); Caps Lock and Fn have none.
    private static func deviceMask(_ code: KeyCode) -> CGEventFlags? {
        let bits: [KeyCode: UInt64] = [
            .control: 0x1, .shift: 0x2, .rightShift: 0x4, .command: 0x8,
            .rightCommand: 0x10, .option: 0x20, .rightOption: 0x40, .rightControl: 0x2000,
        ]
        return bits[code].map(CGEventFlags.init)
    }

    private static let siblingModifier: [KeyCode: KeyCode] = [
        .shift: .rightShift, .rightShift: .shift, .control: .rightControl,
        .rightControl: .control, .option: .rightOption, .rightOption: .option,
        .command: .rightCommand, .rightCommand: .command,
    ]
}
