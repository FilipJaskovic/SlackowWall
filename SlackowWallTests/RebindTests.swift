//
//  RebindTests.swift
//  SlackowWallTests
//

import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import SlackowWall

@MainActor
struct RebindTests {
    private func keyEvent(_ code: KeyCode, down: Bool) -> CGEvent {
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
    }

    private func rebind(_ from: RemapInput, _ to: RemapInput?) -> KeyRebind {
        var rebind = KeyRebind()
        rebind.from = from
        rebind.to = to
        return rebind
    }

    private func press(
        _ rebind: KeyRebind, shift: Bool = false, down: Bool = true
    ) -> CGEvent {
        guard case .key(let code) = rebind.from else { fatalError("key rebinds only") }
        let event = keyEvent(code, down: down)
        if shift { event.flags.insert(.maskShift) }
        return RebindManager.makeEvent(
            for: rebind, isDown: down, isRepeat: false, like: event)!
    }

    @Test func typedTextFollowsShift() {
        var split = rebind(.key(.g), .key(.p))
        split.typed = .custom("g")

        let plain = press(split)
        #expect(plain.getIntegerValueField(.keyboardEventKeycode) == Int64(KeyCode.p))
        #expect(RebindManager.characters(of: plain) == "g")
        // No Shift rule: the custom text is uppercased.
        #expect(RebindManager.characters(of: press(split, shift: true)) == "G")

        split.shiftTyped = .custom("!")
        #expect(RebindManager.characters(of: press(split, shift: true)) == "!")
    }

    @Test func modifierOutputDoesNotRepeat() {
        let toShift = rebind(.key(.g), .key(.shift))
        let repeated = RebindManager.makeEvent(
            for: toShift, isDown: true, isRepeat: true, like: keyEvent(.g, down: true))
        #expect(repeated == nil)
    }

    @Test func modifierReleaseUsesItsOwnSide() {
        // Left Shift released while Right Shift is still held.
        let event = CGEvent(keyboardEventSource: nil, virtualKey: .shift, keyDown: false)!
        event.type = .flagsChanged
        event.flags = [.maskShift, CGEventFlags(rawValue: 0x4)]
        #expect(RebindManager.decode(type: .flagsChanged, event: event)?.1 == false)
    }

    @Test func heldModifierRebindsUpdateOtherKeys() {
        let q = keyEvent(.q, down: true)
        q.flags = [.maskCommand, CGEventFlags(rawValue: 0x8)]
        RebindManager.applyHeldModifiers([.key(.command): rebind(.key(.command), nil)], to: q)
        #expect(!q.flags.contains(.maskCommand))

        let a = keyEvent(.a, down: true)
        RebindManager.applyHeldModifiers([.key(.g): rebind(.key(.g), .key(.shift))], to: a)
        #expect(a.flags.contains(.maskShift))

        // Swapped modifiers both stay applied.
        let b = keyEvent(.b, down: true)
        b.flags = [.maskShift, .maskControl, CGEventFlags(rawValue: 0x2 | 0x1)]
        RebindManager.applyHeldModifiers(
            [
                .key(.control): rebind(.key(.control), .key(.shift)),
                .key(.shift): rebind(.key(.shift), .key(.control)),
            ], to: b)
        #expect(b.flags.contains(.maskShift) && b.flags.contains(.maskControl))
    }

