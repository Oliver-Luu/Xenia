//
//  Components.swift
//  Xenia
//
//  Hand-built controls for the Instrument look. No stock Form/List styling,
//  no shadows, no materials. Structure comes from hairlines and the grid.
//

import SwiftUI

// MARK: - Screen scaffold

/// Full-bleed ground, a fixed header, and a scroll region that insets itself
/// past the tab bar.
struct InstrumentScreen<Content: View, Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                InstrumentHeader(title: title) { trailing() }
                ScrollView {
                    VStack(alignment: .leading, spacing: Grid.x6) {
                        content()
                    }
                    .padding(.horizontal, Grid.x4)
                    .padding(.top, Grid.x5)
                    .padding(.bottom, Grid.x8 + Grid.tabBar)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Palette.ground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                        .font(.system(.body, weight: .semibold))
                        .tint(Palette.accentText)
                }
            }
        }
    }
}

func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
    )
}

extension InstrumentScreen where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

extension InstrumentScreen {
    init(_ title: LocalizedStringKey,
         @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: trailing, content: content)
    }
}

struct InstrumentHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.screenTitle)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: Grid.x3)
            trailing()
        }
        .padding(.horizontal, Grid.x4)
        .padding(.top, Grid.x2)
        .padding(.bottom, Grid.x4)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            Rectangle().fill(Palette.rule).frame(height: 1)
        }
        .background(Palette.ground)
    }
}

// MARK: - Panel

/// A raised block: panel fill, hairline frame, no shadow.
struct Panel<Content: View>: View {
    var padding: CGFloat = Grid.x4
    var spacing: CGFloat = Grid.x3
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: Corner.panel)
                .strokeBorder(Palette.rule, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: Corner.panel))
    }
}

/// Label sitting above a group of content, ledger-column style.
struct FieldGroup<Content: View>: View {
    let label: Text
    var note: Text?
    @ViewBuilder var content: () -> Content

    init(label: LocalizedStringKey, note: LocalizedStringKey? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = Text(label)
        self.note = note.map { Text($0) }
        self.content = content
    }

    /// For a label that's real data (a place name) rather than app copy — shown
    /// as-is, never run through the localization catalog.
    init<S: StringProtocol>(label: S, note: LocalizedStringKey? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = Text(label)
        self.note = note.map { Text($0) }
        self.content = content
    }

    /// For a note that's already resolved (e.g. built from shared, pre-localized
    /// copy) rather than a literal at the call site — shown as-is, not looked up
    /// again in the catalog.
    init<S: StringProtocol>(label: S, note: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = Text(label)
        self.note = Text(verbatim: note)
        self.content = content
    }

