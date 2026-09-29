//
//  CategoryEditView.swift
//  Xenia
//
//  Create or edit a category: base tip, the ratings it asks about, and the
//  adjustment rules. Ratings and rules each open their own editor sheet.
//

import SwiftUI
import SwiftData

struct CategoryEditView: View {
    let category: TipCategory?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var symbolName = CategorySymbol.fallback
    @State private var baseTipPercent = 18.0
    @State private var reminderMinutes = 45
    @State private var restoredMinutes = 30
    @State private var editingRule: AdjustmentRule?
    @State private var creatingRule = false
    @State private var editingDimension: RatingDimension?
    @State private var creatingDimension = false
    @State private var workingCategory: TipCategory?
    @State private var pendingRuleDelete: AdjustmentRule?
    @State private var pendingDimensionDelete: RatingDimension?
    @State private var confirmCategoryDelete = false
    /// Flips the instant "Delete this category" is confirmed, so the body stops
    /// reading a model that archive() is about to hard-delete before dismissal.
    @State private var isDeletingCategory = false
    /// Set once the sheet has closed deliberately (saved, cancelled or deleted),
    /// so `.onDisappear` can tell a swipe-away from an outcome already handled.
    @State private var didSettle = false
    @FocusState private var nameFocused: Bool

    private var isNew: Bool { category == nil }
    private var rules: [AdjustmentRule] {
        guard !isDeletingCategory, let workingCategory else { return [] }
        return workingCategory.sortedRules
    }
    private var dimensions: [RatingDimension] {
        guard !isDeletingCategory, let workingCategory else { return [] }
        return workingCategory.sortedRatingDimensions
    }
    private var categoryDeleteTitle: String {
        guard !isDeletingCategory, let name = category?.name, !name.isEmpty else {
            return String(localized: "Delete this category?")
        }
        return String(localized: "Delete \(name)?")
    }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        SheetScaffold(
            title: isNew ? "New category" : "Edit category",
            confirmEnabled: canSave,
            onCancel: cancel,
            onConfirm: save
        ) {
            FieldGroup(label: "Name") {
                FieldWell(placeholder: "Category name", text: $name, focus: $nameFocused)
            }

            FieldGroup(label: "Icon") {
                iconPicker
            }

            FieldGroup(label: "Base tip") {
                Panel {
                    HStack {
                        Text("Every visit starts here").font(.bodyText).foregroundStyle(Palette.inkDim)
                        Spacer()
                        PlusMinusDecimal(
                            value: $baseTipPercent, range: 0...40, step: 0.5,
                            display: Format.percent(baseTipPercent)
                        )
                        .frame(width: 150)
                    }
                }
            }

            FieldGroup(
                label: "Arrival reminder",
                note: reminderMinutes == 0
                    ? "No nudge to tip when you get to a place in this category. Individual places can still turn it on for themselves."
                    : "The wait is about how long a visit here runs before you pay — Xenia waits this long after you arrive, then nudges you (needs reminders on in Settings)."
            ) {
                Panel {
                    Button {
                        if reminderMinutes > 0 {
                            restoredMinutes = reminderMinutes
                            reminderMinutes = 0
                        } else {
                            reminderMinutes = max(restoredMinutes, 1)
                        }
                    } label: {
                        HStack(spacing: Grid.x3) {
                            MarkerBox(isOn: reminderMinutes > 0)
                            Text("Remind me to tip at these places")
                                .font(.bodyText).foregroundStyle(Palette.ink)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if reminderMinutes > 0 {
                        HairRule()
                        HStack {
                            Text("Wait after arriving").font(.bodyText).foregroundStyle(Palette.inkDim)
                            Spacer()
                            PlusMinus(
                                value: reminderMinutes, range: 1...180,
                                display: "\(reminderMinutes) min"
                            ) { reminderMinutes = $0; restoredMinutes = $0 }
                            .frame(width: 150)
                        }
                    }
                }
            }

            FieldGroup(
                label: "Ratings to ask about",
                note: dimensions.isEmpty
                    ? "Leave empty to skip the scoring step for this category."
                    : "Tap one to change its scale or how much it counts."
            ) {
                Panel(padding: 0, spacing: 0) {
                    if dimensions.isEmpty {
                        Text("None yet.")
                            .font(.noteText).foregroundStyle(Palette.inkFaint)
                            .padding(Grid.x4)
                    } else {
                        ForEach(Array(dimensions.enumerated()), id: \.element.uuid) { index, dimension in
                            if index > 0 { HairRule() }
                            ReorderableRow(
                                index: index,
                                count: dimensions.count,
                                onEdit: { editingDimension = dimension },
                                onMove: { Reorder.move(dimension, by: $0, in: dimensions, saving: modelContext) }
                            ) {
                                dimensionRowLabel(dimension)
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) { pendingDimensionDelete = dimension }
                            }
                        }
                    }
                    HairRule()
                    AddRow(title: "Add a rating") {
                        ensureWorkingCategory()
                        creatingDimension = true
                    }
                }
            }

            FieldGroup(
                label: "Adjustment rules",
                note: rules.count > 1 ? "Arrows reorder them. This is the order you'll see at checkout." : nil
            ) {
                Panel(padding: 0, spacing: 0) {
                    if rules.isEmpty {
                        Text("None yet.")
                            .font(.noteText).foregroundStyle(Palette.inkFaint)
                            .padding(Grid.x4)
                    } else {
                        ForEach(Array(rules.enumerated()), id: \.element.uuid) { index, rule in
                            if index > 0 { HairRule() }
                            ReorderableRow(
                                index: index,
                                count: rules.count,
                                onEdit: { editingRule = rule },
                                onMove: { Reorder.move(rule, by: $0, in: rules, saving: modelContext) }
                            ) {
                                ruleRow(rule)
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) { pendingRuleDelete = rule }
                            }
                        }
                    }
                    HairRule()
                    AddRow(title: "Add an adjustment") {
                        ensureWorkingCategory()
                        creatingRule = true
                    }
                }
            }

            if category != nil {
                Button("Delete this category") { confirmCategoryDelete = true }
                    .buttonStyle(DangerButtonStyle())
            }
        }
        .alert(
            pendingRuleDelete.map { "Delete \u{201C}\($0.title)\u{201D}?" } ?? "Delete this adjustment?",
            isPresented: Binding(get: { pendingRuleDelete != nil }, set: { if !$0 { pendingRuleDelete = nil } }),
            presenting: pendingRuleDelete
        ) { rule in
            Button("Delete", role: .destructive) { deleteRule(rule); pendingRuleDelete = nil }
            Button("Cancel", role: .cancel) { pendingRuleDelete = nil }
        }
        .alert(
            pendingDimensionDelete.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "Delete this rating?",
            isPresented: Binding(get: { pendingDimensionDelete != nil }, set: { if !$0 { pendingDimensionDelete = nil } }),
            presenting: pendingDimensionDelete
        ) { dimension in
            Button("Delete", role: .destructive) { deleteDimension(dimension); pendingDimensionDelete = nil }
            Button("Cancel", role: .cancel) { pendingDimensionDelete = nil }
        }
        .alert(
            categoryDeleteTitle,
            isPresented: $confirmCategoryDelete
        ) {
            Button("Delete", role: .destructive) {
                guard let category else { dismiss(); return }
                didSettle = true
                isDeletingCategory = true
                DeletionArchive.archive(category, in: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Places using this category fall back to no category.")
        }
        .onAppear(perform: populate)
        // Adding a rating or a rule to a brand-new category has to insert the
        // category first (`ensureWorkingCategory`), and the child editor's own
        // save() writes it to disk. Cancel cleans that up, but a swipe-down
        // dismissal never calls it — without this the draft survives as a stray
        // "New category" in the Rules list, the pickers and Settings.
        .onDisappear { if !didSettle { discardDraft() } }
        .sheet(item: $editingRule) { rule in
            RuleEditView(rule: rule)
        }
        .sheet(isPresented: $creatingRule) {
            if let workingCategory {
                RuleEditView(rule: nil, category: workingCategory)
            }
        }
        .sheet(item: $editingDimension) { dimension in
            RatingEditView(dimension: dimension)
        }
        .sheet(isPresented: $creatingDimension) {
            if let workingCategory {
                RatingEditView(dimension: nil, category: workingCategory)
            }
        }
    }

    private var iconPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Grid.x2) {
                ForEach(CategorySymbol.options, id: \.self) { option in
                    Button {
                        symbolName = option
                    } label: {
                        Image(systemName: option)
                            .font(.system(size: 16))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(symbolName == option ? Palette.onAccent : Palette.inkDim)
                            .background(symbolName == option ? Palette.accent : Palette.well)
                            .overlay(
                                RoundedRectangle(cornerRadius: Corner.chip)
                                    .strokeBorder(Palette.rule, lineWidth: symbolName == option ? 0 : 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Corner.chip))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func dimensionRowLabel(_ dimension: RatingDimension) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if dimension.name.isEmpty { Text("Untitled") } else { Text(dimension.name) }
            }
            .font(.bodyText).foregroundStyle(Palette.ink)
            Text(dimension.summary)
                .font(.noteText).foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Grid.x2)
    }

