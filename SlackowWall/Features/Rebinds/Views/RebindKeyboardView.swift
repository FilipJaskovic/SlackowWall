//
//  RebindKeyboardView.swift
//  SlackowWall
//

import Carbon.HIToolbox
import SwiftUI

/// Physical key shape of the keyboard last typed on. JIS falls back to ANSI.
enum KeyboardShape {
    /// US shape: wide Return, long left Shift.
    case ansi
    /// European shape: tall L-shaped Return, extra key next to a short left Shift.
    case iso

    static var current: Self {
        KBGetLayoutType(Int16(LMGetKbdType())) == PhysicalKeyboardLayoutType(kKeyboardISO)
            ? .iso : .ansi
    }
}

/// A clickable Mac keyboard and mouse showing which inputs have rebinds.
/// The keyboard follows the physical shape of the user's keyboard (ANSI or ISO).
/// Key color follows the Always rule (or the first rule when there is none);
/// dots show every condition that has a rule.
struct RebindKeyboardView: View {
    let rebinds: [KeyRebind]
    @Binding var selection: RemapInput?
    var shape: KeyboardShape = .current

    private static let unit: CGFloat = 26.5
    private static let gap: CGFloat = 3

    /// Point width of a cap `units` wide, so every 15-unit row lines up.
    private static func span(_ units: CGFloat) -> CGFloat {
        units * (unit + gap) - gap
    }

    private typealias Cap = (code: KeyCode, width: CGFloat)

    /// Standard-width caps for a run of keys.
    private static func keys(_ codes: KeyCode...) -> [Cap] {
        codes.map { ($0, 1) }
    }

    /// Key rows, each 15 units wide. On ISO the Return key is drawn separately
    /// beside rows 2 and 3, and the arrow cluster always follows the last row.
    private static func rows(_ shape: KeyboardShape) -> [[Cap]] {
        let iso = shape == .iso
        let fKeys: [KeyCode] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]

        var function: [Cap] = [(.escape, 1.5)]
        function += fKeys.map { ($0, 1.125) }

        var numbers = keys(iso ? .section : .grave)
        numbers += keys(.one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero)
        numbers += keys(.minus, .equals) + [(.delete, 2)]

        var top: [Cap] = [(.tab, 1.5)]
        top += keys(.q, .w, .e, .r, .t, .y, .u, .i, .o, .p, .leftBracket, .rightBracket)
        if !iso { top.append((.backslash, 1.5)) }

        var home: [Cap] = [(.capsLock, 1.75)]
        home += keys(.a, .s, .d, .f, .g, .h, .j, .k, .l, .semicolon, .apostrophe)
        home += iso ? keys(.backslash) : [(.returnKey, 2.25)]

        var bottom: [Cap] = iso ? [(.shift, 1.25), (.grave, 1)] : [(.shift, 2.25)]
        bottom += keys(.z, .x, .c, .v, .b, .n, .m, .comma, .period, .forwardSlash)
        bottom.append((.rightShift, 2.75))

        var modifiers = keys(.function, .control, .option)
        modifiers += [(.command, 1.25), (.space, 5.5), (.rightCommand, 1.25)]
        modifiers += keys(.rightOption)

