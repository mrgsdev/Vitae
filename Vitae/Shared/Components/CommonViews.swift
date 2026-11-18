import Charts
import SwiftUI

/// Заголовок карточки в стиле «Здоровья»: иконка + капслок.
struct CardHeader: View {
    let title: String
    var systemImage: String?
    var trailing: String?
    /// Ссылка-действие справа в заголовке, например «Все показатели».
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.caption)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").imageScale(.small)
                    }
                    .font(.callout)
                }
                .buttonStyle(.link)
            }
        }
        .foregroundStyle(.secondary)
    }
}

struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    var trailing: String?
    var actionTitle: String?
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                CardHeader(title: title, systemImage: systemImage, trailing: trailing, actionTitle: actionTitle, action: action)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct StatusBadge: View {
    let status: ResultStatus
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbolName)
                .imageScale(.small)
            Text(compact ? status.shortTitle : status.title)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(status.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.12), in: Capsule())
        .help(status.title)
        .accessibilityLabel(status.title)
    }
}

struct ExaminationStatusBadge: View {
    let status: ExaminationStatus

    var body: some View {
        Label(status.title, systemImage: status.symbolName)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .foregroundStyle(status.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.12), in: Capsule())
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var color: Color = .primary
    var systemImage: String?
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(color)
                }
                Text(title).font(.callout).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(Theme.bigNumber(26))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: caption == nil ? 64 : 84, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 14)
    }
}

/// Нейтральное отображение изменения: направление без оценки «хорошо/плохо».
struct ChangeLabel: View {
    let absolute: Double
    let percent: Double?
    var unit: String = ""
    var font: Font = .callout

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: absolute > 0 ? "arrow.up.right" : absolute < 0 ? "arrow.down.right" : "arrow.right")
                .imageScale(.small)
            Text(Fmt.signedNumber(absolute) + (unit.isEmpty ? "" : " \(unit)"))
            if let percent {
                Text("(\(Fmt.percent(percent)))").foregroundStyle(.secondary)
            }
        }
        .font(font.monospacedDigit())
        .foregroundStyle(.primary)
        .help("Изменение показано без оценки: рост или снижение сами по себе не означают улучшения или ухудшения.")
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Мини-график для карточек.
struct SparklineView: View {
    struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    let points: [Point]
    var color: Color = .accentColor

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Дата", point.date), y: .value("Значение", point.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(color)
            PointMark(x: .value("Дата", point.date), y: .value("Значение", point.value))
                .symbolSize(14)
                .foregroundStyle(color)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

/// Строка «подпись — значение».
struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.callout)
    }
}

/// Поле лаборатории: свободный ввод + меню из известных лабораторий.
struct LaboratoryField: View {
    @Binding var text: String
    let laboratories: [String]
    var prompt = "Лаборатория"

    var body: some View {
        HStack(spacing: 4) {
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
            Menu {
                if laboratories.isEmpty {
                    Text("Лаборатории ещё не добавлены")
                }
                ForEach(laboratories, id: \.self) { lab in
                    Button(lab) { text = lab }
                }
            } label: {
                Image(systemName: "building.2")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .help("Выбрать из ранее использованных лабораторий")
        }
    }
}

/// Строка поиска для внутренних панелей.
struct InlineSearchField: View {
    @Binding var text: String
    var prompt = "Поиск"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Очистить")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}
