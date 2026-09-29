//
//  PlacePickerView.swift
//  Xenia
//
//  Choose where you are: a saved place, a nearby MapKit result (not saved until
//  you tap "Save to Places" on the tip screen), or a bare category.
//

import SwiftUI
import SwiftData
import CoreLocation

/// A nearby place picked from search that hasn't been added to Places yet.
struct DraftPlace {
    var name: String
    var streetAddress: String
    var coordinate: CLLocationCoordinate2D?
    var category: TipCategory
}

enum PlaceSelection {
    case restaurant(Restaurant)
    /// A bare category. `typedName` carries whatever the user had typed into the
    /// search field, so the calculator can pre-fill the place name instead of
    /// asking them to type it a second time.
    case category(TipCategory, typedName: String?)
    case newPlace(DraftPlace)
}

struct PlacePickerView: View {
    let categories: [TipCategory]
    let savedRestaurants: [Restaurant]
    let onPick: (PlaceSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LocationManager.self) private var locationManager

    @State private var searchService = PlaceSearchService()
    @State private var query = ""
    @State private var pendingPlace: NearbyPlace?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: Grid.x6) {
                        FieldWell(
                            placeholder: "Search by name",
                            text: $query,
                            focus: $searchFocused
                        )

                        if !filteredSaved.isEmpty {
                            section("Saved") {
                                rows(filteredSaved) { restaurant in
                                    savedRow(restaurant)
                                } action: {
                                    choose(.restaurant($0))
                                }
                            }
                        }

                        section(query.isEmpty ? "Nearby" : "Results") {
                            nearbyContent
                        }

                        section("Or a category") {
                            Panel(padding: 0, spacing: 0) {
                                ForEach(Array(categories.enumerated()), id: \.element.persistentModelID) { index, category in
                                    if index > 0 { HairRule() }
                                    SelectRow(action: { choose(.category(category, typedName: trimmedQuery)) }) {
                                        Text(category.name)
                                            .font(.bodyText)
                                            .foregroundStyle(Palette.ink)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Grid.x4)
                    .padding(.vertical, Grid.x5)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Palette.ground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
        .task { await loadNearby() }
        .sheet(item: $pendingPlace) { place in
            AssignCategorySheet(place: place, categories: categories) { category in
                pendingPlace = nil
                choose(.newPlace(DraftPlace(
                    name: place.name,
                    streetAddress: place.address,
                    coordinate: place.coordinate,
                    category: category
                )))
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Choose a place")
                .font(.cardTitle)
                .foregroundStyle(Palette.ink)
            Spacer()
            Button("Cancel") { dismiss() }
                .font(.bodyText)
                .foregroundStyle(Palette.inkDim)
        }
        .padding(.horizontal, Grid.x4)
        .padding(.top, Grid.x6)
        .padding(.bottom, Grid.x3)
        .background(alignment: .bottom) { HairRule() }
    }

    @ViewBuilder
    private func section<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Grid.x2) {
            Text(label).sectionLabelStyle()
            content()
        }
    }

    @ViewBuilder
    private func rows<T: Identifiable, Row: View>(
        _ items: [T],
        @ViewBuilder row: @escaping (T) -> Row,
        action: @escaping (T) -> Void
    ) -> some View {
        Panel(padding: 0, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { HairRule() }
                SelectRow(action: { action(item) }) { row(item) }
            }
        }
    }

    @ViewBuilder
    private var nearbyContent: some View {
        switch searchService.loadState {
        case .loading:
            HStack(spacing: Grid.x2) {
                ProgressView().tint(Palette.inkDim)
                Text("Searching").font(.noteText).foregroundStyle(Palette.inkDim)
            }
            .padding(.vertical, Grid.x2)
        case .failed(let message):
            Text(message).font(.noteText).foregroundStyle(Palette.inkFaint)
        case .idle where !locationManager.isAuthorized && query.isEmpty:
            Text("Turn on location, or search by name.")
                .font(.noteText).foregroundStyle(Palette.inkFaint)
        default:
            if newNearbyResults.isEmpty {
                Text(query.isEmpty ? "Nothing found nearby." : "No matches.")
                    .font(.noteText).foregroundStyle(Palette.inkFaint)
            } else {
                Panel(padding: 0, spacing: 0) {
                    ForEach(Array(newNearbyResults.enumerated()), id: \.element.id) { index, place in
                        if index > 0 { HairRule() }
                        SelectRow(showsChevron: true, action: { pendingPlace = place }) {
                            nearbyRow(place)
                        }
                    }
                }
            }
        }
    }

    private func savedRow(_ restaurant: Restaurant) -> some View {
        VStack(alignment: .leading, spacing: Grid.x1) {
            Text(restaurant.name).font(.bodyText).foregroundStyle(Palette.ink)
            HStack(spacing: Grid.x2) {
                CategoryTag(name: restaurant.category?.name)
                if let distance = distance(to: restaurant.coordinate) {
                    Text(Format.distance(distance))
                        .font(.figureSmall).foregroundStyle(Palette.inkFaint)
                }
            }
        }
    }

    private func nearbyRow(_ place: NearbyPlace) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(place.name).font(.bodyText).foregroundStyle(Palette.ink)
            HStack(spacing: Grid.x2) {
                if !place.address.isEmpty {
                    Text(place.address).font(.noteText).foregroundStyle(Palette.inkFaint)
                }
                if let distance = place.distance {
                    Text(Format.distance(distance)).font(.figureSmall).foregroundStyle(Palette.inkFaint)
                }
            }
        }
    }

    // MARK: - Data

    private var filteredSaved: [Restaurant] {
        let sorted = savedRestaurants.sorted { lhs, rhs in
            switch (distance(to: lhs.coordinate), distance(to: rhs.coordinate)) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.name < rhs.name
            }
        }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Nearby results minus the ones already in Places. A name match alone isn't
    /// enough — chains repeat, so a saved "Joe's Coffee" at home would otherwise
    /// hide the branch you're standing in. It has to be the same name in the same
    /// spot (or a saved place with no point at all, which can't be told apart).
    private var newNearbyResults: [NearbyPlace] {
        searchService.results.filter { place in
            !savedRestaurants.contains { saved in
                guard saved.name.localizedCaseInsensitiveCompare(place.name) == .orderedSame
                else { return false }
                guard let savedCoordinate = saved.coordinate else { return true }
                let here = CLLocation(latitude: place.coordinate.latitude,
                                      longitude: place.coordinate.longitude)
                let there = CLLocation(latitude: savedCoordinate.latitude,
                                       longitude: savedCoordinate.longitude)
                return here.distance(from: there) <= Self.samePlaceThreshold
            }
        }
    }

    /// How close two same-named places have to be to count as one place.
    private static let samePlaceThreshold: CLLocationDistance = 150

    private func distance(to coordinate: CLLocationCoordinate2D?) -> CLLocationDistance? {
        guard let coordinate, let location = locationManager.currentLocation else { return nil }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: location)
    }

    /// The search text, trimmed — `nil` when empty.
    private var trimmedQuery: String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func choose(_ selection: PlaceSelection) {
        onPick(selection)
        dismiss()
    }

    private func loadNearby() async {
        guard let location = locationManager.currentLocation else { return }
        await searchService.loadNearby(around: location.coordinate, userLocation: location)
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            if trimmed.isEmpty {
                await loadNearby()
            } else {
                await searchService.search(
                    trimmed,
                    near: locationManager.currentLocation?.coordinate,
                    userLocation: locationManager.currentLocation
                )
            }
        }
    }
}

