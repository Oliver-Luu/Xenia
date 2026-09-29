//
//  CurrencyPickerView.swift
//  Xenia
//
//  Pick the currency amounts show in. Left automatic it follows where you are —
//  landing somewhere new offers to switch, once per country. Picking a currency
//  here is a standing instruction instead: it sticks, and travel stops asking.
//

import SwiftUI

struct CurrencyPickerView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""

    /// What "Automatic" resolves to right now — the travel currency if the user
    /// accepted one, otherwise their home region's.
    private var automaticCode: String {
        preferences.travelCurrencyCode ?? Locale.current.currency?.identifier ?? "USD"
    }

    private var automaticNote: String {
        preferences.travelCurrencyCode == nil
            ? String(localized: "Your region")
            : String(localized: "Where you are")
    }

    private var codes: [String] {
        let all = Locale.commonISOCurrencyCodes
        guard !search.isEmpty else { return all }
        let needle = search.lowercased()
        return all.filter { code in
            code.lowercased().contains(needle)
                || (Locale.current.localizedString(forCurrencyCode: code)?.lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        InstrumentList("Currency", headerTopPadding: Grid.x5) {
            HeaderButton(title: "Done", symbol: "checkmark") { dismiss() }
        } content: {
            FieldWell(placeholder: "Search currencies", text: $search, icon: "magnifyingglass", showsClear: true)
                .plainListRow()
                .padding(.bottom, Grid.x3)

            PanelRow(isFirst: true, isLast: search.isEmpty ? false : codes.isEmpty) {
                SelectRow(
                    isSelected: preferences.currencyCode == nil,
                    showsChevron: false,
                    swipeSafe: true,
                    action: { preferences.currencyCode = nil; dismiss() }
                ) {
                    VStack(alignment: .leading, spacing: Grid.x1) {
                        Text("Automatic").font(.bodyText).foregroundStyle(Palette.ink)
                        Text("\(automaticCode) · \(Format.currencySymbol(for: automaticCode)) · \(automaticNote)")
                            .font(.figureSmall).foregroundStyle(Palette.inkFaint)
                    }
                }
            }

            ForEach(Array(codes.enumerated()), id: \.element) { index, code in
                PanelRow(isFirst: false, isLast: index == codes.count - 1) {
                    SelectRow(
                        isSelected: preferences.currencyCode == code,
                        showsChevron: false,
                        swipeSafe: true,
                        action: { preferences.currencyCode = code; dismiss() }
                    ) {
                        HStack(spacing: Grid.x3) {
                            Text(code)
                                .font(.figure).monospacedDigit()
                                .foregroundStyle(Palette.ink)
                                .frame(width: 52, alignment: .leading)
                            Text(Format.currencySymbol(for: code))
                                .font(.figureSmall).foregroundStyle(Palette.inkDim)
                                .frame(width: 34, alignment: .leading)
                            Text(Locale.current.localizedString(forCurrencyCode: code) ?? code)
                                .font(.bodyText).foregroundStyle(Palette.inkDim)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    CurrencyPickerView()
        .environment(Preferences.shared)
}
