//
//  DeletionArchive.swift
//  Xenia
//
//  "Recently deleted." Every user-facing delete routes through here: the object
//  (and anything it owns) is serialized into a `DeletedItem`, then hard-deleted.
//  Restoring rebuilds the model(s) from the blob, re-linking parents by `uuid`
//  when they still exist. Items older than `retention` are purged on launch.
//
//  Bulk "Start over" resets (DataReset) intentionally do NOT come through here.
//

import Foundation
import SwiftData

// MARK: - Snapshots

/// A category-or-place-owned adjustment rule, as stored.
private struct RuleSnapshot: Codable {
    var uuid: UUID
    var title: String
    var detail: String
    var deltaPercent: Double
    var isStepper: Bool
    var maxSteps: Int
    var sortOrder: Int

    init(_ rule: AdjustmentRule) {
        uuid = rule.uuid
        title = rule.title
        detail = rule.detail
        deltaPercent = rule.deltaPercent
        isStepper = rule.isStepper
        maxSteps = rule.maxSteps
        sortOrder = rule.sortOrder
    }

    func makeModel() -> AdjustmentRule {
        let rule = AdjustmentRule(
            title: title, detail: detail, deltaPercent: deltaPercent,
            isStepper: isStepper, maxSteps: maxSteps, sortOrder: sortOrder
        )
        rule.uuid = uuid
        return rule
    }
}

/// A category-or-place-owned rating dimension, as stored.
private struct DimensionSnapshot: Codable {
    var uuid: UUID
    var name: String
    var maxScore: Int
    var neutralScore: Int
    var weight: Double
    var sortOrder: Int

    init(_ dimension: RatingDimension) {
        uuid = dimension.uuid
        name = dimension.name
        maxScore = dimension.maxScore
        neutralScore = dimension.neutralScore
        weight = dimension.weight
        sortOrder = dimension.sortOrder
    }

    func makeModel() -> RatingDimension {
        let dimension = RatingDimension(
            name: name, maxScore: maxScore, neutralScore: neutralScore,
            weight: weight, sortOrder: sortOrder
        )
        dimension.uuid = uuid
        return dimension
    }
}

private enum OwnerKind: String, Codable { case category, restaurant }

private struct PlaceSnapshot: Codable {
    var uuid: UUID
    var name: String
    var streetAddress: String
    /// Optional so payloads written before the city field still decode.
    var city: String?
    var latitude: Double
    var longitude: Double
    var hasCoordinate: Bool
    var isFavorite: Bool
    var visitCount: Int
    var baseTipOverride: Double?
    var disabledRuleIDs: [UUID]
    var arrivalRemindersOn: Bool?
    var note: String
    var categoryUUID: UUID?
    var groupUUID: UUID?
    var customRules: [RuleSnapshot]
    var customRatingDimensions: [DimensionSnapshot]
}

private struct CategorySnapshot: Codable {
    var uuid: UUID
    var name: String
    var symbolName: String
    var baseTipPercent: Double
    var arrivalReminderMinutes: Int
    var sortOrder: Int
    var rules: [RuleSnapshot]
    var ratingDimensions: [DimensionSnapshot]
    var memberPlaceUUIDs: [UUID]
}

private struct StandaloneRuleSnapshot: Codable {
    var rule: RuleSnapshot
    var ownerKind: OwnerKind
    var ownerUUID: UUID
    var ownerName: String
}

private struct StandaloneDimensionSnapshot: Codable {
    var dimension: DimensionSnapshot
    var ownerKind: OwnerKind
    var ownerUUID: UUID
    var ownerName: String
}

private struct HistorySnapshot: Codable {
    var date: Date
    var placeName: String
    var categoryName: String
    var billAmount: Double
    var tipPercent: Double
    var tipAmount: Double
    var total: Double
    var partySize: Int
    var ratingScores: [RatingSnapshot]
    /// Optional so payloads written before the stamp existed still decode.
    var currencyCode: String?
}

