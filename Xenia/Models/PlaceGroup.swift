//
//  PlaceGroup.swift
//  Xenia
//
//  A user-made bucket for organizing saved places ("Work lunch", "Date night",
//  "Downtown"). A place with no group falls back to grouping by its tip category.
//

import Foundation
import SwiftData

@Model
final class PlaceGroup {
    var uuid: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Restaurant.group)
    var places: [Restaurant] = []

    init(name: String, sortOrder: Int = 0) {
        self.uuid = UUID()
        self.name = name
        self.sortOrder = sortOrder
    }
}
