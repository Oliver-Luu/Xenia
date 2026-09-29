//
//  RowRemover.swift
//  Xenia
//
//  Row removal for the list screens, driven by the view instead of a `@Query`
//  round-trip (which teleported the rows below up into place).
//
//  Two vertical red bars sit on the row's left and right edges, then slide inward
//  like closing doors until they meet as one centred red line; the line fades;
//  then the row leaves the list inside `withAnimation`, so the rows below slide
//  up to close the gap. The model is archived last.
//

import SwiftUI
import SwiftData

enum RemovalPhase: Equatable {
    case present   // normal
    case armed     // red bars snapped onto the left and right edges
    case closing   // bars sliding to the centre; row content fading under them
    case fading    // the merged centre line fading out
    case gone      // dropped from the list source (rows below slide up)
}

@MainActor
@Observable
final class RowRemover {

    private var phases: [PersistentIdentifier: RemovalPhase] = [:]

    func phase(_ id: PersistentIdentifier) -> RemovalPhase { phases[id] ?? .present }

    /// Only true at the very end — filtering the row out any earlier cancels the
    /// blink and makes the rows below jump.
    func isGone(_ id: PersistentIdentifier) -> Bool { phase(id) == .gone }

    /// Blink timing. Deliberately unhurried — the closing "doors" are the moment
    /// the user reads as "this row is being deleted", so give them room.
    private enum Timing {
        static let armedHold: Double = 0.10
        static let closing: Double = 0.42
        static let fading: Double = 0.30
        static let gone: Double = 0.34
        static let slideBackIn: Double = 0.30
    }

    /// Runs the blink, then `archive`. `archive` returns whether it actually
    /// persisted — on `false` (a rare save failure) the row slides back in
    /// instead of vanishing for good.
    func remove(_ id: PersistentIdentifier, archive: @escaping () -> Bool) {
        guard phase(id) == .present else { return }
        phases[id] = .armed
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Timing.armedHold))
            withAnimation(.easeInOut(duration: Timing.closing)) { phases[id] = .closing }
            try? await Task.sleep(for: .seconds(Timing.closing))
            withAnimation(.easeOut(duration: Timing.fading)) { phases[id] = .fading }
            try? await Task.sleep(for: .seconds(Timing.fading))
            withAnimation(.easeInOut(duration: Timing.gone)) { phases[id] = .gone }
            // Stays .gone on success (prune() clears the entry once @Query catches
            // up); slides back in if the archive couldn't be saved.
            if !archive() {
                withAnimation(.easeInOut(duration: Timing.slideBackIn)) { phases[id] = .present }
            }
        }
    }

    /// Forget ids the store no longer has so the map doesn't grow.
    func prune(against live: some Sequence<PersistentIdentifier>) {
        let alive = Set(live)
        phases = phases.filter { alive.contains($0.key) }
    }
}

extension View {
    func blinkCollapse(_ phase: RemovalPhase) -> some View {
        modifier(BlinkCollapse(phase: phase))
    }
}

private struct BlinkCollapse: ViewModifier {
    let phase: RemovalPhase

    private static let barWidth: CGFloat = 3.5

    private var closedIn: Bool { phase == .closing || phase == .fading || phase == .gone }
    private var barsLit: Bool { phase == .armed || phase == .closing }
    private var contentHidden: Bool { phase != .present && phase != .armed }

    func body(content: Content) -> some View {
        content
            .opacity(contentHidden ? 0 : 1)
            .overlay { curtains }
    }

    private var curtains: some View {
        GeometryReader { geo in
            let travel = closedIn ? max(0, geo.size.width / 2 - Self.barWidth / 2) : 0
            ZStack {
                bar
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: travel)
                bar
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(x: -travel)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(barsLit ? 1 : 0)
        }
        .allowsHitTesting(false)
    }

    private var bar: some View {
        Rectangle()
            .fill(Palette.destructive)
            .frame(width: Self.barWidth)
    }
}
