import SwiftUI

struct CSVImportSession: Identifiable {
    let id = UUID()
    let table: CSVTable
    let fileName: String
    let catalog: CatalogIndex
}

/// Сопоставление колонок CSV с полями результатов и предварительный просмотр.
struct CSVMappingSheet: View {
    let session: CSVImportSession
    let onImport: ([ExaminationDraft]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mapping = CSVMapping()
    @State private var loaded = false

    var body: some View {
        let result = CSVImporter.makeDrafts(table: session.table, mapping: mapping, catalog: session.catalog,
                                            defaultCurrency: AppSettings.defaultCurrency)
        VStack(alignment: .leading, spacing: 14) {
            Text("Импорт из CSV").font(.title2.weight(.semibold))
            Text("\(session.fileName) · строк: \(session.table.rows.count) · разделитель «\(session.table.delimiter == "\t" ? "Tab" : String(session.table.delimiter))»")
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 20) {
                Form {
                    ForEach(CSVField.allCases) { field in
                        Picker(field.title + (field.isRequired ? " *" : ""), selection: Binding(
                            get: { mapping.columns[field] },
                            set: { mapping.columns[field] = $0 }
                        )) {
                            Text("— не использовать").tag(Int?.none)
                            ForEach(Array(session.table.headers.enumerated()), id: \.offset) { index, header in
                                Text(header.isEmpty ? "Колонка \(index + 1)" : header).tag(Int?.some(index))
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(width: 360)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Предпросмотр").font(.headline)
                    ScrollView([.horizontal, .vertical]) {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                            GridRow {
                                ForEach(Array(session.table.headers.enumerated()), id: \.offset) { _, header in
                                    Text(header).font(.caption.weight(.semibold))
                                }
                            }
                            ForEach(Array(session.table.rows.prefix(8).enumerated()), id: \.offset) { _, row in
                                GridRow {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                        Text(cell).font(.caption).lineLimit(1)
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 200)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                    Divider()
                    if !mapping.missingRequired.isEmpty {
                        Label("Укажите колонки: " + mapping.missingRequired.map(\.title).joined(separator: ", "),
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Будет создано обследований: \(result.drafts.count), результатов: \(result.drafts.reduce(0) { $0 + $1.rows.count }).")
                        if !result.skippedRows.isEmpty {
                            Text("Строки без даты, названия или значения будут пропущены: \(result.skippedRows.prefix(10).map(String.init).joined(separator: ", "))\(result.skippedRows.count > 10 ? "…" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !result.unmatchedNames.isEmpty {
                            Text("Не найдены в справочнике (станут пользовательскими показателями): \(result.unmatchedNames.sorted().prefix(8).joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Импортировать") {
                    onImport(result.drafts)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!mapping.missingRequired.isEmpty || result.drafts.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 940, height: 640)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            mapping = CSVMapping.autoDetect(headers: session.table.headers)
        }
    }
}
