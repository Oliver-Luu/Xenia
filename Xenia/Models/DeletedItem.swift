//
//  DeletedItem.swift
//  Xenia
//
//  One entry in "Recently deleted". Rather than tombstoning every model (which
//  would mean filtering every query and relationship walk in the app), a delete
//  serializes the object and its owned children into `payload` and hard-deletes
//  the original. Restoring rebuilds the model(s) from the blob. See DeletionArchive.
//

import Foundation
import SwiftData

enum DeletedKind: String, Codable, CaseIterable {
    case place, category, rule, rating, history, group

    /// Short noun for the type, e.g. shown as a tag on each row.
    var label: String {
        switch self {
        case .place:    return String(localized: "Place")
        case .category: return String(localized: "Category")
        case .rule:     return String(localized: "Rule")
        case .rating:   return String(localized: "Rating")
        case .history:  return String(localized: "Tip")
        case .group:    return String(localized: "Group")
        }
    }
}

@Model
final class DeletedItem {
    var id: UUID = UUID()
    var deletedAt: Date = Date.now

    var kindRaw: String = DeletedKind.place.rawValue

    /// Display name, e.g. "Lunetta Trattoria".
    var title: String = ""
    /// Secondary line, e.g. "Sit-Down Restaurant" or "Adjustment rule · Bar".
    var subtitle: String = ""

    /// JSON of the matching snapshot struct from `DeletionArchive`.
    var payload: Data = Data()
    /// Payload format version, for future-proofing decode.
    var schemaVersion: Int = 1

    init(kind: DeletedKind, title: String, subtitle: String, payload: Data) {
        self.id = UUID()
        self.deletedAt = .now
        self.kindRaw = kind.rawValue
        self.title = title
        self.subtitle = subtitle
        self.payload = payload
        self.schemaVersion = 1
    }

    var kind: DeletedKind { DeletedKind(rawValue: kindRaw) ?? .place }
}