private struct GroupSnapshot: Codable {
    var uuid: UUID
    var name: String
    var sortOrder: Int
    var memberPlaceUUIDs: [UUID]
}

// MARK: - Archive

enum DeletionArchive {

    /// How long a deleted item sticks around before it's purged for good.
    nonisolated static let retention: TimeInterval = 30 * 24 * 3600

    enum RestoreOutcome: Equatable {
        case restored
        /// The item can't be restored yet — e.g. its parent is also in the trash.
        case blocked(String)
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: Archiving

    @discardableResult
    @MainActor
    static func archive(_ place: Restaurant, in context: ModelContext) -> DeletedItem? {
        let snapshot = PlaceSnapshot(
            uuid: place.uuid,
            name: place.name,
            streetAddress: place.streetAddress,
            city: place.city,
            latitude: place.latitude,
            longitude: place.longitude,
            hasCoordinate: place.hasCoordinate,
            isFavorite: place.isFavorite,
            visitCount: place.visitCount,
            baseTipOverride: place.baseTipOverride,
            disabledRuleIDs: place.disabledRuleIDs,
            arrivalRemindersOn: place.arrivalRemindersOn,
            note: place.note,
            categoryUUID: place.category?.uuid,
            groupUUID: place.group?.uuid,
            customRules: place.sortedCustomRules.map(RuleSnapshot.init),
            customRatingDimensions: place.sortedCustomRatingDimensions.map(DimensionSnapshot.init)
        )
        return finishArchive(
            kind: .place,
            title: place.name.isEmpty ? String(localized: "Unnamed place") : place.name,
            subtitle: place.category?.name ?? String(localized: "No category"),
            snapshot: snapshot,
            original: place,
            in: context
        )
    }

    @discardableResult
    @MainActor
    static func archive(_ category: TipCategory, in context: ModelContext) -> DeletedItem? {
        let snapshot = CategorySnapshot(
            uuid: category.uuid,
            name: category.name,
            symbolName: category.symbolName,
            baseTipPercent: category.baseTipPercent,
            arrivalReminderMinutes: category.arrivalReminderMinutes,
            sortOrder: category.sortOrder,
            rules: category.sortedRules.map(RuleSnapshot.init),
            ratingDimensions: category.sortedRatingDimensions.map(DimensionSnapshot.init),
            memberPlaceUUIDs: category.restaurants.map(\.uuid)
        )
        let ruleCount = snapshot.rules.count
        let ratingCount = snapshot.ratingDimensions.count
        let subtitle = "\(ruleCount) rule\(ruleCount == 1 ? "" : "s"), \(ratingCount) rating\(ratingCount == 1 ? "" : "s")"
        return finishArchive(
            kind: .category,
            title: category.name.isEmpty ? String(localized: "Unnamed category") : category.name,
            subtitle: subtitle,
            snapshot: snapshot,
            original: category,
            in: context
        )
    }

    @discardableResult
    @MainActor
    static func archive(_ rule: AdjustmentRule, in context: ModelContext) -> DeletedItem? {
        let owner: (kind: OwnerKind, uuid: UUID, name: String) = {
            if let category = rule.category {
                return (.category, category.uuid, category.name)
            }
            if let restaurant = rule.restaurant {
                return (.restaurant, restaurant.uuid, restaurant.name)
            }
            return (.category, UUID(), "")
        }()
        let snapshot = StandaloneRuleSnapshot(
            rule: RuleSnapshot(rule),
            ownerKind: owner.kind,
            ownerUUID: owner.uuid,
            ownerName: owner.name
        )
        return finishArchive(
            kind: .rule,
            title: rule.title.isEmpty ? String(localized: "Untitled rule") : rule.title,
            subtitle: owner.name.isEmpty ? "" : String(localized: "from \(owner.name)"),
            snapshot: snapshot,
            original: rule,
            in: context
        )
    }

