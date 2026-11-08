//
//  KeyRebind.swift
//  SlackowWall
//

import DefaultCodable
import Foundation

/// A physical input a rebind reads, or the input it sends to Minecraft instead.
enum RemapInput: Codable, Hashable {
    case key(KeyCode)
    /// CGEvent button number: 0 left, 1 right, 2 middle, 3 back, 4 forward.
    case mouse(Int64)

    var displayName: String {
        switch self {
            case .key(let code): KeyCode.toName(code: code)
            case .mouse(0): "Left Click"
            case .mouse(1): "Right Click"
            case .mouse(2): "Middle Click"
            case .mouse(let button): "Mouse \(button + 1)"
        }
    }
}

/// When a rebind applies. `playing` means the cursor is captured (no screen open);
/// `inMenu` means it's free (inventory, chat, pause, title). Telling them apart needs the
/// State Output mod, so without it only `always` rebinds apply.
enum RebindCondition: String, Codable, CaseIterable {
    case always, playing, inMenu

    var label: String {
        switch self {
            case .always: "Always"
            case .playing: "Playing"
            case .inMenu: "In menus"
        }
    }
}

/// One Toolscreen-style rebind, applied only while a tracked Minecraft instance is frontmost.
/// Several rebinds may share an input: a matching `playing`/`inMenu` one wins over `always`.
@DefaultCodable
struct KeyRebind: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var enabled: Bool = true
    /// The input to intercept. The rebind does nothing until this is set.
    var from: RemapInput? = nil
    /// What Minecraft receives instead. `nil` blocks the input from reaching the game,
    /// while SlackowWall's own shortcuts still see it.
    var to: RemapInput? = nil
    var when: RebindCondition = .always
    /// What the press types in chat or signs. Only applies when `to` is a key.
    var typed: TypedText = .keyDefault
    /// Typed instead while Shift is held. `nil` reuses `typed`, uppercased when custom.
    var shiftTyped: TypedText? = nil
    /// Only type; Minecraft gets no game key press, so keybinds on `to` don't fire.
    var typeOnly: Bool = false

    init() {}

    /// The characters to type for one press, or nil to keep the output key's own character.
    func typedCharacters(shift: Bool) -> String? {
        let rule = shift ? shiftTyped ?? typed.shifted : typed
        switch rule {
            case .keyDefault: return nil
            case .nothing: return ""
            case .custom(let text): return text
        }
    }

    /// Whether typing differs from what the output key would normally type.
    var changesTyping: Bool {
        typed != .keyDefault || shiftTyped != nil || typeOnly
    }
}

/// What a rebind types, separate from the game key it presses.
enum TypedText: Codable, Hashable {
    /// Whatever the output key normally types.
    case keyDefault
    /// Types nothing, so the key only acts as a game key.
    case nothing
    case custom(String)

    /// The Shift version of this rule when no explicit Shift rule is set.
    var shifted: Self {
        if case .custom(let text) = self { .custom(text.uppercased()) } else { self }
    }
}