    /// For an optional note built from shared, pre-localized copy.
    init(label: LocalizedStringKey, note: String?, @ViewBuilder content: @escaping () -> Content) {
        self.label = Text(label)
        self.note = note.map { Text(verbatim: $0) }
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.x2) {
            label.sectionLabelStyle()
            content()
            if let note {
                note
                    .font(.noteText)
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Rows

/// `label ................ value` with a monospaced, right-aligned value.
struct LedgerRow: View {
    let label: Text
    let value: String
    var emphasized = false
    var negative = false

    init(label: LocalizedStringKey, value: String, emphasized: Bool = false, negative: Bool = false) {
        self.label = Text(label)
        self.value = value
        self.emphasized = emphasized
        self.negative = negative
    }

    /// For a label that's real data (a rule or rating title) rather than app
    /// copy — shown as-is, never run through the localization catalog.
    init<S: StringProtocol>(label: S, value: String, emphasized: Bool = false, negative: Bool = false) {
        self.label = Text(label)
        self.value = value
        self.emphasized = emphasized
        self.negative = negative
    }

    var body: some View {
        HStack(spacing: Grid.x3) {
            label
                .font(emphasized ? .figure.weight(.semibold) : .bodyText)
                .foregroundStyle(emphasized ? Palette.ink : Palette.inkDim)
            Spacer(minLength: Grid.x2)
            Text(value)
                .font(emphasized ? .readoutMid : .figure)
                .foregroundStyle(negative ? Palette.negative : Palette.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

struct HairRule: View {
    var body: some View {
        Rectangle().fill(Palette.rule).frame(height: 1)
    }
}

/// Tappable row used in pickers and lists: leading content, chevron, hairline.
/// Owns its edge padding so the pressed-state wash fills the whole row rather
/// than an inset rectangle — callers must not add their own horizontal padding.
struct SelectRow<Leading: View>: View {
    var isSelected: Bool = false
    var showsChevron: Bool = true
    /// Set for rows that live inside an `InstrumentList` next to `.swipeActions`.
    /// A custom `ButtonStyle` there fires the row's action mid-swipe; `.plain`
    /// lets `List` tell a tap from a swipe. Costs the press wash, which is fine
    /// for a row whose feedback is the sheet it opens.
    var swipeSafe: Bool = false
    let action: () -> Void
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: Grid.x3) {
                leading()
                Spacer(minLength: Grid.x2)
                if isSelected {
                    AccentTick()
                } else if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .padding(.horizontal, Grid.x4)
            .padding(.vertical, Grid.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .modifier(SelectRowStyle(swipeSafe: swipeSafe))
    }
}

private struct SelectRowStyle: ViewModifier {
    var swipeSafe: Bool

    func body(content: Content) -> some View {
        if swipeSafe {
            content.buttonStyle(.plain)
        } else {
            content.buttonStyle(RowButtonStyle())
        }
    }
}

struct AccentTick: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.onAccent)
            .frame(width: 20, height: 20)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Instrument list

/// A screen built around a `List` (for native swipe-to-delete) instead of the
/// plain `ScrollView` in `InstrumentScreen`. Same custom header; the List is
/// restyled so rows read as one hairline-ruled panel rather than stock cells.
struct InstrumentList<Content: View, Trailing: View>: View {
    let title: LocalizedStringKey
    /// Extra space above the header — used when the list is shown in a sheet so
    /// the title clears the grab indicator.
    var headerTopPadding: CGFloat = 0
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    /// Bumped whenever the screen leaves the tab bar so a half-open swipe row is
    /// rebuilt closed instead of still sitting open when you come back.
    @State private var generation = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                InstrumentHeader(title: title) { trailing() }
                    .padding(.top, headerTopPadding)
                List {
                    content()
                }
                .id(generation)
                .listStyle(.plain)
                .listRowSpacing(0)
                .environment(\.defaultMinListRowHeight, 0)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(.horizontal, Grid.x4, for: .scrollContent)
                .contentMargins(.top, Grid.x5, for: .scrollContent)
                .contentMargins(.bottom, Grid.x12 + Grid.tabBar, for: .scrollContent)
            }
            .background(Palette.ground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onDisappear { generation += 1 }
    }
}

extension InstrumentList where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, headerTopPadding: CGFloat = 0, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, headerTopPadding: headerTopPadding, trailing: { EmptyView() }, content: content)
    }
}

extension InstrumentList {
    init(_ title: LocalizedStringKey,
         headerTopPadding: CGFloat = 0,
         @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, headerTopPadding: headerTopPadding, trailing: trailing, content: content)
    }
}

/// One row in an `InstrumentList` panel group: panel fill, hairline below except
/// on the last row, rounded top/bottom corners at the group's edges. Clears the
/// stock cell chrome so swipe actions read against the Instrument palette.
struct PanelRow<Content: View>: View {
    var isFirst: Bool
    var isLast: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel)
            .overlay(alignment: .bottom) {
                if !isLast { HairRule() }
            }
            .clipShape(
                .rect(
                    topLeadingRadius: isFirst ? Corner.panel : 0,
                    bottomLeadingRadius: isLast ? Corner.panel : 0,
                    bottomTrailingRadius: isLast ? Corner.panel : 0,
                    topTrailingRadius: isFirst ? Corner.panel : 0
                )
            )
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: isFirst ? Corner.panel : 0,
                    bottomLeadingRadius: isLast ? Corner.panel : 0,
                    bottomTrailingRadius: isLast ? Corner.panel : 0,
                    topTrailingRadius: isFirst ? Corner.panel : 0
                )
                .strokeBorder(Palette.rule, lineWidth: 1)
                .allowsHitTesting(false)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

