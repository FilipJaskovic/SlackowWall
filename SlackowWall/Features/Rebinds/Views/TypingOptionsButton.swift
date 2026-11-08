//
//  TypingOptionsButton.swift
//  SlackowWall
//

import SwiftUI

/// Shows a rebind's typing summary and opens a popover to change what it types,
/// what it types with Shift, and whether it only types.
struct TypingOptionsButton: View {
    @Binding var rebind: KeyRebind
    @State private var isOpen = false

    var body: some View {
        Button(rebind.typingSummary) { isOpen = true }
            .frame(width: 90)
            .disabled(!rebind.outputIsKey)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("Types")
                        TypedTextPicker(text: $rebind.typed, defaultLabel: "Normal")
                    }
                    GridRow {
                        Text("With Shift")
                        TypedTextPicker(
                            text: Binding(
                                get: { rebind.shiftTyped ?? .keyDefault },
                                set: { rebind.shiftTyped = $0 == .keyDefault ? nil : $0 }),
                            defaultLabel: "Same, shifted")
                    }
                    GridRow {
                        Toggle("Type only", isOn: $rebind.typeOnly)
                            .gridCellColumns(2)
                    }
                    Text(
                        "Type only sends the text without pressing a game key, so it only does something in chat and signs."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 260, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .gridCellColumns(2)
                }
                .padding(12)
            }
    }
}

/// Normal / Custom / Nothing, with a text field for Custom.
private struct TypedTextPicker: View {
    @Binding var text: TypedText
    let defaultLabel: String

    private enum Mode: Hashable { case keyDefault, custom, nothing }

    private var mode: Binding<Mode> {
        Binding(
            get: {
                switch text {
                    case .keyDefault: .keyDefault
                    case .custom: .custom
                    case .nothing: .nothing
                }
            },
            set: { mode in
                switch mode {
                    case .keyDefault: text = .keyDefault
                    case .custom: text = .custom(customText.wrappedValue)
                    case .nothing: text = .nothing
                }
            })
    }

    private var customText: Binding<String> {
        Binding(
            get: { if case .custom(let value) = text { value } else { "" } },
            set: { text = .custom($0) })
    }

    var body: some View {
        HStack {
            Picker("", selection: mode) {
                Text(defaultLabel).tag(Mode.keyDefault)
                Text("Custom").tag(Mode.custom)
                Text("Nothing").tag(Mode.nothing)
            }
            .labelsHidden()
            .frame(width: 130)

            if case .custom = text {
                TextField("Text", text: customText)
                    .frame(width: 60)
            }
        }
    }
}

extension TypedText {
    var label: String {
        switch self {
            case .keyDefault: "Normal"
            case .nothing: "Nothing"
            case .custom(let text): "\u{201C}\(text)\u{201D}"
        }
    }
}

extension KeyRebind {
    /// Compact description for the Typing button, e.g. "“g”, ⇧ “G”, only".
    var typingSummary: String {
        var parts = [typed.label]
        if let shiftTyped { parts.append("⇧ \(shiftTyped.label)") }
        if typeOnly { parts.append("only") }
        return parts.joined(separator: ", ")
    }
}