    @discardableResult
    @MainActor
    static func archive(_ dimension: RatingDimension, in context: ModelContext) -> DeletedItem? {
        let owner: (kind: OwnerKind, uuid: UUID, name: String) = {
            if let category = dimension.category {
                return (.category, category.uuid, category.name)
            }
            if let restaurant = dimension.restaurant {
                return (.restaurant, restaurant.uuid, restaurant.name)
            }
            return (.category, UUID(), "")
        }()
        let snapshot = StandaloneDimensionSnapshot(
            dimension: DimensionSnapshot(dimension),
            ownerKind: owner.kind,
            ownerUUID: owner.uuid,
            ownerName: owner.name
        )
        return finishArchive(
            kind: .rating,
            title: dimension.name.isEmpty ? String(localized: "Untitled rating") : dimension.name,
            subtitle: owner.name.isEmpty ? "" : String(localized: "from \(owner.name)"),
            snapshot: snapshot,
            original: dimension,
            in: context
        )
    }

    @discardableResult
    @MainActor
    static func archive(_ record: TipRecord, in context: ModelContext) -> DeletedItem? {
        let snapshot = HistorySnapshot(
            date: record.date,
            placeName: record.placeName,
            categoryName: record.categoryName,
            billAmount: record.billAmount,
            tipPercent: record.tipPercent,
            tipAmount: record.tipAmount,
            total: record.total,
            partySize: record.partySize,
            ratingScores: record.ratingScores,
            currencyCode: record.currencyCode
        )
        let subtitle = "\(Format.currency(record.total, code: record.currency)) total · \(record.date.formatted(date: .abbreviated, time: .omitted))"
        return finishArchive(
            kind: .history,
            title: record.placeName.isEmpty ? String(localized: "Tip") : record.placeName,
            subtitle: subtitle,
            snapshot: snapshot,
            original: record,
            in: context
        )
    }

    @discardableResult
    @MainActor
    static func archive(_ group: PlaceGroup, in context: ModelContext) -> DeletedItem? {
        let snapshot = GroupSnapshot(
            uuid: group.uuid,
            name: group.name,
            sortOrder: group.sortOrder,
            memberPlaceUUIDs: group.places.map(\.uuid)
        )
        let count = snapshot.memberPlaceUUIDs.count
        return finishArchive(
            kind: .group,
            title: group.name.isEmpty ? String(localized: "Unnamed group") : group.name,
            subtitle: "\(count) place\(count == 1 ? "" : "s")",
            snapshot: snapshot,
            original: group,
            in: context
        )
    }

    @MainActor
    private static func finishArchive<S: Encodable, M: PersistentModel>(
        kind: DeletedKind,
        title: String,
        subtitle: String,
        snapshot: S,
        original: M,
        in context: ModelContext
    ) -> DeletedItem? {
        // If the snapshot won't serialize there's nothing to restore from later —
        // leave the original in place rather than delete it into a dead entry.
        guard let payload = try? encoder.encode(snapshot) else { return nil }
        let item = DeletedItem(kind: kind, title: title, subtitle: subtitle, payload: payload)
        context.insert(item)
        context.delete(original)
        do {
            try context.save()
            return item
        } catch {
            // Undo the insert + delete so the row genuinely stays put.
            context.rollback()
            return nil
        }
    }

    // MARK: Restoring