extension View {
    /// Strips stock `List` row chrome for free-standing content (headers, empty
    /// states) inside an `InstrumentList`.
    func plainListRow() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Trailing swipe-to-delete in the app's red. Full-swipe is off — its
    /// expand/contract animation reads badly against the custom row chrome — so
    /// pair this with an optimistic hide in the caller (drop the row from the
    /// `ForEach` source inside `withAnimation`) so it leaves the moment you tap,
    /// instead of waiting on `@Query` to round-trip.
    ///
    /// The button is deliberately NOT `role: .destructive`: that makes `List`
    /// optimistically collapse the row the instant it's tapped, so the rows
    /// below jump up and then snap back down when no data change lands within
    /// its window — fighting the blink. The blink and the caller's animated
    /// removal own every pixel of the delete; `List` must not pre-empt them.
    func deleteSwipeAction(perform: @escaping () -> Void) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: perform) {
                Label("Delete", systemImage: "trash")
            }
            .tint(Palette.destructive)
        }
    }
}

// MARK: - Buttons

/// Primary action: amber fill, real pressed state (scale + darken), never a
/// hover/opacity fade.
struct FilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.accent)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .clipShape(RoundedRectangle(cornerRadius: Corner.control))
            .contentShape(RoundedRectangle(cornerRadius: Corner.control))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary action: hairline frame, ink label.
struct GhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(configuration.isPressed ? Palette.well : Palette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: Corner.control)
                    .strokeBorder(Palette.ruleStrong, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: Corner.control))
            .contentShape(RoundedRectangle(cornerRadius: Corner.control))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// Destructive action: muted rust label and frame.
struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(Palette.negative)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(configuration.isPressed ? Palette.well : Palette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: Corner.control)
                    .strokeBorder(Palette.negative.opacity(0.5), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: Corner.control))
            .contentShape(RoundedRectangle(cornerRadius: Corner.control))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// Row press feedback: a brief wash, no fade-out.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Palette.ink.opacity(configuration.isPressed ? 0.05 : 0))
    }
}

/// A panel row with a leading up/down reorder control and a full-width tap
/// target that opens an editor. Used for adjustment rules and rating dimensions
/// in both the category editor and the per-place editor.
struct ReorderableRow<Label: View>: View {
    let index: Int
    let count: Int
    let onEdit: () -> Void
    let onMove: (Int) -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: Grid.x2) {
                Color.clear.frame(width: 34)
                label()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.leading, Grid.x3)
            .padding(.trailing, Grid.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .overlay(alignment: .leading) {
            VStack(spacing: 0) {
                moveButton("chevron.up", "Move up", enabled: index > 0) { onMove(-1) }
                moveButton("chevron.down", "Move down", enabled: index < count - 1) { onMove(1) }
            }
            .padding(.leading, Grid.x2)
        }
    }

    private func moveButton(
        _ symbol: String, _ label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? Palette.inkDim : Palette.inkFaint.opacity(0.4))
                .frame(width: 32, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// The "+ Add a …" affordance that closes out a panel of editable rows.
struct AddRow: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Grid.x1) {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                Text(title).font(.system(.subheadline, weight: .semibold))
            }
            .foregroundStyle(Palette.accentText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Grid.x4)
            .padding(.vertical, Grid.x3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Steppers & selectors

/// Holds the current tick action so a running hold-repeat loop always calls the
/// latest closure (with fresh captured state) rather than a stale one.
final class StepActionBox {
    var perform: () -> Void = {}
}

/// A `+`/`-` glyph that fires once on tap and then auto-repeats — accelerating —
/// while held. Stops on release, when the finger slides off (so it doesn't fight
/// a scroll), or when `enabled` goes false at a range bound.
struct HoldRepeatButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    @GestureState private var held = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var box = StepActionBox()

    var body: some View {
        box.perform = action
        return Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(enabled ? Palette.ink : Palette.inkFaint)
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
            .background(Palette.ink.opacity(held && enabled ? 0.06 : 0))
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 999, maximumDistance: 16)
                    .updating($held) { _, state, _ in state = true }
            )
            .onChange(of: held) { _, isHeld in
                if isHeld && enabled { startRepeating() } else { stopRepeating() }
            }
            .onChange(of: enabled) { _, isEnabled in
                if !isEnabled { stopRepeating() }
            }
            .onDisappear { stopRepeating() }
            .accessibilityElement()
            .accessibilityLabel(symbol)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Hold to change quickly")
            .accessibilityAction { if enabled { action() } }
    }

    private func startRepeating() {
        box.perform()
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            // Ramp from ~3.5/sec up to a ~12/sec top speed over ~1s of holding.
            var delayMS = 280
            while !Task.isCancelled {
                box.perform()
                delayMS = max(83, delayMS - 40)
                try? await Task.sleep(for: .milliseconds(delayMS))
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

/// `[ - ]  value  [ + ]` with a monospaced readout. Replaces stock Stepper.
/// Hold a button to repeat, faster the longer you hold.
struct PlusMinus: View {
    let value: Int
    let range: ClosedRange<Int>
    var display: LocalizedStringKey?
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            HoldRepeatButton(symbol: "minus", enabled: value > range.lowerBound) {
                onChange(max(range.lowerBound, value - 1))
            }
            Text(display ?? "\(value)")
                .font(.figure)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 44)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 2)
            HoldRepeatButton(symbol: "plus", enabled: value < range.upperBound) {
                onChange(min(range.upperBound, value + 1))
            }
        }
        .frame(height: 40)
        .background(Palette.well)
        .overlay(RoundedRectangle(cornerRadius: Corner.control).strokeBorder(Palette.rule, lineWidth: 1).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: Corner.control))
    }
}