private struct AssignCategorySheet: View {
    let place: NearbyPlace
    let categories: [TipCategory]
    let onConfirm: (TipCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: TipCategory?

    var body: some View {
        SheetScaffold(
            title: "New place",
            confirmTitle: "Continue",
            confirmEnabled: selection != nil,
            onCancel: { dismiss() },
            onConfirm: { if let selection { onConfirm(selection) } }
        ) {
            FieldGroup(label: "Saving") {
                Panel {
                    Text(place.name).font(.cardTitle).foregroundStyle(Palette.ink)
                    if !place.address.isEmpty {
                        Text(place.address).font(.noteText).foregroundStyle(Palette.inkDim)
                    }
                }
            }
            FieldGroup(label: "Tipping category") {
                Panel(padding: 0, spacing: 0) {
                    ForEach(Array(categories.enumerated()), id: \.element.persistentModelID) { index, category in
                        if index > 0 { HairRule() }
                        SelectRow(
                            isSelected: selection?.persistentModelID == category.persistentModelID,
                            showsChevron: false,
                            action: { selection = category }
                        ) {
                            Text(category.name).font(.bodyText).foregroundStyle(Palette.ink)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    PlacePickerView(categories: [], savedRestaurants: [], onPick: { _ in })
        .environment(LocationManager())
        .modelContainer(PreviewData.container)
}
