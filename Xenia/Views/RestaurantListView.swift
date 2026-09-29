//
//  RestaurantListView.swift
//  Xenia
//
//  Saved places: search, favorites and most-visited pinned to the top, the rest
//  grouped by user-made group (falling back to tip category).
//

import SwiftUI
import SwiftData
import CoreLocation

struct RestaurantListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Restaurant.name) private var restaurants: [Restaurant]
    @Query(sort: \TipCategory.sortOrder) private var categories: [TipCategory]
    @Query(sort: \PlaceGroup.sortOrder) private var placeGroups: [PlaceGroup]

    @State private var editing: Restaurant?
    @State private var creatingNew = false
    @State private var pendingDelete: Restaurant?
    @State private var searchText = ""
    @State private var renamingGroup: PlaceGroup?
    @State private var groupNameDraft = ""
    @State private var pendingGroupDelete: PlaceGroup?
    @State private var remover = RowRemover()

    var body: some View {
        InstrumentList("Places") {
            if !categories.isEmpty {
                HeaderButton(title: "Add") { creatingNew = true }
            }
        } content: {
            if hasVisiblePlaces {
                FieldWell(placeholder: "Search places", text: $searchText, icon: "magnifyingglass", showsClear: true)
                    .plainListRow()
                    .padding(.bottom, Grid.x4)
            }

            if !hasVisiblePlaces {
                BlankSlate(
                    headline: "No saved places",
                    message: "Add places you visit often, or save them from the tip screen when you get there.",
                    symbol: "mappin.slash"
                )
                .plainListRow()
            } else if sections.isEmpty {
                Text("Nothing matches \u{201C}\(searchText)\u{201D}.")
                    .font(.noteText).foregroundStyle(Palette.inkFaint)
                    .plainListRow()
            } else {
                ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
                    sectionHeader(section, isFirst: sectionIndex == 0)

                    ForEach(Array(section.places.enumerated()), id: \.element.id) { index, place in
                        PanelRow(isFirst: index == 0, isLast: index == section.places.count - 1) {
                            SelectRow(swipeSafe: true, action: { editing = place }) {
                                row(place)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                toggleFavorite(place)
                            } label: {
                                Label(place.isFavorite ? "Unpin" : "Pin",
                                      systemImage: place.isFavorite ? "star.slash" : "star")
                            }
                            .tint(Palette.accentText)
                        }
                        .blinkCollapse(remover.phase(place.persistentModelID))
                        .deleteSwipeAction { remove(place) }
                        .contextMenu {
                            Button(place.isFavorite ? "Remove from Quick access" : "Add to Quick access",
                                   systemImage: place.isFavorite ? "star.slash" : "star") {
                                toggleFavorite(place)
                            }
                            Button("Delete", role: .destructive) { pendingDelete = place }
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { restaurant in
            RestaurantEditView(restaurant: restaurant, categories: categories)
        }
        .sheet(isPresented: $creatingNew) {
            RestaurantEditView(restaurant: nil, categories: categories)
        }
        .alert(
            pendingDelete.map { "Delete \($0.name)?" } ?? "Delete this place?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { restaurant in
            Button("Delete", role: .destructive) { remove(restaurant); pendingDelete = nil }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This removes the place and its overrides. Your history stays.")
        }
        .alert(
            "Rename group",
            isPresented: Binding(get: { renamingGroup != nil }, set: { if !$0 { renamingGroup = nil } })
        ) {
            TextField("Name", text: $groupNameDraft)
            Button("Save") {
                let trimmed = groupNameDraft.trimmingCharacters(in: .whitespaces)
                if let renamingGroup, !trimmed.isEmpty {
                    renamingGroup.name = trimmed
                    try? modelContext.save()
                }
                renamingGroup = nil
            }
            Button("Cancel", role: .cancel) { renamingGroup = nil }
        }
        .alert(
            pendingGroupDelete.map { "Delete the \u{201C}\($0.name)\u{201D} group?" } ?? "Delete this group?",
            isPresented: Binding(get: { pendingGroupDelete != nil }, set: { if !$0 { pendingGroupDelete = nil } }),
            presenting: pendingGroupDelete
        ) { group in
            Button("Delete", role: .destructive) {
                DeletionArchive.archive(group, in: modelContext)
                pendingGroupDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingGroupDelete = nil }
        } message: { _ in
            Text("The places stay — they go back to being grouped by category.")
        }
        .onChange(of: restaurants.count) { _, _ in
            remover.prune(against: restaurants.map(\.persistentModelID))
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func sectionHeader(_ section: PlaceSection, isFirst: Bool) -> some View {
        HStack(spacing: Grid.x2) {
            Text(section.title).sectionLabelStyle()
            if section.isQuickAccess {
                Image(systemName: section.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.accentText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, isFirst ? 0 : Grid.x5)
        .padding(.bottom, Grid.x2)
        .plainListRow()
        .contextMenu {
            if let group = section.group {
                Button("Rename") {
                    groupNameDraft = group.name
                    renamingGroup = group
                }
                Button("Delete group", role: .destructive) { pendingGroupDelete = group }
            }
        }
    }

    private func row(_ restaurant: Restaurant) -> some View {
        VStack(alignment: .leading, spacing: Grid.x1) {
            HStack(spacing: Grid.x2) {
                if restaurant.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent)
                }
                Text(restaurant.name).font(.cardTitle).foregroundStyle(Palette.ink)
                if !restaurant.city.isEmpty {
                    Text(restaurant.city)
                        .font(.figureSmall)
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            HStack(spacing: Grid.x3) {
                CategoryTag(name: restaurant.category?.name)
                Text("Base \(Format.percent(restaurant.effectiveBaseTipPercent))")
                    .font(.figureSmall).foregroundStyle(Palette.inkDim)
                if restaurant.visitCount > 0 {
                    Text("\(restaurant.visitCount) visit\(restaurant.visitCount == 1 ? "" : "s")")
                        .font(.figureSmall).foregroundStyle(Palette.inkFaint)
                }
            }
            if !restaurant.hasCoordinate {
                Text("No GPS point saved")
                    .font(.noteText).foregroundStyle(Palette.inkFaint)
            }
        }
    }

    // MARK: - Grouping

    private struct PlaceSection: Identifiable {
        let id: String
        let title: String
        let places: [Restaurant]
        var isQuickAccess = false
        var symbol = "mappin"
        var group: PlaceGroup?
    }

    private var hasVisiblePlaces: Bool {
        restaurants.contains { !remover.isGone($0.persistentModelID) }
    }

    private var sections: [PlaceSection] {
        let restaurants = self.restaurants.filter { !remover.isGone($0.persistentModelID) }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()

        if !query.isEmpty {
            let hits = restaurants
                .filter {
                    $0.name.lowercased().contains(query)
                        || $0.streetAddress.lowercased().contains(query)
                        || $0.city.lowercased().contains(query)
                        || ($0.category?.name.lowercased().contains(query) ?? false)
                        || ($0.group?.name.lowercased().contains(query) ?? false)
                }
                .sorted { $0.name < $1.name }
            return hits.isEmpty ? [] : [PlaceSection(id: "results", title: "Results", places: hits)]
        }

        var result: [PlaceSection] = []
        var pinned = Set<PersistentIdentifier>()

        let favorites = restaurants.filter(\.isFavorite).sorted { $0.name < $1.name }
        if !favorites.isEmpty {
            result.append(PlaceSection(
                id: "favorites", title: "Quick access", places: favorites,
                isQuickAccess: true, symbol: "star.fill"
            ))
            pinned.formUnion(favorites.map(\.persistentModelID))
        }

        let mostVisited = restaurants
            .filter { $0.visitCount >= 2 && !pinned.contains($0.persistentModelID) }
            .sorted { $0.visitCount > $1.visitCount }
            .prefix(3)
        if !mostVisited.isEmpty {
            result.append(PlaceSection(
                id: "most-visited", title: "Most visited", places: Array(mostVisited),
                isQuickAccess: true, symbol: "clock.fill"
            ))
            pinned.formUnion(mostVisited.map(\.persistentModelID))
        }

        let rest = restaurants.filter { !pinned.contains($0.persistentModelID) }

        for group in placeGroups {
            let members = rest
                .filter { $0.group?.persistentModelID == group.persistentModelID }
                .sorted { $0.name < $1.name }
            if !members.isEmpty {
                result.append(PlaceSection(
                    id: "group-\(group.uuid)", title: group.name, places: members, group: group
                ))
            }
        }

        let ungrouped = rest.filter { $0.group == nil }
        let byCategory = Dictionary(grouping: ungrouped) { $0.category?.name ?? "Other places" }
        for key in byCategory.keys.sorted() {
            result.append(PlaceSection(
                id: "category-\(key)", title: key,
                places: (byCategory[key] ?? []).sorted { $0.name < $1.name }
            ))
        }

        return result
    }

    // MARK: - Mutations

    private func toggleFavorite(_ restaurant: Restaurant) {
        restaurant.isFavorite.toggle()
        try? modelContext.save()
    }

    private func remove(_ restaurant: Restaurant) {
        remover.remove(restaurant.persistentModelID) { delete(restaurant) }
    }

    /// Returns whether the archive actually persisted.
    private func delete(_ restaurant: Restaurant) -> Bool {
        DeletionArchive.archive(restaurant, in: modelContext) != nil
    }
}

struct RestaurantEditView: View {
    let restaurant: Restaurant?
    let categories: [TipCategory]
    var prefillCategory: TipCategory? = nil
    var onSaved: ((Restaurant) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationManager.self) private var locationManager
    @Query(sort: \PlaceGroup.sortOrder) private var placeGroups: [PlaceGroup]

    @State private var name = ""
    @State private var address = ""
    @State private var city = ""
    @State private var categoryID: PersistentIdentifier?
    @State private var groupID: PersistentIdentifier?
    @State private var isFavorite = false
    @State private var useOverride = false
    @State private var overridePercent = 18.0
    @State private var reminderOverride: Bool?
    @State private var note = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var disabledRuleIDs: Set<UUID> = []
    @State private var confirmDelete = false
    @State private var showNewGroup = false
    @State private var newGroupName = ""
    @State private var editingCustomRule: AdjustmentRule?
    @State private var creatingCustomRule = false
    @State private var editingCustomDimension: RatingDimension?
    @State private var creatingCustomDimension = false
    @State private var pendingCustomDelete: CustomDelete?
    /// Flips the instant "Delete this place" is confirmed, so the body stops
    /// reading a model that archive() is about to hard-delete before dismissal.
    @State private var isDeletingPlace = false
    /// Set while "Use my current location" waits on a fix it asked for.
    @State private var awaitingFix = false
    @FocusState private var focused: Bool

    private enum CustomDelete: Identifiable {
        case rule(AdjustmentRule), dimension(RatingDimension)
        var id: String {
            switch self {
            case .rule(let r): return "r-\(r.uuid)"
            case .dimension(let d): return "d-\(d.uuid)"
            }
        }
    }

    private var isNew: Bool { restaurant == nil }
    private var selectedCategory: TipCategory? {
        categories.first { $0.persistentModelID == categoryID }
    }
    private var customDimensions: [RatingDimension] {
        guard !isDeletingPlace, let restaurant else { return [] }
        return restaurant.sortedCustomRatingDimensions
    }
    private var customRules: [AdjustmentRule] {
        guard !isDeletingPlace, let restaurant else { return [] }
        return restaurant.sortedCustomRules
    }
    private var placeDeleteTitle: String {
        guard !isDeletingPlace, let name = restaurant?.name, !name.isEmpty else {
            return String(localized: "Delete this place?")
        }
        return String(localized: "Delete \(name)?")
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && categoryID != nil
    }
    private var baseTipNote: String? {
        guard !useOverride, let category = selectedCategory else { return nil }
        return String(localized: "Uses the category default, \(Format.percent(category.baseTipPercent)).")
    }

    var body: some View {
        SheetScaffold(
            title: isNew ? "New place" : "Edit place",
            confirmEnabled: canSave,
            onCancel: { dismiss() },
            onConfirm: save
        ) {
            FieldGroup(label: "Name") {
                FieldWell(placeholder: "Place name", text: $name, focus: $focused)
            }
            FieldGroup(label: "Address") {
                FieldWell(placeholder: "Optional", text: $address)
            }
            FieldGroup(label: "City") {
                FieldWell(placeholder: "Filled in automatically", text: $city)
            }

            FieldGroup(label: "Quick access") {
                Panel {
                    Button { isFavorite.toggle() } label: {
                        HStack(spacing: Grid.x3) {
                            MarkerBox(isOn: isFavorite)
                            Text("Pin to the top of Places")
                                .font(.bodyText).foregroundStyle(Palette.ink)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            FieldGroup(label: "Category") {
                Panel(padding: 0, spacing: 0) {
                    ForEach(Array(categories.enumerated()), id: \.element.persistentModelID) { index, category in
                        if index > 0 { HairRule() }
                        SelectRow(
                            isSelected: categoryID == category.persistentModelID,
                            showsChevron: false,
                            action: { categoryID = category.persistentModelID }
                        ) {
                            Text(category.name).font(.bodyText).foregroundStyle(Palette.ink)
                        }
                    }
                }
            }

            FieldGroup(label: "Group", note: "Optional. Used to organize the Places list.") {
                Panel(padding: 0, spacing: 0) {
                    SelectRow(isSelected: groupID == nil, showsChevron: false, action: { groupID = nil }) {
                        Text("No group").font(.bodyText).foregroundStyle(Palette.inkDim)
                    }
                    ForEach(placeGroups) { group in
                        HairRule()
                        SelectRow(
                            isSelected: groupID == group.persistentModelID,
                            showsChevron: false,
                            action: { groupID = group.persistentModelID }
                        ) {
                            Text(group.name).font(.bodyText).foregroundStyle(Palette.ink)
                        }
                    }
                    HairRule()
                    AddRow(title: "New group") { newGroupName = ""; showNewGroup = true }
                }
            }

            FieldGroup(label: "Base tip", note: baseTipNote) {
                Panel {
                    Button { useOverride.toggle() } label: {
                        HStack(spacing: Grid.x3) {
                            MarkerBox(isOn: useOverride)
                            Text("Set a different base for this place")
                                .font(.bodyText).foregroundStyle(Palette.ink)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if useOverride {
                        HairRule()
                        HStack {
                            Text("Base").font(.bodyText).foregroundStyle(Palette.inkDim)
                            Spacer()
                            PlusMinusDecimal(
                                value: $overridePercent, range: 0...40, step: 0.5,
                                display: Format.percent(overridePercent)
                            )
                            .frame(width: 150)
                        }
                    }
                }
            }

            FieldGroup(label: "Arrival reminder", note: arrivalReminderNote) {
                Panel(padding: 0, spacing: 0) {
                    reminderOverrideRow("Follow the category", value: nil)
                    HairRule()
                    reminderOverrideRow("Remind me here", value: true)
                    HairRule()
                    reminderOverrideRow("Don't remind me here", value: false)
                }
            }

            if let selectedCategory, !selectedCategory.sortedRules.isEmpty {
                FieldGroup(
                    label: "Category adjustments",
                    note: "Ticked ones are offered when you tip here. Untick any that never apply at this place."
                ) {
                    Panel(padding: 0, spacing: 0) {
                        ForEach(Array(selectedCategory.sortedRules.enumerated()), id: \.element.uuid) { index, rule in
                            if index > 0 { HairRule() }
                            Button {
                                if disabledRuleIDs.contains(rule.uuid) { disabledRuleIDs.remove(rule.uuid) }
                                else { disabledRuleIDs.insert(rule.uuid) }
                            } label: {
                                HStack(spacing: Grid.x3) {
                                    MarkerBox(isOn: !disabledRuleIDs.contains(rule.uuid))
                                    Text(rule.title).font(.bodyText).foregroundStyle(Palette.ink)
                                    Spacer()
                                }
                                .padding(.horizontal, Grid.x4)
                                .padding(.vertical, Grid.x3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let restaurant {
                customRatingsSection(restaurant)
                customRulesSection(restaurant)
            }

            FieldGroup(
                label: "GPS point",
                note: coordinate == nil ? "Without a point, auto-detect can't find this place." : nil
            ) {
                Panel {
                    if let coordinate {
                        LedgerRow(
                            label: "Saved",
                            value: "\(coordinate.latitude.formatted(.number.precision(.fractionLength(4)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(4))))"
                        )
                        HairRule()
                    }
                    // `refresh()` only *asks* — the fix arrives later through the
                    // delegate, so take whatever is already known now and let
                    // onChange below pick up the fresh one when it lands.
                    Button(awaitingFix ? "Finding your location\u{2026}" : "Use my current location") {
                        if let current = locationManager.currentLocation {
                            coordinate = current.coordinate
                        }
                        awaitingFix = true
                        locationManager.refresh()
                    }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(awaitingFix)
                    if coordinate != nil {
                        Button("Clear the point") { coordinate = nil }
                            .font(.figureSmall)
                            .foregroundStyle(Palette.negative)
                    }
                }
            }

            FieldGroup(label: "Notes") {
                Panel {
                    TextField("Anything worth remembering", text: $note, axis: .vertical)
                        .font(.bodyText)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1...4)
                }
            }

            if restaurant != nil {
                Button("Delete this place") { confirmDelete = true }
                    .buttonStyle(DangerButtonStyle())
            }
        }
        .onAppear(perform: populate)
        .onChange(of: locationManager.currentLocation) { _, fix in
            guard awaitingFix, let fix else { return }
            coordinate = fix.coordinate
            awaitingFix = false
        }
        .onChange(of: locationManager.state) { _, state in
            // Denied or failed: stop waiting, or the button stays disabled for good.
            if case .denied = state { awaitingFix = false }
            if case .failed = state { awaitingFix = false }
        }
        .sheet(item: $editingCustomRule) { rule in
            RuleEditView(rule: rule)
        }
        .sheet(isPresented: $creatingCustomRule) {
            if let restaurant { RuleEditView(rule: nil, restaurant: restaurant) }
        }
        .sheet(item: $editingCustomDimension) { dimension in
            RatingEditView(dimension: dimension)
        }
        .sheet(isPresented: $creatingCustomDimension) {
            if let restaurant { RatingEditView(dimension: nil, restaurant: restaurant) }
        }
        .alert(
            customDeleteTitle,
            isPresented: Binding(get: { pendingCustomDelete != nil }, set: { if !$0 { pendingCustomDelete = nil } }),
            presenting: pendingCustomDelete
        ) { pending in
            Button("Delete", role: .destructive) {
                switch pending {
                case .rule(let r): DeletionArchive.archive(r, in: modelContext)
                case .dimension(let d): DeletionArchive.archive(d, in: modelContext)
                }
                pendingCustomDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingCustomDelete = nil }
        }
        .alert("New group", isPresented: $showNewGroup) {
            TextField("Name", text: $newGroupName)
            Button("Create") { createGroup() }
            Button("Cancel", role: .cancel) { newGroupName = "" }
        }
        .alert(
            placeDeleteTitle,
            isPresented: $confirmDelete
        ) {
            Button("Delete", role: .destructive) {
                guard let restaurant else { dismiss(); return }
                isDeletingPlace = true
                DeletionArchive.archive(restaurant, in: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Arrival reminder override

    private func reminderOverrideRow(_ label: LocalizedStringKey, value: Bool?) -> some View {
        SelectRow(
            isSelected: reminderOverride == value,
            showsChevron: false,
            action: { reminderOverride = value }
        ) {
            Text(label).font(.bodyText).foregroundStyle(Palette.ink)
        }
    }

    private var arrivalReminderNote: String {
        let categoryName = selectedCategory?.name ?? String(localized: "the category")
        let categoryMinutes = selectedCategory?.arrivalReminderMinutes ?? 0
        switch reminderOverride {
        case .none:
            return categoryMinutes > 0
                ? String(localized: "Follows \(categoryName) — a nudge about \(categoryMinutes) min after you arrive.")
                : String(localized: "\(categoryName) has arrival reminders off, so this place won't nudge you.")
        case .some(true):
            let minutes = categoryMinutes > 0 ? categoryMinutes : ArrivalDefaults.fallbackMinutes
            return String(localized: "A nudge about \(minutes) min after you arrive here, even if \(categoryName) has reminders off. Needs a GPS point and reminders on in Settings.")
        case .some(false):
            return String(localized: "No arrival nudge here, even if \(categoryName) has reminders on.")
        }
    }

    // MARK: - Custom ratings & rules

    @ViewBuilder
    private func customRatingsSection(_ restaurant: Restaurant) -> some View {
        FieldGroup(
            label: "Ratings only here",
            note: customDimensions.isEmpty
                ? "Add a score you only care about at this place, on top of the category's."
                : "Asked after the category's ratings when you tip here."
        ) {
            Panel(padding: 0, spacing: 0) {
                ForEach(Array(customDimensions.enumerated()), id: \.element.uuid) { index, dimension in
                    if index > 0 { HairRule() }
                    ReorderableRow(
                        index: index,
                        count: customDimensions.count,
                        onEdit: { editingCustomDimension = dimension },
                        onMove: { Reorder.move(dimension, by: $0, in: customDimensions, saving: modelContext) }
                    ) {
                        rowLabel(dimension.name, dimension.summary)
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) { pendingCustomDelete = .dimension(dimension) }
                    }
                }
                if !customDimensions.isEmpty { HairRule() }
                AddRow(title: "Add a rating") { creatingCustomDimension = true }
            }
        }
    }

    @ViewBuilder
    private func customRulesSection(_ restaurant: Restaurant) -> some View {
        FieldGroup(
            label: "Adjustments only here",
            note: customRules.isEmpty
                ? "A toggle or stepper just for this place — a regulars' bump, a corkage fee, anything."
                : "Offered after the category's adjustments when you tip here."
        ) {
            Panel(padding: 0, spacing: 0) {
                ForEach(Array(customRules.enumerated()), id: \.element.uuid) { index, rule in
                    if index > 0 { HairRule() }
                    ReorderableRow(
                        index: index,
                        count: customRules.count,
                        onEdit: { editingCustomRule = rule },
                        onMove: { Reorder.move(rule, by: $0, in: customRules, saving: modelContext) }
                    ) {
                        rowLabel(
                            rule.title,
                            rule.isStepper ? "Stepper, up to \(rule.maxSteps)×" : rule.detail,
                            trailing: Format.signedPercent(rule.deltaPercent),
                            trailingNegative: rule.deltaPercent < 0
                        )
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) { pendingCustomDelete = .rule(rule) }
                    }
                }
                if !customRules.isEmpty { HairRule() }
                AddRow(title: "Add an adjustment") { creatingCustomRule = true }
            }
        }
    }

    private func rowLabel(
        _ title: String,
        _ subtitle: String,
        trailing: String? = nil,
        trailingNegative: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if title.isEmpty { Text("Untitled") } else { Text(title) }
                }
                .font(.bodyText).foregroundStyle(Palette.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.noteText).foregroundStyle(Palette.inkFaint)
                }
            }
            Spacer(minLength: Grid.x2)
            if let trailing {
                Text(trailing)
                    .font(.figureSmall)
                    .foregroundStyle(trailingNegative ? Palette.negative : Palette.inkDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Grid.x2)
    }

    private var customDeleteTitle: String {
        switch pendingCustomDelete {
        case .rule(let r): return String(localized: "Delete \u{201C}\(r.title)\u{201D}?")
        case .dimension(let d): return String(localized: "Delete \u{201C}\(d.name)\u{201D}?")
        case .none: return String(localized: "Delete this?")
        }
    }

    private func populate() {
        if let restaurant {
            name = restaurant.name
            address = restaurant.streetAddress
            city = restaurant.city
            categoryID = restaurant.category?.persistentModelID
            groupID = restaurant.group?.persistentModelID
            isFavorite = restaurant.isFavorite
            useOverride = restaurant.baseTipOverride != nil
            overridePercent = restaurant.baseTipOverride ?? restaurant.category?.baseTipPercent ?? 18
            note = restaurant.note
            coordinate = restaurant.coordinate
            disabledRuleIDs = Set(restaurant.disabledRuleIDs)
            reminderOverride = restaurant.arrivalRemindersOn
        } else {
            let start = prefillCategory ?? categories.first
            categoryID = start?.persistentModelID
            overridePercent = start?.baseTipPercent ?? 18
            coordinate = locationManager.currentLocation?.coordinate
        }
    }

    private func createGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespaces)
        newGroupName = ""
        guard !trimmed.isEmpty else { return }
        let group = PlaceGroup(name: trimmed, sortOrder: Reorder.nextSortOrder(after: placeGroups))
        modelContext.insert(group)
        try? modelContext.save()
        groupID = group.persistentModelID
    }

    private func save() {
        let target: Restaurant
        if let restaurant {
            target = restaurant
        } else {
            target = Restaurant(name: "")
            modelContext.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.streetAddress = address.trimmingCharacters(in: .whitespaces)
        target.city = city.trimmingCharacters(in: .whitespaces)
        target.category = selectedCategory
        target.group = placeGroups.first { $0.persistentModelID == groupID }
        target.isFavorite = isFavorite
        target.baseTipOverride = useOverride ? overridePercent : nil
        target.note = note
        target.coordinate = coordinate
        target.disabledRuleIDs = Array(disabledRuleIDs)
        target.arrivalRemindersOn = reminderOverride
        try? modelContext.save()
        ArrivalReminders.shared.start()
        // No city yet but we have a point — fill it in from the map in the
        // background (won't touch a value the user typed).
        if target.city.isEmpty, let coordinate = target.coordinate {
            let id = target.uuid
            Task { await PlaceGeocoder.backfillCity(placeID: id, coordinate: coordinate, in: modelContext) }
        }
        onSaved?(target)
        dismiss()
    }
}

/// `PlusMinus` for a `Double` with a step, showing a formatted string. Hold a
/// button to repeat, faster the longer you hold.
struct PlusMinusDecimal: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: String

    var body: some View {
        HStack(spacing: 0) {
            HoldRepeatButton(symbol: "minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            Text(display)
                .font(.figure).monospacedDigit()
                .foregroundStyle(Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 2)
            HoldRepeatButton(symbol: "plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
        .frame(height: 40)
        .background(Palette.well)
        .overlay(RoundedRectangle(cornerRadius: Corner.control).strokeBorder(Palette.rule, lineWidth: 1).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: Corner.control))
    }
}

#Preview {
    RestaurantListView()
        .environment(LocationManager())
        .modelContainer(PreviewData.container)
}
