//
//  CategoryListView.swift
//  Xenia
//
//  Tipping categories and their adjustment rules.
//

import SwiftUI
import SwiftData

struct CategoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TipCategory.sortOrder) private var categories: [TipCategory]

    @State private var editing: TipCategory?
    @State private var creatingNew = false
    @State private var pendingDelete: TipCategory?
    @State private var remover = RowRemover()

    private var visible: [TipCategory] {
        categories.filter { !remover.isGone($0.persistentModelID) }
    }

    var body: some View {
        InstrumentList("Rules") {
            HeaderButton(title: "Add") { creatingNew = true }
        } content: {
            if visible.isEmpty {
                BlankSlate(
                    headline: "No categories",
                    message: "A category holds a base tip and the rules you work at checkout.",
                    symbol: "dial.medium"
                )
                .plainListRow()
            } else {
                ForEach(Array(visible.enumerated()), id: \.element.persistentModelID) { index, category in
                    PanelRow(isFirst: index == 0, isLast: index == visible.count - 1) {
                        SelectRow(swipeSafe: true, action: { editing = category }) {
                            row(category)
                        }
                    }
                    .blinkCollapse(remover.phase(category.persistentModelID))
                    .deleteSwipeAction { remove(category) }
                    .contextMenu {
                        Button("Delete", role: .destructive) { pendingDelete = category }
                    }
                }
            }
        }
        .onChange(of: categories.count) { _, _ in
            remover.prune(against: categories.map(\.persistentModelID))
        }
        .sheet(item: $editing) { category in
            CategoryEditView(category: category)
        }
        .sheet(isPresented: $creatingNew) {
            CategoryEditView(category: nil)
        }
        .alert(
            pendingDelete.map { "Delete \($0.name)?" } ?? "Delete this category?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { category in
            Button("Delete", role: .destructive) { remove(category); pendingDelete = nil }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { category in
            Text("""
            Deletes the category along with its \(contentsSummary(category)). \
            Places using it fall back to no category.
            """)
        }
    }

    private func row(_ category: TipCategory) -> some View {
        // The editor's icon picker had nowhere to show: this is the one place
        // the chosen symbol is actually read back.
        HStack(spacing: Grid.x3) {
            Image(systemName: category.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.accentText)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: Grid.x1) {
                Text(category.name).font(.cardTitle).foregroundStyle(Palette.ink)
                HStack(spacing: Grid.x3) {
                    Text("Base \(Format.percent(category.baseTipPercent))")
                        .font(.figureSmall).foregroundStyle(Palette.inkDim)
                    Text(count(category.rules.count, "adjustment"))
                        .font(.figureSmall).foregroundStyle(Palette.inkFaint)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    /// "3 ratings and 4 adjustments" — a category cascades both when it goes, so
    /// the confirmation names both. The row shows just the adjustments, for room.
    private func contentsSummary(_ category: TipCategory) -> String {
        count(category.ratingDimensions.count, "rating")
            + " and " + count(category.rules.count, "adjustment")
    }

    /// Blink the row shut, then archive underneath.
    private func remove(_ category: TipCategory) {
        remover.remove(category.persistentModelID) { delete(category) }
    }

    /// Returns whether the archive actually persisted.
    private func delete(_ category: TipCategory) -> Bool {
        DeletionArchive.archive(category, in: modelContext) != nil
    }
}

#Preview {
    CategoryListView()
        .modelContainer(PreviewData.container)
}
