//
//  SettingsView.swift
//  Xenia
//
//  Arrival-reminder controls and the destructive "start over" actions.
//

import SwiftUI
import SwiftData
import CoreLocation
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ArrivalReminders.self) private var reminders
    @Environment(Preferences.self) private var preferences
    @Environment(TutorialState.self) private var tutorial
    @Query(sort: \TipCategory.sortOrder) private var categories: [TipCategory]
    @Query private var deletedItems: [DeletedItem]

    @State private var remindersOn = ArrivalReminders.shared.isEnabled
    @State private var triggerMeters = ArrivalReminders.shared.triggerRadiusMeters
    @State private var radiusApply: Task<Void, Never>?
    @State private var pendingReset: ResetKind?
    @State private var showCurrencyPicker = false
    @State private var showRecentlyDeleted = false

    private enum ResetKind: String, Identifiable {
        case history, places, timing, categories, all
        var id: String { rawValue }

        var title: String {
            switch self {
            case .places: return String(localized: "Reset saved places?")
            case .categories: return String(localized: "Reset categories & rules?")
            case .history: return String(localized: "Reset tip history?")
            case .timing: return String(localized: "Reset reminder times?")
            case .all: return String(localized: "Reset everything?")
            }
        }
        var message: String {
            switch self {
            case .places: return String(localized: "Every saved place and place group is removed. Your history stays.")
            case .categories:
                return String(localized: "Every category, rule, and rating goes back to Xenia defaults. Saved places lose their category until you set it again.")
            case .history: return String(localized: "Every saved tip is removed. Your places and rules stay.")
            case .timing:
                return String(localized: "Every category's arrival-reminder timing goes back to the Xenia default. Nothing else changes.")
            case .all:
                return String(localized: "Every place, group, saved tip, category, rule, and rating is removed, and Recently Deleted is emptied. Categories go back to the Xenia starter set. Your currency and display settings stay.")
            }
        }
        var confirmLabel: String {
            switch self {
            case .places: return String(localized: "Reset places")
            case .categories: return String(localized: "Reset to defaults")
            case .history: return String(localized: "Reset history")
            case .timing: return String(localized: "Reset times")
            case .all: return String(localized: "Reset everything")
            }
        }
    }

    var body: some View {
        InstrumentScreen("Settings") {
            arrivalSection
            if remindersOn { timingSection }
            tipDisplaySection
            currencySection
            unitsSection
            recentlyDeletedSection
            tutorialSection
            dataSection
        }
        .onAppear {
            remindersOn = reminders.isEnabled
            triggerMeters = snappedTrigger(reminders.triggerRadiusMeters)
        }
        .sheet(isPresented: $showCurrencyPicker) { CurrencyPickerView() }
        .sheet(isPresented: $showRecentlyDeleted) { RecentlyDeletedView() }
        .alert(
            pendingReset?.title ?? String(localized: "Are you sure?"),
            isPresented: Binding(get: { pendingReset != nil }, set: { if !$0 { pendingReset = nil } }),
            presenting: pendingReset
        ) { kind in
            Button(kind.confirmLabel, role: .destructive) { perform(kind); pendingReset = nil }
            Button("Cancel", role: .cancel) { pendingReset = nil }
        } message: { kind in
            Text(kind.message)
        }
    }

    // MARK: - Arrival reminders

    private var arrivalSection: some View {
        FieldGroup(
            label: "Arrival reminders",
            note: "When you settle in at a place you've tipped at before, Xenia can nudge you to work out the tip — sooner at a café, or later at a sit-down meal. Works with the app closed.\n\nXenia relies on your phone's location, which can lead to occasional notification inaccuracies. If you are experiencing false notifications, increase \"Trigger Distance\" or \"Reminder Timing\"."
        ) {
            Panel {
                Button {
                    remindersOn.toggle()
                    reminders.isEnabled = remindersOn
                } label: {
                    HStack(spacing: Grid.x3) {
                        MarkerBox(isOn: remindersOn)
                        Text("Suggest a tip when I arrive")
                            .font(.bodyText).foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if remindersOn {
                    HairRule()
                    HStack(spacing: Grid.x3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trigger distance").font(.bodyText).foregroundStyle(Palette.ink)
                            Text("How close you have to get")
                                .font(.noteText).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer(minLength: Grid.x2)
                        PlusMinusDecimal(
                            value: triggerDisplay,
                            range: triggerRange,
                            step: Format.distanceStep,
                            display: Format.distanceFine(triggerMeters)
                        )
                        .frame(width: 150)
                    }
                    .onChange(of: triggerMeters) { _, meters in
                        reminders.triggerRadiusMeters = meters
                        // Re-monitor once the stepper settles, not on every tick.
                        radiusApply?.cancel()
                        radiusApply = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            if !Task.isCancelled { reminders.start() }
                        }
                    }
                }

                if remindersOn, let issue = permissionIssue {
                    HairRule()
                    VStack(alignment: .leading, spacing: Grid.x2) {
                        Text(issue).font(.noteText).foregroundStyle(Palette.negative)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
            }
        }
    }

    // The stepper works in whole display units (25 m / 50 ft) so the readout lands
    // on round numbers; metres stay the storage unit underneath.

    private var triggerRange: ClosedRange<Double> {
        let step = Format.distanceStep
        let low = (Format.displayDistance(ArrivalReminders.radiusRange.lowerBound) / step).rounded(.up) * step
        let high = (Format.displayDistance(ArrivalReminders.radiusRange.upperBound) / step).rounded(.down) * step
        return low...high
    }

    private var triggerDisplay: Binding<Double> {
        Binding(
            get: { Format.displayDistance(triggerMeters) },
            set: { triggerMeters = Format.metersFromDisplay($0) }
        )
    }

    private func snappedTrigger(_ meters: CLLocationDistance) -> CLLocationDistance {
        let step = Format.distanceStep
        let snapped = (Format.displayDistance(meters) / step).rounded() * step
        let clamped = min(max(snapped, triggerRange.lowerBound), triggerRange.upperBound)
        return Format.metersFromDisplay(clamped)
    }

    // Lives on ArrivalReminders alongside the state it reads, so the tutorial and
    // the tests see the same verdict this screen does.
    private var permissionIssue: String? { reminders.permissionIssue }

    // MARK: - Per-category timing

    private var timingSection: some View {
        FieldGroup(
            label: "Reminder timing",
            note: "Minutes after you arrive before the nudge. Set a category to Off to skip it."
        ) {
            Panel(padding: 0, spacing: 0) {
                if categories.isEmpty {
                    Text("No categories.").font(.noteText).foregroundStyle(Palette.inkFaint)
                        .padding(Grid.x4)
                }
                ForEach(Array(categories.enumerated()), id: \.element.persistentModelID) { index, category in
                    if index > 0 { HairRule() }
                    HStack(spacing: Grid.x3) {
                        Text(category.name).font(.bodyText).foregroundStyle(Palette.ink)
                        Spacer(minLength: Grid.x2)
                        PlusMinus(
                            value: category.arrivalReminderMinutes,
                            range: 0...180,
                            display: category.arrivalReminderMinutes == 0
                                ? "Off"
                                : "\(category.arrivalReminderMinutes) min"
                        ) { newValue in
                            category.arrivalReminderMinutes = newValue
                            try? modelContext.save()
                            reminders.start()
                        }
                        .frame(width: 148)
                    }
                    .padding(.horizontal, Grid.x4)
                    .padding(.vertical, Grid.x2)
                }
            }
        }
    }

    // MARK: - Tip display

    private var tipDisplaySection: some View {
        FieldGroup(
            label: "Tip display defaults",
            note: "Every new bill starts from these. You can still switch per bill on the tip screen."
        ) {
            Panel(spacing: Grid.x4) {
                VStack(alignment: .leading, spacing: Grid.x2) {
                    Text("Enter the tip as").font(.noteText).foregroundStyle(Palette.inkFaint)
                    choiceRow("A percentage", selected: preferences.tipEntryMode == .percent) {
                        preferences.tipEntryMode = .percent
                    }
                    choiceRow("A cash amount", selected: preferences.tipEntryMode == .amount) {
                        preferences.tipEntryMode = .amount
                    }
                }
                HairRule()
                VStack(alignment: .leading, spacing: Grid.x2) {
                    Text("Rounding").font(.noteText).foregroundStyle(Palette.inkFaint)
                    choiceRow("Don't round", selected: preferences.roundingDefault == .none) {
                        preferences.roundingDefault = .none
                    }
                    choiceRow("Round the tip", selected: preferences.roundingDefault == .tip) {
                        preferences.roundingDefault = .tip
                    }
                    choiceRow("Round the total", selected: preferences.roundingDefault == .total) {
                        preferences.roundingDefault = .total
                    }
                }
                HairRule()
                choiceRow("Auto-place the decimal", selected: preferences.autoDecimal) {
                    preferences.autoDecimal.toggle()
                }
            }
        }
    }

    // MARK: - Currency

    private var currencySection: some View {
        FieldGroup(
            label: "Currency",
            note: "Used wherever amounts show. Left automatic it follows where you are — arriving somewhere new offers to switch, once per country. Picking a currency here sticks instead, and travel stops asking.\n\nTips already saved keep the currency they were paid in."
        ) {
            Panel {
                Button { showCurrencyPicker = true } label: {
                    HStack(spacing: Grid.x3) {
                        Text(currencyLabel).font(.bodyText).foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var currencyLabel: String {
        let code = Format.currencyCode
        let base = "\(code) · \(Format.currencySymbol(for: code))"
        guard preferences.currencyCode == nil else { return base }
        // Say *why* this is the currency — "region default" would be a lie while
        // a travel currency is in effect.
        return preferences.travelCurrencyCode == nil
            ? String(localized: "\(base)  (your region)")
            : String(localized: "\(base)  (where you are)")
    }

    // MARK: - Units

    private var unitsSection: some View {
        FieldGroup(
            label: "Distance units",
            note: "Automatic follows your device's region and doesn't change when you travel."
        ) {
            Panel(spacing: Grid.x2) {
                choiceRow("Automatic", selected: preferences.distanceUnits == .auto) {
                    preferences.distanceUnits = .auto
                }
                choiceRow("Metric (m, km)", selected: preferences.distanceUnits == .metric) {
                    preferences.distanceUnits = .metric
                }
                choiceRow("Imperial (ft, mi)", selected: preferences.distanceUnits == .imperial) {
                    preferences.distanceUnits = .imperial
                }
            }
        }
    }

    // MARK: - Recently deleted

    private var recentlyDeletedSection: some View {
        FieldGroup(
            label: "Recently deleted",
            note: "Restore something you removed by mistake. Cleared automatically after 30 days."
        ) {
            Panel {
                Button { showRecentlyDeleted = true } label: {
                    HStack(spacing: Grid.x3) {
                        Text("Open recently deleted").font(.bodyText).foregroundStyle(Palette.ink)
                        Spacer()
                        if !deletedItems.isEmpty {
                            Text("\(deletedItems.count)").font(.figureSmall).foregroundStyle(Palette.inkFaint)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Tutorial

    private var tutorialSection: some View {
        FieldGroup(
            label: "Tutorial",
            note: "A short walk through the app with a practice tip you can play with. Nothing in it touches your places, rules or history."
        ) {
            Panel {
                Button("Replay the tutorial") { tutorial.replay() }
                    .buttonStyle(GhostButtonStyle())
            }
        }
    }

    private func choiceRow(_ label: LocalizedStringKey, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Grid.x3) {
                MarkerBox(isOn: selected)
                Text(label).font(.bodyText).foregroundStyle(Palette.ink)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private var dataSection: some View {
        FieldGroup(label: "Start over", note: "These can't be undone.") {
            Panel {
                Button("Reset saved places") { pendingReset = .places }
                    .buttonStyle(DangerButtonStyle())
                Button("Reset categories & rules") { pendingReset = .categories }
                    .buttonStyle(DangerButtonStyle())
                Button("Reset tip history") { pendingReset = .history }
                    .buttonStyle(DangerButtonStyle())
                Button("Reset reminder times") { pendingReset = .timing }
                    .buttonStyle(DangerButtonStyle())
                HairRule()
                Button("Reset everything") { pendingReset = .all }
                    .buttonStyle(DangerButtonStyle())
            }
        }
    }

    private func perform(_ kind: ResetKind) {
        switch kind {
        case .history: DataReset.clearHistory(in: modelContext)
        case .places:
            DataReset.clearPlaces(in: modelContext)
            reminders.start()
        case .timing:
            DataReset.resetReminderTiming(in: modelContext)
            reminders.start()
        case .categories: DataReset.resetCategories(in: modelContext)
        case .all:
            DataReset.resetEverything(in: modelContext)
            reminders.start()
        }
    }
}

#Preview {
    SettingsView()
        .environment(ArrivalReminders.shared)
        .environment(Preferences.shared)
        .environment(TutorialState.shared)
        .modelContainer(PreviewData.container)
}
