//
//  Item.swift
//  Xenia
//
//  Created by Oliver Luu on 8/31/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
