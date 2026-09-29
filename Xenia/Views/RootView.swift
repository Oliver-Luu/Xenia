//
//  RootView.swift
//  Xenia
//
//  Seeds default data on first launch. A native TabView handles state and sheet
//  plumbing; its own bar is hidden and replaced with the custom Instrument bar.
//

import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable, Identifiable {
    case calculate, places, rules, history, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .calculate: return String(localized: "Tip")
        case .places: return String(localized: "Places")
        case .rules: return String(localized: "Rules")
        case .history: return String(localized: "History")
        case .settings: return String(localized: "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .calculate: return "percent"
        case .places: return "mappin"
        case .rules: return "dial.medium"
        case .history: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var restaurants: [Restaurant]
    @State private var locationManager = LocationManager()
    @State private var tabPing = TabBarPing()
    @State private var arrivalReminders = ArrivalReminders.shared
    @State private var preferences = Preferences.shared
    @State private var tutorial = TutorialState.shared
    @State private var travelCurrency = TravelCurrency.shared
    @State private var tab: AppTab = .calculate

    var body: some View {
        TabView(selection: $tab) {
            CalculatorView()
                .tag(AppTab.calculate)
                .toolbar(.hidden, for: .tabBar)
            RestaurantListView()
                .tag(AppTab.places)
                .toolbar(.hidden, for: .tabBar)
            CategoryListView()
                .tag(AppTab.rules)
                .toolbar(.hidden, for: .tabBar)
            HistoryListView()
                .tag(AppTab.history)
                .toolbar(.hidden, for: .tabBar)
            SettingsView()
                .tag(AppTab.settings)
                .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InstrumentTabBar(selection: $tab, ping: tabPing)
        }
        // Keep the whole tab shell (and its bottom bar) put when a keyboard
        // opens — otherwise the custom bar rides up and floats mid-screen.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // The cover is attached BEFORE the .environment calls on purpose, so they
        // wrap it and its content inherits them. The other way round the tutorial
        // sits outside that scope and trapped @Environment lookups crash it.
        .fullScreenCover(isPresented: $tutorial.isPresented) {
            TutorialView()
        }
        .environment(locationManager)
        .environment(tabPing)
        .environment(arrivalReminders)
        .environment(preferences)
        .environment(tutorial)
        .instrumentChrome()
        .task {
            SeedData.installIfNeeded(in: modelContext)
            DeletionArchive.purgeExpired(in: modelContext)
            // Seed first: the walkthrough talks about the starter categories.
            tutorial.presentIfUnseen()
            arrivalReminders.start()
            // Hold the location prompt until the walkthrough is done — it lands on
            // top of the first page otherwise, before the user has been told what
            // Xenia wants it for.
            guard !tutorial.isPresented else { return }
            await requestLocationFix()
        }
        .onChange(of: tutorial.isPresented) { _, showing in
            guard !showing else { return }
            Task { await requestLocationFix() }
        }
        .onChange(of: restaurants.count) { _, _ in
            arrivalReminders.start()
        }
        // Currency follows where the user is. The lookup needs the network, so it
        // rides on new fixes rather than blocking anything, and only asks again
        // once they've actually moved (see TravelCurrency.recheckDistance).
        .onChange(of: locationManager.currentLocation) { _, location in
            guard let location, !tutorial.isPresented else { return }
            Task { await travelCurrency.check(location) }
        }
        .alert(
            travelCurrencyPromptTitle,
            isPresented: Binding(
                get: { travelCurrency.pendingPrompt != nil },
                set: { if !$0 { travelCurrency.declinePending() } }
            ),
            presenting: travelCurrency.pendingPrompt
        ) { prompt in
            Button("Switch to \(prompt.currency)") { travelCurrency.acceptPending() }
            Button("Not now", role: .cancel) { travelCurrency.declinePending() }
        } message: { prompt in
            Text("""
            Amounts will show in \(Format.currencySymbol(for: prompt.currency)) \
            while you're here. You can change this any time in Settings.
            """)
        }
        .onReceive(NotificationCenter.default.publisher(for: .arrivalReminderOpened)) { _ in
            tab = .calculate
        }
    }

    private var travelCurrencyPromptTitle: String {
        guard let prompt = travelCurrency.pendingPrompt else { return "" }
        return String(localized: "Looks like you're in \(TravelCurrency.regionName(prompt.region))")
    }

    /// The one place that asks the location manager to move. Mutating it during a
    /// view's first render silently breaks `.sheet` presentation on that view, so
    /// it happens here, off the render pass, after a short beat.
    private func requestLocationFix() async {
        try? await Task.sleep(for: .milliseconds(150))
        locationManager.refresh()
    }
}

struct InstrumentTabBar: View {
    @Binding var selection: AppTab
    var ping: TabBarPing

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let lit = ping.isLit(tab)
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: Grid.x1) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 17, weight: .medium))
                            .frame(height: 22)
                            .overlay(alignment: .topTrailing) {
                                Circle()
                                    .fill(Palette.accent)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 7, y: -3)
                                    .scaleEffect(lit ? 1 : 0.1)
                                    .opacity(lit ? 1 : 0)
                            }
                        Text(tab.label.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                    }
                    .foregroundStyle(
                        lit
                            ? Palette.accentText
                            : (selection == tab ? Palette.ink : Palette.inkFaint)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, Grid.x3)
                    .contentShape(Rectangle())
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Palette.accent)
                            .frame(height: 2)
                            .opacity(selection == tab ? 1 : 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, Grid.x1)
        .background(alignment: .top) { HairRule() }
        .background(Palette.panel.ignoresSafeArea(edges: .bottom))
        .animation(.snappy(duration: 0.28), value: ping.pinged)
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}
