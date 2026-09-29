//
//  HistoryListView.swift
//  Xenia
//
//  Past calculations, newest first, with a short ledger summary.
//

import SwiftUI
import SwiftData

struct HistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TipRecord.date, order: .reverse) private var records: [TipRecord]

    @State private var detail: TipRecord?
    @State private var pendingDelete: TipRecord?
    @State private var remover = RowRemover()

    private var visible: [TipRecord] {
        records.filter { !remover.isGone($0.persistentModelID) }
    }

    var body: some View {
        InstrumentList("History") {
            if visible.isEmpty {
                BlankSlate(
                    headline: "Nothing saved yet",
                    message: "Tips you save from the tip screen land here.",
                    symbol: "list.bullet.rectangle"
                )
                .plainListRow()
            } else {
                summary
                    .padding(.bottom, Grid.x6)
                    .plainListRow()

                Text("Visits").sectionLabelStyle()
                    .padding(.bottom, Grid.x2)
                    .plainListRow()

                ForEach(Array(visible.enumerated()), id: \.element.id) { index, record in
                    PanelRow(isFirst: index == 0, isLast: index == visible.count - 1) {
                        SelectRow(swipeSafe: true, action: { detail = record }) {
                            row(record)
                        }
                    }
                    .blinkCollapse(remover.phase(record.persistentModelID))
                    .deleteSwipeAction { remove(record) }
                    .contextMenu {
                        Button("Delete", role: .destructive) { pendingDelete = record }
                    }
                }
            }
        }
        .onChange(of: records.count) { _, _ in
            remover.prune(against: records.map(\.persistentModelID))
        }
        .sheet(item: $detail) { record in
            HistoryDetailView(record: record)
        }
        .alert(
            pendingDelete.map { "Delete the \($0.placeName) visit?" } ?? "Delete this visit?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { record in
            Button("Delete", role: .destructive) { remove(record); pendingDelete = nil }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private func remove(_ record: TipRecord) {
        remover.remove(record.persistentModelID) { delete(record) }
    }

    private var summary: some View {
        let count = records.count
        let avgPercent = count > 0 ? records.map(\.tipPercent).reduce(0, +) / Double(count) : 0
        let totals = TipRecord.totalsByCurrency(records)
        return Panel {
            LedgerRow(label: "Visits", value: "\(count)")
            HairRule()
            LedgerRow(label: "Average tip", value: Format.percent(avgPercent))
            HairRule()
            // One line per currency spent in. A single-currency history looks
            // exactly as it always did.
            if totals.count <= 1 {
                LedgerRow(
                    label: "Total tipped",
                    value: Format.currency(totals.first?.total ?? 0,
                                           code: totals.first?.currency ?? Format.currencyCode),
                    emphasized: true
                )
            } else {
                ForEach(Array(totals.enumerated()), id: \.element.currency) { index, entry in
                    if index > 0 { HairRule() }
                    LedgerRow(
                        label: index == 0 ? "Total tipped" : " ",
                        value: Format.currency(entry.total, code: entry.currency),
                        emphasized: true
                    )
                }
            }
        }
    }

    private func row(_ record: TipRecord) -> some View {
        VStack(alignment: .leading, spacing: Grid.x1) {
            HStack {
                Text(record.placeName).font(.cardTitle).foregroundStyle(Palette.ink)
                Spacer()
                Text(Format.currency(record.tipAmount, code: record.currency))
                    .font(.figure).foregroundStyle(Palette.ink)
            }
            HStack(spacing: Grid.x2) {
                Text(record.date, format: .dateTime.month().day().year())
                Text("\(Format.percent(record.tipPercent)) on \(Format.currency(record.billAmount, code: record.currency))")
            }
            .font(.noteText)
            .foregroundStyle(Palette.inkFaint)
        }
    }

    /// Returns whether the archive actually persisted.
    private func delete(_ record: TipRecord) -> Bool {
        DeletionArchive.archive(record, in: modelContext) != nil
    }
}

private struct HistoryDetailView: View {
    let record: TipRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your Visit").font(.cardTitle).foregroundStyle(Palette.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Palette.accentText)
            }
            .padding(.horizontal, Grid.x4)
            .padding(.top, Grid.x6)
            .padding(.bottom, Grid.x3)
            .background(alignment: .bottom) { HairRule() }

            ScrollView {
                VStack(alignment: .leading, spacing: Grid.x6) {
                    FieldGroup(label: record.placeName) {
                        Panel {
                            if !record.categoryName.isEmpty {
                                LedgerRow(label: "Category", value: record.categoryName)
                                HairRule()
                            }
                            LedgerRow(
                                label: "When",
                                value: record.date.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                    }

                    FieldGroup(label: "Amounts") {
                        Panel {
                            LedgerRow(label: "Bill",
                                      value: Format.currency(record.billAmount, code: record.currency))
                            LedgerRow(label: "Tip (\(Format.percent(record.tipPercent)))",
                                      value: Format.currency(record.tipAmount, code: record.currency))
                            LedgerRow(label: "Total",
                                      value: Format.currency(record.total, code: record.currency),
                                      emphasized: true)
                            if record.partySize > 1 {
                                HairRule()
                                LedgerRow(label: "Party", value: "\(record.partySize)")
                                LedgerRow(label: "Each pays",
                                          value: Format.currency(record.perPersonTotal, code: record.currency))
                            }
                        }
                    }

                    if !record.ratingScores.isEmpty {
                        FieldGroup(label: "Ratings") {
                            Panel {
                                ForEach(Array(record.ratingScores.enumerated()), id: \.offset) { index, entry in
                                    if index > 0 { HairRule() }
                                    LedgerRow(label: entry.name, value: "\(entry.score) / \(entry.outOf)")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Grid.x4)
                .padding(.vertical, Grid.x5)
            }
        }
        .background(Palette.ground.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    HistoryListView()
        .modelContainer(PreviewData.container)
}
