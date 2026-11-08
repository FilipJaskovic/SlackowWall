//
//  RebindInputEditor.swift
//  SlackowWall
//

import SwiftUI

/// Edits every rule for one input, one row per condition (Always, Playing, In menus).
/// Recording an output on an empty row creates its rule; Clear removes it.
struct RebindInputEditor: View {
    let input: RemapInput
    @Binding var rebinds: [KeyRebind]

    var body: some View {
        if input == .key(.capsLock) {
            Text("Caps Lock can't be rebound: macOS only reports when the lock toggles.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            grid
        }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("When")
                Text("Output")
                Text("Typing")
                Text("On")
                Text("")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(RebindCondition.allCases, id: \.self) { condition in
                Divider()
                row(condition)
            }
        }
    }

    @ViewBuilder private func row(_ condition: RebindCondition) -> some View {
        GridRow {
            HStack(spacing: 5) {
                Circle().fill(condition.color).frame(width: 6, height: 6)
                Text(condition.label)
            }
            .fixedSize()

            if let rule = binding(for: condition) {
                RemapInputField(input: rule.to, placeholder: "Blocked")
                if rule.wrappedValue.outputIsKey {
                    TypingOptionsButton(rebind: rule)
                } else {
                    Text("")
                }
                Toggle("", isOn: rule.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                Button("Clear") {
                    rebinds.removeAll { $0.id == rule.wrappedValue.id }
                }
            } else {
                RemapInputField(
                    input: Binding(get: { nil }, set: { add(condition, to: $0) }),
                    placeholder: hasRule(.always) && condition != .always
                        ? "Same as Always" : "Not rebound")
                Text("")
                Text("")
                Button("Block") { add(condition, to: nil) }
            }
        }
    }

    private func hasRule(_ condition: RebindCondition) -> Bool {
        rebinds.contains { $0.from == input && $0.when == condition }
    }

    private func add(_ condition: RebindCondition, to output: RemapInput?) {
        var rebind = KeyRebind()
        rebind.from = input
        rebind.to = output
        rebind.when = condition
        rebinds.append(rebind)
    }

    /// Binds to the rule by id so removing other rules can't shift it.
    private func binding(for condition: RebindCondition) -> Binding<KeyRebind>? {
        guard let id = rebinds.first(where: { $0.from == input && $0.when == condition })?.id
        else { return nil }
        return Binding(
            get: { rebinds.first { $0.id == id } ?? KeyRebind() },
            set: { new in
                if let index = rebinds.firstIndex(where: { $0.id == id }) {
                    rebinds[index] = new
                }
            })
    }
}

extension KeyRebind {
    /// Typed text only applies when the output is a key.
    var outputIsKey: Bool {
        if case .key = to { true } else { false }
    }
}
