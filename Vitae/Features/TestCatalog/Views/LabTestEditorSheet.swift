import SwiftData
import SwiftUI

/// Создание и редактирование пользовательского показателя или комплекса.
struct LabTestEditorSheet: View {
    let test: LabTest?
    let onSave: (LabTest) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var form = LabTestForm()
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(test == nil ? "Новый показатель" : "Редактирование показателя")
                .font(.title2.weight(.semibold))
                .padding([.horizontal, .top], 20)
            Form {
                Section {
                    TextField("Название", text: $form.name, prompt: Text("Например, «Цинк»"))
                        .accessibilityIdentifier("labTest.name")
                    TextField("Сокращение", text: $form.shortName, prompt: Text("Zn"))
                    Picker("Категория", selection: $form.category) {
                        ForEach(TestCategory.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Комплексное исследование (несколько показателей)", isOn: $form.isPanel)
                }
                if !form.isPanel {
                    Section {
                        TextField("Единица по умолчанию", text: $form.unit, prompt: Text("мкмоль/л"))
                        Toggle("Качественный результат (текст, например «отрицательно»)", isOn: $form.isQualitative)
                    }
                } else {
                    Section("Компоненты") {
                        ForEach($form.components) { $component in
                            HStack {
                                TextField("Название", text: $component.name)
                                TextField("Единица", text: $component.unit).frame(width: 110)
                                Toggle("Текст", isOn: $component.isQualitative).toggleStyle(.checkbox)
                                Button {
                                    form.components.removeAll { $0.id == component.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button {
                            form.components.append(LabTestForm.Component())
                        } label: {
                            Label("Добавить компонент", systemImage: "plus")
                        }
                    }
                }
                Section {
                    TextField("Синонимы для поиска и распознавания (через запятую)", text: $form.aliasesText, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Описание", text: $form.details, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Text("Референсные интервалы не задаются в справочнике — их вводят по бланку конкретной лаборатории.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding(.horizontal, 20)
            }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!form.isValid)
                    .accessibilityIdentifier("labTest.save")
            }
            .padding(20)
        }
        .frame(width: 560, height: form.isPanel ? 640 : 560)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let test { form = CatalogStore(context: context).form(for: test) }
        }
    }

    private func save() {
        do {
            let saved = try CatalogStore(context: context).saveCustom(form, editing: test)
            onSave(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
