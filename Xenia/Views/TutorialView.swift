//
//  TutorialView.swift
//  Xenia
//
//  Renders whatever `TutorialScript.pages` contains — a title, a paragraph, an
//  optional bullet panel, an optional slice of the practice calculator, an
//  optional self-ticking task — with progress marks, Back/Next and Skip around
//  it. It knows nothing about how many pages there are or what they say, so
//  changing the tutorial means editing the script, not this file.
//

import SwiftUI

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var session = PracticeSession()
    @FocusState private var billFocused: Bool

    /// Never empty: a script edited down to nothing would otherwise leave the
    /// user stuck behind a blank full-screen cover with no way out.
    private let pages: [TutorialPage] = {
        let scripted = TutorialScript.pages
        guard scripted.isEmpty else { return scripted }
        return [TutorialPage(
            id: "empty",
            title: String(localized: "Welcome to Xenia"),
            body: String(localized: "Pick a place, put in the bill, say how it went.")
        )]
    }()

    /// Clamped, so an index left past the end can't read off the array.
    private var page: TutorialPage { pages[min(max(index, 0), pages.count - 1)] }
    private var isLast: Bool { index >= pages.count - 1 }

    /// A required goal holds the Next button until it's done. Skip always works,
    /// so this nudges rather than traps.
    private var canAdvance: Bool {
        guard page.goalRequired, let goal = page.goal else { return true }
        return goal.isMet(in: session)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Grid.x5) {
                            pageContent
                        }
                        .padding(.horizontal, Grid.x4)
                        .padding(.top, Grid.x5)
                        .padding(.bottom, Grid.x8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Rebuild on page change so each page opens at the top, on its
                    // heading and explanation — not scrolled partway down the
                    // calculator to the section it introduces.
                    .id(page.id)
                    .scrollDismissesKeyboard(.interactively)
                    // Pull the bill field clear of the number pad when it's tapped;
                    // the wait lets the keyboard finish coming up first.
                    .onChange(of: billFocused) { _, focused in
                        guard focused else { return }
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            withAnimation(.snappy(duration: 0.3)) {
                                proxy.scrollTo(TutorialPracticeView.billAnchor, anchor: .top)
                            }
                        }
                    }
                }
                footer
            }
            .background(Palette.ground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: Grid.x3) {
                progressMarks
                Spacer(minLength: Grid.x2)
                if !isLast {
                    Button("Skip") { close() }
                        .font(.bodyText)
                        .foregroundStyle(Palette.inkDim)
                }
            }
            .padding(.horizontal, Grid.x4)
            .padding(.top, Grid.x4)
            .padding(.bottom, Grid.x3)

            // On practice pages the figure stays put while the page scrolls, so
            // the ratings and adjustments visibly move it.
            if page.practice != nil {
                HairRule()
                TutorialTipStrip(session: session)
                    .padding(.horizontal, Grid.x4)
                    .padding(.vertical, Grid.x2)
            }
        }
        .background(alignment: .bottom) { HairRule() }
        .background(Palette.ground)
    }

    private var progressMarks: some View {
        HStack(spacing: 5) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { position, _ in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(mark(at: position))
                    .frame(width: position == index ? 18 : 8, height: 3)
            }
        }
        .animation(.snappy(duration: 0.25), value: index)
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(pages.count)")
    }

    private func mark(at position: Int) -> Color {
        if position == index { return Palette.accent }
        return position < index ? Palette.inkDim : Palette.rule
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HairRule()
            // The number pad has no return key, and a keyboard toolbar doesn't
            // reliably render inside a full-screen cover, so the way out of the
            // pad lives here — directly above it once the footer lifts.
            if billFocused {
                HStack {
                    Spacer()
                    Button("Done") { billFocused = false }
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Palette.accentText)
                }
                .padding(.horizontal, Grid.x4)
                .padding(.vertical, Grid.x2)
                HairRule()
            }
            // The task rides above the buttons rather than in the page, so it's
            // still in front of the user once they've scrolled down to do it.
            if let goal = page.goal {
                goalRow(goal)
                HairRule()
            }
            HStack(spacing: Grid.x3) {
                if index > 0 {
                    Button("Back") { step(-1) }
                        .buttonStyle(GhostButtonStyle())
                        .frame(width: 110)
                }
                Button(isLast ? "Start tipping" : "Next") { advance() }
                    .buttonStyle(FilledButtonStyle())
                    .disabled(!canAdvance)
            }
            .padding(.horizontal, Grid.x4)
            .padding(.top, Grid.x3)
            .padding(.bottom, Grid.x2)
        }
        .background(Palette.panel)
        .animation(.snappy(duration: 0.2), value: billFocused)
    }

    // MARK: - Page

    @ViewBuilder
    private var pageContent: some View {
        if let eyebrow = page.eyebrow {
            Text(eyebrow).sectionLabelStyle()
        }

        if let symbol = page.symbol, page.practice == nil {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Palette.accentText)
        }

        Text(page.title)
            .font(.screenTitle)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)

        Text(page.body)
            .font(.bodyText)
            .foregroundStyle(Palette.inkDim)
            .fixedSize(horizontal: false, vertical: true)

        if !page.points.isEmpty {
            Panel(spacing: 0) {
                ForEach(Array(page.points.enumerated()), id: \.element.id) { position, point in
                    if position > 0 {
                        HairRule().padding(.vertical, Grid.x3)
                    }
                    pointRow(point)
                }
            }
        }

        if let permission = page.permission {
            TutorialPermissionPanel(step: permission)
        }

        if let stage = page.practice {
            TutorialPracticeView(session: session, stage: stage, billFocus: $billFocused)
        }

        if let footnote = page.footnote {
            Text(footnote)
                .font(.noteText)
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pointRow(_ point: TutorialPoint) -> some View {
        HStack(alignment: .top, spacing: Grid.x3) {
            Image(systemName: point.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.accentText)
                .frame(width: 22, alignment: .leading)
            Text(point.text)
                .font(.bodyText)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func goalRow(_ goal: PracticeGoal) -> some View {
        let met = goal.isMet(in: session)
        return HStack(spacing: Grid.x3) {
            MarkerBox(isOn: met)
            Text(goal.label)
                .font(.bodyText)
                .foregroundStyle(met ? Palette.inkDim : Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Grid.x4)
        .padding(.vertical, Grid.x3)
        .animation(.snappy(duration: 0.2), value: met)
    }

    // MARK: - Actions

    private func advance() {
        if isLast {
            close()
        } else {
            step(1)
        }
    }

    private func step(_ delta: Int) {
        billFocused = false
        withAnimation(.snappy(duration: 0.25)) {
            index = min(max(index + delta, 0), pages.count - 1)
        }
    }

    /// Finished or skipped — either way the user has been offered the tutorial
    /// and shouldn't be interrupted by it again.
    private func close() {
        billFocused = false
        TutorialState.shared.markSeen()
        TutorialState.shared.isPresented = false
        dismiss()
    }
}

#Preview {
    TutorialView()
        .environment(LocationManager())
        .environment(ArrivalReminders.shared)
}