    private func ruleRow(_ rule: AdjustmentRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title).font(.bodyText).foregroundStyle(Palette.ink)
                if rule.isStepper {
                    Text("Stepper, up to \(rule.maxSteps) times")
                        .font(.noteText).foregroundStyle(Palette.inkFaint)
                } else if !rule.detail.isEmpty {
                    Text(rule.detail).font(.noteText).foregroundStyle(Palette.inkFaint)
                }
            }
            Spacer()
            Text(Format.signedPercent(rule.deltaPercent))
                .font(.figure)
                .foregroundStyle(rule.deltaPercent < 0 ? Palette.negative : Palette.inkDim)
        }
        .padding(.vertical, Grid.x2)
    }

    private func deleteDimension(_ dimension: RatingDimension) {
        DeletionArchive.archive(dimension, in: modelContext)
    }

    // MARK: - Lifecycle

    private func populate() {
        guard let category else { return }
        workingCategory = category
        name = category.name
        symbolName = category.symbolName
        baseTipPercent = category.baseTipPercent
        reminderMinutes = category.arrivalReminderMinutes
        if category.arrivalReminderMinutes > 0 { restoredMinutes = category.arrivalReminderMinutes }
        else if let seeded = SeedData.defaultReminderMinutes(forCategoryNamed: category.name), seeded > 0 {
            restoredMinutes = seeded
        }
    }

    private func ensureWorkingCategory() {
        guard workingCategory == nil else { return }
        let created = TipCategory(
            name: name.isEmpty ? "New category" : name,
            symbolName: symbolName,
            baseTipPercent: baseTipPercent,
            sortOrder: Int.max
        )
        created.arrivalReminderMinutes = reminderMinutes
        modelContext.insert(created)
        workingCategory = created
    }

    private func save() {
        didSettle = true
        ensureWorkingCategory()
        guard let workingCategory else { return }
        workingCategory.name = name.trimmingCharacters(in: .whitespaces)
        workingCategory.symbolName = symbolName
        workingCategory.baseTipPercent = baseTipPercent
        workingCategory.arrivalReminderMinutes = reminderMinutes
        if workingCategory.sortOrder == Int.max {
            // Everything except this draft, which is already in the context
            // carrying the Int.max sentinel.
            let existing = ((try? modelContext.fetch(FetchDescriptor<TipCategory>())) ?? [])
                .filter { $0.sortOrder != Int.max }
            workingCategory.sortOrder = Reorder.nextSortOrder(after: existing)
        }
        try? modelContext.save()
        ArrivalReminders.shared.start()
        dismiss()
    }

    private func cancel() {
        didSettle = true
        discardDraft()
        dismiss()
    }

    /// Removes the placeholder category `ensureWorkingCategory()` inserted for a
    /// new category the user walked away from. Hard-delete, not archive — the
    /// user never saved it, so it has no business in Recently Deleted.
    private func discardDraft() {
        guard isNew, let workingCategory else { return }
        modelContext.delete(workingCategory)
        try? modelContext.save()
        self.workingCategory = nil
    }

    private func deleteRule(_ rule: AdjustmentRule) {
        DeletionArchive.archive(rule, in: modelContext)
    }
}

