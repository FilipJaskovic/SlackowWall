//
//  RemapInputField.swift
//  SlackowWall
//

import SwiftUI

/// Click, then press a key or a non-left mouse button to record it.
/// A left click anywhere cancels recording, so mouse buttons (including left click)
/// can also be picked from the field's right-click menu.
struct RemapInputField: View {
    @Binding var input: RemapInput?
    /// Shown when `input` is nil.
    let placeholder: String

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: startRecording) {
                Text(isRecording ? "Press input" : input?.displayName ?? placeholder)
                    .foregroundStyle(isRecording || input == nil ? .secondary : .primary)
                    .frame(width: 100)
            }

            Button {
                input = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(input == nil ? 0 : 1)
            .disabled(input == nil)
        }
        .contextMenu {
            ForEach(0..<5) { button in
                Button(RemapInput.mouse(Int64(button)).displayName) {
                    input = .mouse(Int64(button))
                }
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]) { event in
            switch event.type {
                case .leftMouseDown:
                    stopRecording()
                    return event
                case .keyDown:
                    input = .key(event.keyCode)
                case .flagsChanged:
                    // Record modifiers on press only. Caps Lock only reports lock toggles,
                    // so rebinds ignore it.
                    guard event.keyCode != .capsLock,
                        let mask = KeyCode.modifierFlags(code: event.keyCode),
                        event.modifierFlags.contains(mask)
                    else { return nil }
                    input = .key(event.keyCode)
                default:
                    input = .mouse(Int64(event.buttonNumber))
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
