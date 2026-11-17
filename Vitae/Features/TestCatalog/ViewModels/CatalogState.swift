import Foundation

/// Строка таблицы справочника.
struct CatalogRow: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let shortName: String
    let category: TestCategory
    let categoryTitle: String
    let unit: String
    let kindTitle: String
    let isCustom: Bool
    let isFavorite: Bool
    let favoriteSortKey: Int
    let sourceSortKey: Int
    let resultCount: Int
    let panelName: String?
    let sortOrder: Int
    let searchText: String

    init(entry: CatalogEntry, resultCount: Int, panelName: String?) {
        code = entry.code
        name = entry.name
        shortName = entry.shortName
        category = entry.category
        categoryTitle = entry.category.title
        unit = entry.unit
        kindTitle = entry.isPanel ? "Комплекс" : entry.isQualitative ? "Текстовый" : "Числовой"
        isCustom = entry.isCustom
        isFavorite = entry.isFavorite
        favoriteSortKey = entry.isFavorite ? 0 : 1
        sourceSortKey = entry.isCustom ? 0 : 1
        self.resultCount = resultCount
        self.panelName = panelName
        sortOrder = entry.sortOrder
        searchText = ([entry.name, entry.shortName] + entry.aliases).joined(separator: " ").searchNormalized
    }
}

struct CatalogState {
    var searchText = ""
    var category: TestCategory?
    var onlyFavorites = false
    var onlyCustom = false
    var selection: String?
    var showInspector = true
    var sortOrder: [KeyPathComparator<CatalogRow>] = [KeyPathComparator(\CatalogRow.sortOrder)]

    func apply(to rows: [CatalogRow]) -> [CatalogRow] {
        let query = searchText.searchNormalized
        return rows.filter { row in
            (query.isEmpty || row.searchText.contains(query))
                && (category == nil || row.category == category)
                && (!onlyFavorites || row.isFavorite)
                && (!onlyCustom || row.isCustom)
        }
        .sorted(using: sortOrder)
    }
}
