//
//  RecentlyDeletedView.swift
//  Xenia
//
//  The trash. Places, categories, rules, ratings, tips, and groups you removed
//  wait here for 30 days. Restore puts them back (re-linking parents that still
//  exist); a parent that's also in the trash blocks its children until it's back.
//

import SwiftUI
import SwiftData

struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \DeletedItem.deletedAt, order: .reverse) private var items: [DeletedItem]

    @State private var confirmEmpty = false
    @State private var pendingRestore: DeletedItem?
    @State private var blockedMessage: String?

    var body: some View {
        InstrumentList("Recently deleted", headerTopPadding: Grid.x5) {
            HeaderButton(title: "Done", symbol: "checkmark") { dismiss() }
        } content: {
            if items.isEmpty {
                BlankSlate(
                    headline: "Nothing here",
                    message: "Deleted places, categories, rules, ratings, groups, and tips wait here for 30 days, then clear on their own.",
                    symbol: "trash"
                )
                .plainListRow()
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PanelRow(isFirst: index == 0, isLast: index == items.count - 1) {
                        SelectRow(showsChevron: false, action: { pendingRestore = item }) {
                            row(item)
                        }
                    }
                    .contextMenu {
                        Button("Restore", systemImage: "arrow.uturn.backward") { pendingRestore = item }
                    }
                }

                Button("Empty Recently Deleted", role: .destructive) { confirmEmpty = true }
                    .buttonStyle(DangerButtonStyle())
                    .plainListRow()
                    .padding(.top, Grid.x4)
            }
        }
        .alert(
            pendingRestore.map { "Restore \u{201C}\($0.title)\u{201D}?" } ?? "Restore this?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { item in
            Button("Restore") { restore(item); pendingRestore = nil }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: { item in
            Text("Puts this \(item.kind.label.lowercased()) back where it was.")
        }
        .alert("Couldn\u{2019}t restore this yet", isPresented: Binding(
            get: { blockedMessage != nil },
            set: { if !$0 { blockedMessage = nil } }
        )) {
            Button("OK", role: .cancel) { blockedMessage = nil }
        } message: {
            Text(blockedMessage ?? "")
        }
        .alert("Empty Recently Deleted?", isPresented: $confirmEmpty) {
            Button("Empty", role: .destructive) { DeletionArchive.empty(in: modelContext) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Permanently removes everything in the trash. This can\u{2019}t be undone.")
        }
    }

    private func row(_ item: DeletedItem) -> some View {
        VStack(alignment: .leading, spacing: Grid.x2) {
            HStack(spacing: Grid.x2) {
                Text(item.kind.label.uppercased())
                    .font(.system(.caption2, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, Grid.x2)
                    .padding(.vertical, 2)
                    .background(Palette.accent, in: Capsule())
                Text(item.title).font(.cardTitle).foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            Text(detail(item))
                .font(.figureSmall)
                .foregroundStyle(Palette.inkFaint)
        }
    }

    private func detail(_ item: DeletedItem) -> String {
        let when = item.deletedAt.formatted(.relative(presentation: .named))
        let daysLeft = max(
            0,
            Int((item.deletedAt.addingTimeInterval(DeletionArchive.retention).timeIntervalSinceNow / 86_400).rounded(.up))
        )
        let parts = [
            item.subtitle,
            String(localized: "deleted \(when)"),
            String(localized: "\(daysLeft)d left"),
        ].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private func restore(_ item: DeletedItem) {
        if case .blocked(let message) = DeletionArchive.restore(item, in: modelContext) {
            blockedMessage = message
        }
    }
}

#Preview {
    RecentlyDeletedView()
        .modelContainer(PreviewData.container)
}
