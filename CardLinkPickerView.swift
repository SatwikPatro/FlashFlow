import SwiftUI
import CoreData

struct CardLinkPickerView: View {
    let deck: CDDeck?
    let excludeCardID: String?
    let onLink: (CDCard) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        animation: .default)
    private var allCards: FetchedResults<CDCard>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        predicate: NSPredicate(format: "parentCategory == nil"),
        animation: .default)
    private var rootCategories: FetchedResults<CDCategory>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        predicate: NSPredicate(format: "category == nil"),
        animation: .default)
    private var uncategorizedDecks: FetchedResults<CDDeck>
    
    @State private var searchText = ""
    
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private var searchResults: [CDCard] {
        let query = searchText.lowercased()
        return allCards.filter { card in
            if let excludeID = excludeCardID, card.id == excludeID { return false }
            let front = CardLinkHelper.plainText(card: card).lowercased()
            let back = card.backText.lowercased()
            return front.contains(query) || back.contains(query)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search cards...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
                .padding()
                
                Divider()
                
                if isSearching {
                    searchResultsList
                } else {
                    hierarchicalBrowser
                }
            }
            .navigationTitle("Link to Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    // MARK: - Search Results
    
    @ViewBuilder
    private var searchResultsList: some View {
        if searchResults.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No cards found")
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(searchResults) { card in
                    CardLinkRow(
                        card: card,
                        breadcrumb: card.deck?.getBreadcrumbPath()
                    ) {
                        selectCard(card)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
    
    // MARK: - Hierarchical Browser
    
    @ViewBuilder
    private var hierarchicalBrowser: some View {
        let hasContent = !rootCategories.isEmpty || !uncategorizedDecks.isEmpty
        
        if !hasContent {
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No cards to link yet.\nCreate some cards first!")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(rootCategories) { category in
                    CategoryLinkSection(
                        category: category,
                        excludeCardID: excludeCardID,
                        onSelectCard: { selectCard($0) }
                    )
                }
                
                ForEach(uncategorizedDecks) { deckItem in
                    DeckLinkSection(
                        deck: deckItem,
                        excludeCardID: excludeCardID,
                        onSelectCard: { selectCard($0) }
                    )
                }
            }
            .listStyle(.plain)
        }
    }
    
    private func selectCard(_ card: CDCard) {
        onLink(card)
        dismiss()
    }
}

// MARK: - Helper

enum CardLinkHelper {
    static func plainText(card: CDCard) -> String {
        if card.frontText.isEmpty { return "(Empty)" }
        if let rtfData = card.frontRTFData,
           let attrString = try? NSAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            var text = attrString.string.trimmingCharacters(in: .whitespacesAndNewlines)
            text = text.replacingOccurrences(of: "\u{1F517}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "(Empty)" : text
        }
        return card.frontText
    }
}

// MARK: - Category Link Section (no @ObservedObject)

struct CategoryLinkSection: View {
    let category: CDCategory
    let excludeCardID: String?
    let onSelectCard: (CDCard) -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        let subs = category.getSortedSubcategories()
        let decks = category.getSortedDecks()
        let hasContent = !subs.isEmpty || !decks.isEmpty
        
        if hasContent {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(subs) { sub in
                    CategoryLinkSection(
                        category: sub,
                        excludeCardID: excludeCardID,
                        onSelectCard: onSelectCard
                    )
                }
                
                ForEach(decks) { deck in
                    DeckLinkSection(
                        deck: deck,
                        excludeCardID: excludeCardID,
                        onSelectCard: onSelectCard
                    )
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .foregroundColor(Color(hexString: category.colorHex))
                        .font(.system(size: 16))
                    
                    Text(category.name)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text("\(category.getTotalCardCount())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(UIColor.tertiarySystemFill))
                        .cornerRadius(10)
                }
            }
        }
    }
}

// MARK: - Deck Link Section (no @ObservedObject)

struct DeckLinkSection: View {
    let deck: CDDeck
    let excludeCardID: String?
    let onSelectCard: (CDCard) -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        let cards = deck.getSortedCards().filter { card in
            if let excludeID = excludeCardID { return card.id != excludeID }
            return true
        }
        
        if !cards.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(cards) { card in
                    CardLinkRow(card: card, breadcrumb: nil) {
                        onSelectCard(card)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: deck.icon)
                        .foregroundColor(Color(hexString: deck.colorHex))
                        .font(.system(size: 14))
                    
                    Text(deck.name)
                    
                    Spacer()
                    
                    Text("\(cards.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(UIColor.tertiarySystemFill))
                        .cornerRadius(10)
                }
            }
        }
    }
}

// MARK: - Card Link Row

struct CardLinkRow: View {
    let card: CDCard
    let breadcrumb: String?
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                Text(CardLinkHelper.plainText(card: card))
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if !card.backText.isEmpty {
                    Text(card.backText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let path = breadcrumb {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text(path)
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