    private func flagsChangedEvent(_ code: KeyCode, flags: CGEventFlags) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        event.type = .flagsChanged
        event.flags = flags
        return event
    }

    /// `handle`'s path for a rebound press or release: normalize held modifiers, then build.
    private func translate(
        _ rebind: KeyRebind, held: [RemapInput: KeyRebind], event: CGEvent, down: Bool
    ) -> CGEvent {
        RebindManager.applyHeldModifiers(held, to: event)
        return RebindManager.makeEvent(for: rebind, isDown: down, isRepeat: false, like: event)!
    }

    @Test func swappedModifiersKeepBothOnSecondPress() {
        // Ctrl → Shift is held, then Left Shift → Ctrl is pressed.
        let ctrlToShift = rebind(.key(.control), .key(.shift))
        let shiftToCtrl = rebind(.key(.shift), .key(.control))
        let press = flagsChangedEvent(
            .shift, flags: [.maskShift, .maskControl, CGEventFlags(rawValue: 0x1 | 0x2)])
        let out = translate(
            shiftToCtrl, held: [.key(.control): ctrlToShift, .key(.shift): shiftToCtrl],
            event: press, down: true)
        #expect(out.flags.contains(.maskShift) && out.flags.contains(.maskControl))
    }

    @Test func modifierOutputReleaseKeepsPhysicalSibling() {
        // G → Left Shift released while the physical Right Shift is held.
        let release = keyEvent(.g, down: false)
        release.flags = [.maskShift, CGEventFlags(rawValue: 0x4)]
        let out = translate(rebind(.key(.g), .key(.shift)), held: [:], event: release, down: false)
        #expect(out.type == .flagsChanged)
        #expect(out.flags.contains(.maskShift))

        // Same with the physical Left Shift itself held.
        let sameSide = keyEvent(.g, down: false)
        sameSide.flags = [.maskShift, CGEventFlags(rawValue: 0x2)]
        let kept = translate(
            rebind(.key(.g), .key(.shift)), held: [:], event: sameSide, down: false)
        #expect(kept.flags.contains(.maskShift))
    }

    @Test func outputsAreTaggedForTheShortcutMonitor() {
        let out = press(rebind(.key(.g), .key(.p)))
        #expect(out.getIntegerValueField(.eventSourceUserData) == RebindManager.outputMarker)
        #expect(RebindManager.isRebindOutput(NSEvent(cgEvent: out)!))
        #expect(!RebindManager.isRebindOutput(NSEvent(cgEvent: keyEvent(.g, down: true))!))
    }

    @Test func typingNothingClearsCharacters() {
        var silent = rebind(.key(.g), .key(.p))
        silent.typed = .nothing
        let out = press(silent)
        #expect(out.getIntegerValueField(.keyboardEventKeycode) == Int64(KeyCode.p))
        // Check what AppKit (and so GLFW) reads, not just the raw CGEvent string.
        #expect(NSEvent(cgEvent: out)?.characters == RebindManager.silentCharacter)
    }

    @Test func typeOnlyHidesGameKeyButKeepsText() {
        var typeOnly = rebind(.key(.g), .key(.p))
        typeOnly.typeOnly = true

        let down = press(typeOnly)
        #expect(
            down.getIntegerValueField(.keyboardEventKeycode)
                == Int64(RebindManager.unmappedKeyCode))
        #expect(RebindManager.characters(of: down) == "p")

        #expect(RebindManager.characters(of: press(typeOnly, shift: true)) == "P")

        let up = press(typeOnly, down: false)
        #expect(
            up.getIntegerValueField(.keyboardEventKeycode)
                == Int64(RebindManager.unmappedKeyCode))
    }

    @Test func sideButtonToF3IsAKeyPress() {
        let click = CGEvent(
            mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero,
            mouseButton: .center)!
        click.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        let decoded = RebindManager.decode(type: .otherMouseDown, event: click)
        #expect(decoded?.0 == .mouse(3))
        #expect(decoded?.1 == true)

        let out = RebindManager.makeEvent(
            for: rebind(.mouse(3), .key(.f3)), isDown: true, isRepeat: false, like: click)!
        #expect(out.type == .keyDown)
        #expect(out.getIntegerValueField(.keyboardEventKeycode) == Int64(KeyCode.f3))
    }

    @Test func modifierOutputBecomesFlagsChanged() {
        let toShift = rebind(.key(.g), .key(.shift))
        let down = press(toShift)
        #expect(down.type == .flagsChanged)
        #expect(down.flags.contains(.maskShift))

        let up = press(toShift, down: false)
        #expect(up.type == .flagsChanged)
        #expect(!up.flags.contains(.maskShift))
    }

    @Test func contextRebindBeatsAlways() {
        var always = KeyRebind()
        always.to = .key(.f3)
        var menu = KeyRebind()
        menu.to = nil
        menu.when = .inMenu
        let candidates = [always, menu]

        #expect(RebindManager.pick(from: candidates, context: .inMenu) == menu)
        #expect(RebindManager.pick(from: candidates, context: .playing) == always)
        // Without State Output the context is unknown, so only Always applies.
        #expect(RebindManager.pick(from: candidates, context: nil) == always)
        #expect(RebindManager.pick(from: [menu], context: nil) == nil)
    }

    @Test func rebindMissingNewFieldsStillDecodes() throws {
        let rebind = try JSONDecoder().decode(
            KeyRebind.self, from: Data(#"{"to": {"key": {"_0": 99}}}"#.utf8))
        #expect(rebind.to == .key(.f3))
        #expect(rebind.when == .always)
        #expect(rebind.enabled)
    }

    @Test func settingsWithoutRebindsStillDecode() throws {
        let section = try JSONDecoder().decode(
            Preferences.KeybindSection.self, from: Data(#"{"blockingF3": true}"#.utf8))
        #expect(section.blockingF3)
        #expect(!section.rebindsEnabled)
        #expect(section.rebinds.isEmpty)

        var withRebind = section
        var rebind = KeyRebind()
        rebind.from = .mouse(3)
        rebind.to = .key(.f3)
        withRebind.rebinds = [rebind]
        let roundTripped = try JSONDecoder().decode(
            Preferences.KeybindSection.self, from: JSONEncoder().encode(withRebind))
        #expect(roundTripped.rebinds == withRebind.rebinds)
    }
}