    @discardableResult
    @MainActor
    static func restore(_ item: DeletedItem, in context: ModelContext) -> RestoreOutcome {
        let outcome: RestoreOutcome
        switch item.kind {
        case .place:    outcome = restorePlace(item, in: context)
        case .category: outcome = restoreCategory(item, in: context)
        case .rule:     outcome = restoreRule(item, in: context)
        case .rating:   outcome = restoreRating(item, in: context)
        case .history:  outcome = restoreHistory(item, in: context)
        case .group:    outcome = restoreGroup(item, in: context)
        }

        guard case .restored = outcome else { return outcome }

        // Commit the rebuilt model(s) and the trash entry's removal in one save.
        // `item.kind` must be read before the delete makes it unreadable.
        let kind = item.kind
        context.delete(item)
        do {
            try context.save()
        } catch {
            // Nothing committed — drop the half-built models and keep the trash
            // entry so a retry doesn't build a second model with the same uuid.
            context.rollback()
            return .blocked(String(localized: "Couldn't finish restoring this. Try again."))
        }
        if kind == .place || kind == .category {
            ArrivalReminders.shared.start()
        }
        return .restored
    }

    @MainActor
    private static func restorePlace(_ item: DeletedItem, in context: ModelContext) -> RestoreOutcome {
        guard let snap = try? decoder.decode(PlaceSnapshot.self, from: item.payload) else {
            return .blocked(String(localized: "This item's data couldn't be read."))
        }
        let place = Restaurant(
            name: snap.name, streetAddress: snap.streetAddress,
            city: snap.city ?? "", note: snap.note
        )
        place.uuid = snap.uuid
        place.latitude = snap.latitude
        place.longitude = snap.longitude
        place.hasCoordinate = snap.hasCoordinate
        place.isFavorite = snap.isFavorite
        place.visitCount = snap.visitCount
        place.baseTipOverride = snap.baseTipOverride
        place.disabledRuleIDs = snap.disabledRuleIDs
        place.arrivalRemindersOn = snap.arrivalRemindersOn
        place.category = snap.categoryUUID.flatMap { findCategory($0, in: context) }
        place.group = snap.groupUUID.flatMap { findGroup($0, in: context) }
        context.insert(place)

        for ruleSnap in snap.customRules {
            let rule = ruleSnap.makeModel()
            rule.restaurant = place
            context.insert(rule)
        }
        for dimSnap in snap.customRatingDimensions {
            let dimension = dimSnap.makeModel()
            dimension.restaurant = place
            context.insert(dimension)
        }

        // The single commit + ArrivalReminders.start() happen back in restore().
        return .restored
    }

    @MainActor
    private static func restoreCategory(_ item: DeletedItem, in context: ModelContext) -> RestoreOutcome {
        guard let snap = try? decoder.decode(CategorySnapshot.self, from: item.payload) else {
            return .blocked(String(localized: "This item's data couldn't be read."))
        }
        let category = TipCategory(
            name: snap.name, symbolName: snap.symbolName,
            baseTipPercent: snap.baseTipPercent, sortOrder: snap.sortOrder
        )
        category.uuid = snap.uuid
        category.arrivalReminderMinutes = snap.arrivalReminderMinutes
        context.insert(category)

        for ruleSnap in snap.rules {
            let rule = ruleSnap.makeModel()
            rule.category = category
            context.insert(rule)
        }
        for dimSnap in snap.ratingDimensions {
            let dimension = dimSnap.makeModel()
            dimension.category = category
            context.insert(dimension)
        }

        // Re-attach members that are still around and have no category.
        for placeUUID in snap.memberPlaceUUIDs {
            if let place = findRestaurant(placeUUID, in: context), place.category == nil {
                place.category = category
            }
        }

        return .restored
    }

    @MainActor
    private static func restoreRule(_ item: DeletedItem, in context: ModelContext) -> RestoreOutcome {
        guard let snap = try? decoder.decode(StandaloneRuleSnapshot.self, from: item.payload) else {
            return .blocked(String(localized: "This item's data couldn't be read."))
        }
        let rule = snap.rule.makeModel()
        switch snap.ownerKind {
        case .category:
            guard let owner = findCategory(snap.ownerUUID, in: context) else {
                return .blocked(String(localized: "Restore \u{201C}\(snap.ownerName)\u{201D} first — this rule belonged to it."))
            }
            rule.category = owner
        case .restaurant:
            guard let owner = findRestaurant(snap.ownerUUID, in: context) else {
                return .blocked(String(localized: "Restore \u{201C}\(snap.ownerName)\u{201D} first — this rule belonged to it."))
            }
            rule.restaurant = owner
        }
        context.insert(rule)
        return .restored
    }