struct RuleEditView: View {
    let rule: AdjustmentRule?
    /// Set when creating a rule owned by a category.
    var category: TipCategory?
    /// Set when creating a rule owned by a single place.
    var restaurant: Restaurant?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var detail = ""
    @State private var deltaPercent = 2.0
    @State private var isStepper = false
    @State private var maxSteps = 5
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    private var isNew: Bool { rule == nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        SheetScaffold(
            title: isNew ? "New adjustment" : "Edit adjustment",
            confirmEnabled: canSave,
            onCancel: { dismiss() },
            onConfirm: save
        ) {
            FieldGroup(label: "Adjustment") {
                FieldWell(placeholder: "Title", text: $title, focus: $titleFocused)
            }
            FieldGroup(label: "When to use it") {
                Panel {
                    TextField("Optional", text: $detail, axis: .vertical)
                        .font(.bodyText).foregroundStyle(Palette.ink)
                        .lineLimit(1...3)
                }
            }
            FieldGroup(
                label: "Effect",
                note: isStepper
                    ? "Applied once per step, up to \(maxSteps) times."
                    : "Applied when you switch it on."
            ) {
                Panel {
                    HStack {
                        Text("Adjust by").font(.bodyText).foregroundStyle(Palette.inkDim)
                        Spacer()
                        PlusMinusDecimal(
                            value: $deltaPercent, range: -20...20, step: 0.5,
                            display: Format.signedPercent(deltaPercent)
                        )
                        .frame(width: 150)
                    }
                    HairRule()
                    Button { isStepper.toggle() } label: {
                        HStack(spacing: Grid.x3) {
                            MarkerBox(isOn: isStepper)
                            Text("Can apply more than once").font(.bodyText).foregroundStyle(Palette.ink)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if isStepper {
                        HairRule()
                        HStack {
                            Text("Up to").font(.bodyText).foregroundStyle(Palette.inkDim)
                            Spacer()
                            PlusMinus(value: maxSteps, range: 1...20, display: "\(maxSteps)×") {
                                maxSteps = $0
                            }
                            .frame(width: 150)
                        }
                    }
                }
            }

            if rule != nil {
                Button("Delete this adjustment") { confirmDelete = true }
                    .buttonStyle(DangerButtonStyle())
            }
        }
        .onAppear(perform: populate)
        .alert("Delete \u{201C}\(title)\u{201D}?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let rule {
                    DeletionArchive.archive(rule, in: modelContext)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func populate() {
        guard let rule else { return }
        title = rule.title
        detail = rule.detail
        deltaPercent = rule.deltaPercent
        isStepper = rule.isStepper
        maxSteps = rule.maxSteps
    }

    private func save() {
        if let rule {
            rule.title = title.trimmingCharacters(in: .whitespaces)
            rule.detail = detail.trimmingCharacters(in: .whitespaces)
            rule.deltaPercent = deltaPercent
            rule.isStepper = isStepper
            rule.maxSteps = maxSteps
        } else if let category {
            let new = AdjustmentRule(
                title: title.trimmingCharacters(in: .whitespaces),
                detail: detail.trimmingCharacters(in: .whitespaces),
                deltaPercent: deltaPercent,
                isStepper: isStepper,
                maxSteps: maxSteps,
                sortOrder: Reorder.nextSortOrder(after: category.rules)
            )
            new.category = category
            category.rules.append(new)
            modelContext.insert(new)
        } else if let restaurant {
            let new = AdjustmentRule(
                title: title.trimmingCharacters(in: .whitespaces),
                detail: detail.trimmingCharacters(in: .whitespaces),
                deltaPercent: deltaPercent,
                isStepper: isStepper,
                maxSteps: maxSteps,
                sortOrder: Reorder.nextSortOrder(after: restaurant.customRules)
            )
            new.restaurant = restaurant
            restaurant.customRules.append(new)
            modelContext.insert(new)
        }
        try? modelContext.save()
        dismiss()
    }
}

/// Create or edit one rating dimension: its name, 1...max scale, neutral mark,
/// and how many points a step away from neutral is worth.
struct RatingEditView: View {
    let dimension: RatingDimension?
    /// Set when creating a rating owned by a category.
    var category: TipCategory?
    /// Set when creating a rating owned by a single place.
    var restaurant: Restaurant?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var maxScore = RatingDefaults.maxScore
    @State private var neutralScore = RatingDefaults.neutralScore
    @State private var weight = RatingDefaults.weight
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    private var isNew: Bool { dimension == nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var swing: Double {
        Double(max(maxScore - neutralScore, neutralScore - 1)) * weight
    }

    /// The neutral mark can't sit outside its own 1...max scale. The stepper
    /// already pulls it down when the top of the scale drops; this is the belt
    /// and braces on the way to the store.
    private var clampedNeutral: Int { min(max(neutralScore, 1), maxScore) }

    var body: some View {
        SheetScaffold(
            title: isNew ? "New rating" : "Edit rating",
            confirmEnabled: canSave,
            onCancel: { dismiss() },
            onConfirm: save
        ) {
            FieldGroup(label: "Name") {
                FieldWell(placeholder: "e.g. Cleanliness", text: $name, focus: $nameFocused)
            }

            FieldGroup(
                label: "Scale",
                note: "Scored 1 to \(maxScore). \(neutralScore) means \u{201C}no opinion\u{201D} and changes nothing."
            ) {
                Panel {
                    HStack {
                        Text("Top of the scale").font(.bodyText).foregroundStyle(Palette.inkDim)
                        Spacer()
                        PlusMinus(value: maxScore, range: 2...RatingDefaults.maxScoreLimit, display: "1–\(maxScore)") {
                            maxScore = $0
                            neutralScore = min(neutralScore, maxScore)
                        }
                        .frame(width: 150)
                    }
                    HairRule()
                    HStack {
                        Text("Neutral mark").font(.bodyText).foregroundStyle(Palette.inkDim)
                        Spacer()
                        PlusMinus(value: neutralScore, range: 1...maxScore, display: "\(neutralScore)") {
                            neutralScore = $0
                        }
                        .frame(width: 150)
                    }
                }
            }

            FieldGroup(
                label: "Weight",
                note: "A best or worst score moves the tip by up to \(Format.percent(swing))."
            ) {
                Panel {
                    HStack {
                        Text("Each point").font(.bodyText).foregroundStyle(Palette.inkDim)
                        Spacer()
                        PlusMinusDecimal(
                            value: $weight, range: 0...10, step: 0.5,
                            display: "\(Format.percent(weight))/pt"
                        )
                        .frame(width: 160)
                    }
                }
            }

            if dimension != nil {
                Button("Delete this rating") { confirmDelete = true }
                    .buttonStyle(DangerButtonStyle())
            }
        }
        .onAppear {
            populate()
            if isNew { nameFocused = true }
        }
        .alert("Delete \u{201C}\(name)\u{201D}?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let dimension {
                    DeletionArchive.archive(dimension, in: modelContext)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func populate() {
        guard let dimension else { return }
        name = dimension.name
        maxScore = dimension.maxScore
        neutralScore = dimension.neutralScore
        weight = dimension.weight
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let dimension {
            dimension.name = trimmed
            dimension.maxScore = maxScore
            dimension.neutralScore = clampedNeutral
            dimension.weight = weight
        } else if let category {
            let new = RatingDimension(
                name: trimmed,
                maxScore: maxScore,
                neutralScore: clampedNeutral,
                weight: weight,
                sortOrder: Reorder.nextSortOrder(after: category.ratingDimensions)
            )
            new.category = category
            category.ratingDimensions.append(new)
            modelContext.insert(new)
        } else if let restaurant {
            let new = RatingDimension(
                name: trimmed,
                maxScore: maxScore,
                neutralScore: clampedNeutral,
                weight: weight,
                sortOrder: Reorder.nextSortOrder(after: restaurant.customRatingDimensions)
            )
            new.restaurant = restaurant
            restaurant.customRatingDimensions.append(new)
            modelContext.insert(new)
        }
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    CategoryEditView(category: nil)
        .modelContainer(PreviewData.container)
}
