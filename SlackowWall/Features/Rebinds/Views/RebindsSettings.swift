//
//  RebindsSettings.swift
//  SlackowWall
//

import SwiftUI

struct RebindsSettings: View {
    @AppSettings(\.keybinds) private var settings
    /// Input being edited in the keyboard layout.
    @State private var selection: RemapInput?

    var body: some View {
        SettingsPageView(title: "Rebinds", shouldDisableFocus: false) {
            SettingsCardView {
                VStack {
                    SettingsToggleView(
                        title: "Enable Rebinds",
                        description:
                            "Remap keys and mouse buttons only while a Minecraft instance is focused.",
                        option: $settings.rebindsEnabled)
                    Divider()
                    HStack {
                        SettingsLabel(
                            title: "Toggle Hotkey",
                            description: "Turns rebinds on or off from anywhere, with a click sound.",
                            font: .body)
                        KeybindingView(keybinding: \.rebindsToggleGKey)
                    }
                    Divider()
                    SettingsToggleView(
                        title: "Shortcuts Use Physical Keys",
                        description:
                            "SlackowWall keybinds react to the key you press, not the key Minecraft gets from a rebind.",
                        option: $settings.shortcutsUsePhysicalKeys)
                    Divider()
                    SettingsToggleView(
                        title: "Show Keyboard Layout",
                        description: "Off shows a plain list instead.",
                        option: $settings.showRebindKeyboard)
                }
            }

            SettingsLabel(
                title: "Rebinds",
                description:
                    "Right-click an input or output field to pick a mouse button. Blocked inputs never reach Minecraft, but your SlackowWall keybinds still see the key you pressed. Typing sets what a rebind types in chat, separately from the game key. Playing and In menus need the State Output mod, and win over Always for the same input."
            )
            .padding(.top, 5)

            if settings.showRebindKeyboard {
                keyboardEditor
            } else {
                list
            }
        }
    }

    private var keyboardEditor: some View {
        Group {
            SettingsCardView {
                RebindKeyboardView(rebinds: settings.rebinds, selection: $selection)
            }

            SettingsCardView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Input").fontWeight(.semibold)
                        RemapInputField(input: $selection, placeholder: "Click a key")
                        Spacer()
                    }
                    if let selection {
                        RebindInputEditor(input: selection, rebinds: $settings.rebinds)
                    } else {
                        Text("Click a key or mouse button above, or record any input here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var list: some View {
        if !settings.rebinds.isEmpty {
            SettingsCardView {
                VStack {
                    ForEach($settings.rebinds) { $rebind in
                        if rebind.id != settings.rebinds.first?.id { Divider() }
                        row($rebind)
                    }
                }
            }
        }

        Button("Add Rebind") {
            settings.rebinds.append(KeyRebind())
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Two lines so a row fits the fixed-width settings pane: mapping on top,
    /// condition and typing below.
    private func row(_ rebind: Binding<KeyRebind>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("", isOn: rebind.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                RemapInputField(input: rebind.from, placeholder: "Not set")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                RemapInputField(input: rebind.to, placeholder: "Blocked")

                Spacer()

                Button {
                    settings.rebinds.removeAll { $0.id == rebind.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            HStack {
                Picker("When", selection: rebind.when) {
                    ForEach(RebindCondition.allCases, id: \.self) { Text($0.label) }
                }
                .frame(width: 150)

                Text("Typing").foregroundStyle(.secondary)
                TypingOptionsButton(rebind: rebind)
            }
            .padding(.leading, 40)
        }
    }
}

#Preview {
    RebindsSettings()
}