    @MainActor
    private static func restoreRating(_ item: DeletedItem, in context: ModelContext) -> RestoreOutcome {
        guard let snap = try? decoder.decode(StandaloneDimensionSnapshot.self, from: item.payload) else {
            return .blocked(String(localized: "This item's data couldn't be read."))
        }
        let dimension = snap.dimension.makeModel()
        switch snap.ownerKind {
        case .category:
            guard let owner = findCategory(snap.ownerUUID, in: context) else {
                return .blocked(String(localized: "Restore \u{201C}\(snap.ownerName)\u{201D} first — this rating belonged to it."))
            }
            dimension.category = owner
        case .restaurant:
            guard let owner = findRestaurant(snap.ownerUUID, in: context) else {
                return .blocked(String(localized: "Restore \u{201C}\(snap.ownerName)\u{201D} first — this rating belonged to it."))
            }
            dimension.restaurant = owner
        }
        context.insert(dimension)
        return .restored
    }

    @MainActor
    private static func restoreHistory(_ item: DeletedItem, in context: ModelContext) -> RestoreOutcome {
        guard let snap = try? decoder.decode(HistorySnapshot.self, from: item.payload) else {
            return .blocked(String(localized: "This item's data couldn't be read."))
        }
        let record = TipRecord(
            date: snap.date,
            placeName: snap.placeName,
            categoryName: snap.categoryName,
            billAmount: snap.billAmount,
            tipPercent: snap.tipPercent,
            tipAmount: snap.tipAmount,
            total: snap.total,
            partySize: snap.partySize,
            ratings: snap.ratingScores,
            currencyCode: snap.currencyCode ?? ""
        )
        context.insert(record)
        return .restored
    }

    @MainActor
    private static func restoreGroup(_ item: DeletedItem, in context: ModelContext) -> RestoreOutcome {
        guard let snap = try? decoder.decode(GroupSnapshot.self, from: item.payload) else {
            return .blocked(String(localized: "This item's data couldn't be read."))
        }
        let group = PlaceGroup(name: snap.name, sortOrder: snap.sortOrder)
        group.uuid = snap.uuid
        context.insert(group)

        for placeUUID in snap.memberPlaceUUIDs {
            if let place = findRestaurant(placeUUID, in: context), place.group == nil {
                place.group = group
            }
        }

        return .restored
    }

    // MARK: Purge

    @MainActor
    static func purgeExpired(
        olderThan cutoff: Date = Date.now.addingTimeInterval(-retention),
        in context: ModelContext
    ) {
        let descriptor = FetchDescriptor<DeletedItem>(
            predicate: #Predicate { $0.deletedAt < cutoff }
        )
        let expired = (try? context.fetch(descriptor)) ?? []
        guard !expired.isEmpty else { return }
        for item in expired { context.delete(item) }
        try? context.save()
    }

    @MainActor
    static func empty(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<DeletedItem>())) ?? []
        for item in all { context.delete(item) }
        try? context.save()
    }

    // MARK: Lookups

    @MainActor
    private static func findCategory(_ uuid: UUID, in context: ModelContext) -> TipCategory? {
        var descriptor = FetchDescriptor<TipCategory>(predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @MainActor
    private static func findRestaurant(_ uuid: UUID, in context: ModelContext) -> Restaurant? {
        var descriptor = FetchDescriptor<Restaurant>(predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @MainActor
    private static func findGroup(_ uuid: UUID, in context: ModelContext) -> PlaceGroup? {
        var descriptor = FetchDescriptor<PlaceGroup>(predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