/// 1...max rating as a filled track of squares. No stars.
struct RatingTrack: View {
    let value: Int
    var maxScore: Int = 5
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: Grid.x1) {
            ForEach(1...max(maxScore, 2), id: \.self) { step in
                Button {
                    onChange(step)
                } label: {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(step <= value ? Palette.accent : Palette.well)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Palette.rule, lineWidth: step <= value ? 0 : 1)
                        )
                        .frame(height: 28)
                        .frame(minWidth: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set to \(step)")
            }
        }
    }
}

/// A single-line text well for numeric or short text entry.
struct FieldWell: View {
    /// Distinguishes app copy (localized) from an already-formatted, non-
    /// translatable placeholder like a currency-shaped "0.00".
    enum Placeholder {
        case key(LocalizedStringKey)
        case verbatim(String)
    }

    let placeholder: Placeholder
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var alignment: TextAlignment = .leading
    var prefix: String?
    var icon: String?
    var showsClear = false
    var focus: FocusState<Bool>.Binding?

    init(
        placeholder: LocalizedStringKey,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        alignment: TextAlignment = .leading,
        prefix: String? = nil,
        icon: String? = nil,
        showsClear: Bool = false,
        focus: FocusState<Bool>.Binding? = nil
    ) {
        self.placeholder = .key(placeholder)
        self._text = text
        self.keyboard = keyboard
        self.alignment = alignment
        self.prefix = prefix
        self.icon = icon
        self.showsClear = showsClear
        self.focus = focus
    }

    /// For a placeholder that's a formatted value (e.g. "0.00") rather than app
    /// copy — shown as-is, never run through the localization catalog.
    init(
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        alignment: TextAlignment = .leading,
        prefix: String? = nil,
        icon: String? = nil,
        showsClear: Bool = false,
        focus: FocusState<Bool>.Binding? = nil
    ) {
        self.placeholder = .verbatim(placeholder)
        self._text = text
        self.keyboard = keyboard
        self.alignment = alignment
        self.prefix = prefix
        self.icon = icon
        self.showsClear = showsClear
        self.focus = focus
    }