        return [function, numbers, top, home, bottom, modifiers]
    }

    private static let arrows: [KeyCode] = [.leftArrow, .upArrow, .downArrow, .rightArrow]

    /// Shorter cap labels than `KeyCode.toName` where that name doesn't fit.
    private static let shortNames: [KeyCode: String] = [
        .delete: "⌫", .returnKey: "↩", .tab: "⇥", .capsLock: "⇪", .space: "",
        .leftArrow: "←", .upArrow: "↑", .downArrow: "↓", .rightArrow: "→",
    ]

    /// Inputs drawn on either keyboard shape or the mouse; rebinds for anything else
    /// are listed separately.
    static let drawnInputs: Set<RemapInput> = Set(
        (rows(.ansi).joined().map(\.code) + rows(.iso).joined().map(\.code) + arrows)
            .map(RemapInput.key) + (0...4).map(RemapInput.mouse))

    var body: some View {
        let rows = Self.rows(shape)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: Self.gap) {
                row(rows[0])
                row(rows[1])
                if shape == .iso {
                    // The home row runs under Return's narrower bottom, so pin Return
                    // to the right edge instead of stacking it beside the rows.
                    ZStack(alignment: .topTrailing) {
                        VStack(alignment: .leading, spacing: Self.gap) {
                            row(rows[2])
                            row(rows[3])
                        }
                        .frame(width: Self.span(15), alignment: .leading)
                        isoReturn
                    }
                } else {
                    row(rows[2])
                    row(rows[3])
                }
                row(rows[4])
                HStack(spacing: Self.gap) {
                    row(rows[5])
                    arrowCluster
                }
            }

            HStack(alignment: .top, spacing: 16) {
                mouse
                VStack(alignment: .leading, spacing: 6) {
                    legend
                    otherInputs
                }
            }
        }
    }

    private func row(_ caps: [Cap]) -> some View {
        HStack(spacing: Self.gap) {
            ForEach(caps.indices, id: \.self) { index in
                key(caps[index].code, width: caps[index].width)
            }
        }
    }

    private func key(_ code: KeyCode, width: CGFloat = 1, height: CGFloat = unit) -> some View {
        cap(
            .key(code), label: Self.shortNames[code] ?? KeyCode.toName(code: code), width: width,
            height: height)
    }

    /// The tall ISO Return: 1.5 units wide on the top row, 1.25 on the home row.
    private var isoReturn: some View {
        cap(
            .key(.returnKey), label: "↩", width: 1.5, height: Self.unit * 2 + Self.gap,
            shape: AnyShape(
                ISOReturnShape(bottomWidth: Self.span(1.25), topHeight: Self.unit)),
            contentHeight: Self.unit)
    }

    /// Mac layout: left and right are full height, up and down share one slot.
    private var arrowCluster: some View {
        let half = (Self.unit - Self.gap) / 2
        return HStack(spacing: Self.gap) {
            key(.leftArrow)
            VStack(spacing: Self.gap) {
                key(.upArrow, height: half)
                key(.downArrow, height: half)
            }
            key(.rightArrow)
        }
    }

    private var mouse: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(spacing: 4) {
                cap(.mouse(4), label: "M5", width: 1.2, height: 26)
                cap(.mouse(3), label: "M4", width: 1.2, height: 26)
            }
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    cap(.mouse(0), label: "L", width: 1.2, height: 44)
                    cap(.mouse(1), label: "R", width: 1.2, height: 44)
                }
                cap(.mouse(2), label: "Mid", width: 1, height: 24)
            }
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 22).stroke(.gray.opacity(0.5), lineWidth: 1))
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ForEach(RebindCondition.allCases, id: \.self) { condition in
                    HStack(spacing: 4) {
                        Circle().fill(condition.color).frame(width: 6, height: 6)
                        Text(condition.label)
                    }
                }
            }
            HStack(spacing: 10) {
                ForEach(RebindKind.allCases, id: \.self) { kind in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(kind.color.opacity(0.45))
                            .frame(width: 10, height: 10)
                        Text(kind.label)
                    }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Rebound inputs with no cap on the drawing, such as numpad keys or extra mouse buttons.
    @ViewBuilder private var otherInputs: some View {
        let others = rebinds.compactMap(\.from).filter { !Self.drawnInputs.contains($0) }
            .reduce(into: [RemapInput]()) { if !$0.contains($1) { $0.append($1) } }
        if !others.isEmpty {
            HStack(spacing: 4) {
                Text("Other:").foregroundStyle(.secondary)
                ForEach(others, id: \.self) { input in
                    Button(input.displayName) { selection = input }
                        .buttonStyle(.link)
                        .fontWeight(selection == input ? .bold : .regular)
                }
            }
            .font(.caption)
        }
    }

    /// One clickable key or button. `contentHeight` limits the labels to the top of
    /// tall shapes like the ISO Return.
    private func cap(
        _ input: RemapInput, label: String, width: CGFloat, height: CGFloat = unit,
        shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: 4)),
        contentHeight: CGFloat? = nil
    ) -> some View {
        let rules = rebinds.filter { $0.enabled && $0.from == input }
        let primary = rules.first { $0.when == .always } ?? rules.first
        let kind = primary.map(RebindKind.init)
        let isSelected = selection == input

        return Button {
            selection = input
        } label: {
            ZStack(alignment: .topLeading) {
                shape
                    .fill(kind?.color.opacity(0.45) ?? Color(nsColor: .controlBackgroundColor))
                shape
                    .stroke(
                        isSelected ? Color.primary : kind?.color ?? .gray.opacity(0.5),
                        lineWidth: isSelected ? 2 : 1)

                VStack(alignment: .leading, spacing: 0) {
                    Text(label).font(.system(size: 8))
                    Spacer(minLength: 0)
                    // Half-height arrow caps only have room for the color.
                    if let primary, height >= 20 {
                        Text(primary.outputSummary)
                            .font(.system(size: 8, weight: .bold))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .frame(height: contentHeight ?? height)

                HStack(spacing: 1) {
                    ForEach(RebindCondition.allCases, id: \.self) { condition in
                        if rules.contains(where: { $0.when == condition }) {
                            Circle().fill(condition.color).frame(width: 4, height: 4)
                        }
                    }
                }
                .padding(3)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
            .frame(width: Self.span(width), height: height)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        // Caps Lock only reports lock toggles on macOS, so it can't be held or rebound.
        .disabled(input == .key(.capsLock))
        .opacity(input == .key(.capsLock) ? 0.4 : 1)
    }
}

/// The L-shaped ISO Return: full width on top, narrower and right-aligned below.
private struct ISOReturnShape: Shape {
    let bottomWidth: CGFloat
    let topHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        let inner = rect.maxX - bottomWidth
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: inner, y: rect.maxY),
            CGPoint(x: inner, y: rect.minY + topHeight),
            CGPoint(x: rect.minX, y: rect.minY + topHeight),
        ]
        var path = Path()
        // Start mid-edge so every corner gets the same rounded arc.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + topHeight / 2))
        for index in corners.indices {
            path.addArc(
                tangent1End: corners[index], tangent2End: corners[(index + 1) % corners.count],
                radius: 4)
        }
        path.closeSubpath()
        return path
    }
}

/// How a rebind treats its input, used to color keys.
enum RebindKind: CaseIterable {
    case remap, split, block

    init(_ rebind: KeyRebind) {
        self =
            if rebind.to == nil { .block } else if rebind.changesTyping { .split } else { .remap }
    }

    var label: String {
        switch self {
            case .remap: "Remapped"
            case .split: "Split"
            case .block: "Blocked"
        }
    }

    var color: Color {
        switch self {
            case .remap: .purple
            case .split: .teal
            case .block: .red
        }
    }
}

extension RebindCondition {
    var color: Color {
        switch self {
            case .always: .purple
            case .playing: .green
            case .inMenu: .orange
        }
    }
}

extension KeyRebind {
    /// Short output label for a key cap: "F3", "P · g" (types g), "“g”" (type only),
    /// "P · ∅" (types nothing) or "✕" when blocked.
    var outputSummary: String {
        guard let to else { return "✕" }
        guard changesTyping else { return to.displayName }
        let typed = typedCharacters(shift: false).map { $0.isEmpty ? "∅" : $0 }
        if typeOnly { return "\u{201C}\(typed ?? to.displayName.lowercased())\u{201D}" }
        return typed.map { "\(to.displayName) · \($0)" } ?? to.displayName
    }
}
