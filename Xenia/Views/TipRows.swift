//
//  TipRows.swift
//  Xenia
//
//  The three rows the tip screen is built from — a scored rating, an adjustment,
//  and the rounding choice. Shared by `CalculatorView` and the tutorial's
//  practice copy so the two can't drift: the practice is only worth anything if
//  it behaves exactly like the real thing.
//
//  They take plain values rather than models, because the practice runs on
//  throwaway structs while the calculator runs on SwiftData objects.
//

import SwiftUI

/// The section labels and notes the tip screen is captioned with. The tutorial's
/// practice calculator shows the same two panels, and had its own copies of these
/// strings — reword one and the walkthrough quietly stops matching the app it is
/// teaching. Same reasoning as the rows below: one definition, both callers.
enum TipCopy {
    static let ratingsLabel = String(localized: "How was it")
    static let ratingsNote = String(localized: "A score at the neutral mark does nothing. Above lifts the tip, below trims it.")
    static let adjustmentsLabel = String(localized: "Adjustments")
}

/// One thing you score at tip time: its name, what that score is contributing
/// right now, and the track to change it.
struct RatingRow: View {
    let name: String
    let score: Int
    let maxScore: Int
    /// Percentage points this score is adding (or trimming, when negative).
    let delta: Double
    /// `delta` already formatted in whatever unit the caller works in.
    let deltaLabel: String
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.x2) {
            HStack {
                Text(name)
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if delta != 0 {
                    Text(deltaLabel)
                        .font(.figureSmall)
                        .foregroundStyle(delta < 0 ? Palette.negative : Palette.inkDim)
                }
            }
            RatingTrack(value: score, maxScore: maxScore, onChange: onChange)
        }
        .padding(.vertical, Grid.x1)
    }
}

/// One adjustment: a toggle, or a stepper that counts up. Its effect shows at
/// all times — the live contribution once engaged, and a faint preview of what
/// engaging it would add while idle — so the user can tell what a rule is worth
/// before touching it.
struct AdjustmentRow: View {
    let title: String
    let detail: String
    let deltaPercent: Double
    let isStepper: Bool
    let maxSteps: Int
    let steps: Int
    /// Formats a percentage-point figure in the caller's unit (points, or the
    /// cash that comes to on the current bill).
    let format: @MainActor (Double) -> String
    let onChange: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Grid.x3) {
            if isStepper {
                VStack(alignment: .leading, spacing: Grid.x2) {
                    label
                    PlusMinus(value: steps, range: 0...maxSteps, onChange: onChange)
                        .frame(width: 160)
                }
            } else {
                MarkerBox(isOn: steps > 0)
                label
            }
        }
        .padding(.vertical, Grid.x2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isStepper else { return }
            onChange(steps > 0 ? 0 : 1)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if deltaPercent != 0 {
                    if steps > 0 {
                        Text(format(deltaPercent * Double(steps)))
                            .font(.figureSmall)
                            .foregroundStyle(deltaPercent < 0 ? Palette.negative : Palette.inkDim)
                    } else {
                        Text(isStepper ? "\(format(deltaPercent)) each" : format(deltaPercent))
                            .font(.figureSmall)
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.noteText)
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The rounding choice that closes out the readout panel.
struct RoundingRows: View {
    @Binding var selection: RoundingMode

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.x2) {
            row("Don't round", .none)
            row("Round the tip to a whole \(Format.currencySymbol())", .tip)
            row("Round the total to a whole \(Format.currencySymbol())", .total)
        }
    }

    private func row(_ label: LocalizedStringKey, _ mode: RoundingMode) -> some View {
        Button { selection = mode } label: {
            HStack(spacing: Grid.x3) {
                MarkerBox(isOn: selection == mode)
                Text(label)
                    .font(.bodyText)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, Grid.x1)
        }
        .buttonStyle(.plain)
    }
}