    var body: some View {
        HStack(spacing: Grid.x2) {
            if let icon {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Palette.inkFaint)
            }
            if let prefix {
                Text(prefix).font(.figure).foregroundStyle(Palette.inkDim)
            }
            Group {
                switch placeholder {
                case .key(let key):
                    if let focus {
                        TextField(key, text: $text).focused(focus)
                    } else {
                        TextField(key, text: $text)
                    }
                case .verbatim(let raw):
                    if let focus {
                        TextField(raw, text: $text).focused(focus)
                    } else {
                        TextField(raw, text: $text)
                    }
                }
            }
            .font(.figure)
            .keyboardType(keyboard)
            .multilineTextAlignment(alignment)
            .foregroundStyle(Palette.ink)

            if showsClear && !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear text")
            }
        }
        .padding(.horizontal, Grid.x3)
        .frame(height: 44)
        .background(Palette.well)
        .overlay(RoundedRectangle(cornerRadius: Corner.control).strokeBorder(Palette.rule, lineWidth: 1).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: Corner.control))
        .contentShape(Rectangle())
        .onTapGesture {
            // The bare TextField only takes taps on the glyphs themselves; a tap
            // in the well's padding was being dropped, so it took two.
            if let focus, !focus.wrappedValue { focus.wrappedValue = true }
        }
    }
}

/// On/off control drawn as a filled marker, not a platform switch.
/// The checkbox mark, drawn only — it is NOT tappable on its own. Every use sits
/// inside a row that is already a Button (or has its own tap gesture); nesting a
/// Button here would swallow the tap and leave the box dead while the label works.
struct MarkerBox: View {
    let isOn: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(isOn ? Palette.accent : Palette.well)
            .overlay(
                RoundedRectangle(cornerRadius: 5).strokeBorder(isOn ? Color.clear : Palette.ruleStrong, lineWidth: 1.5)
            )
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Palette.onAccent)
                }
            }
            .frame(width: 26, height: 26)
            .allowsHitTesting(false)
    }
}

// MARK: - Small pieces

/// Text-only category tag. No colored border, no icon box.
struct CategoryTag: View {
    let name: String?
    var body: some View {
        Group {
            if let name {
                Text(name)
            } else {
                Text("No category")
            }
        }
        .textCase(.uppercase)
        .font(.system(.caption2, weight: .semibold))
        .tracking(0.8)
        .foregroundStyle(Palette.inkDim)
    }
}

/// Compact header action: symbol + short label, accent text, no frame.
struct HeaderButton: View {
    let title: LocalizedStringKey
    var symbol: String = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Grid.x1) {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                Text(title).font(.system(.subheadline, weight: .semibold))
            }
            .foregroundStyle(Palette.accentText)
            .padding(.vertical, Grid.x1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Empty-state block: one glyph, a line, a sentence. Left-aligned, no card.
struct BlankSlate: View {
    let headline: LocalizedStringKey
    let message: LocalizedStringKey
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.x3) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Palette.inkDim)
            Text(headline)
                .font(.cardTitle)
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(.bodyText)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Grid.x2)
        .padding(.bottom, Grid.x8)
    }
}

// MARK: - Sheet scaffold

/// Custom sheet header: title left, Cancel / confirm split. Matches the screen
/// header so sheets don't drop back to stock styling.
struct SheetScaffold<Content: View>: View {
    let title: LocalizedStringKey
    var confirmTitle: LocalizedStringKey = "Save"
    var confirmEnabled: Bool = true
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel)
                    .font(.bodyText)
                    .foregroundStyle(Palette.inkDim)
                Spacer()
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button(confirmTitle, action: onConfirm)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(confirmEnabled ? Palette.accentText : Palette.inkFaint)
                    .disabled(!confirmEnabled)
            }
            .padding(.horizontal, Grid.x4)
            .padding(.top, Grid.x6)
            .padding(.bottom, Grid.x3)
            .background(alignment: .bottom) { HairRule() }

            ScrollView {
                VStack(alignment: .leading, spacing: Grid.x6) {
                    content()
                }
                .padding(.horizontal, Grid.x4)
                .padding(.vertical, Grid.x5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Palette.ground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
                    .font(.system(.body, weight: .semibold))
                    .tint(Palette.accentText)
            }
        }
        }
        .presentationDragIndicator(.visible)
    }
}
