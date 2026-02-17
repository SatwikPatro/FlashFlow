import SwiftUI
import CoreData

// MARK: - Root View

struct CategoryListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
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
    
    @State private var showAddDeck = false
    @State private var showAddCategory = false
    @State private var showDeleteDeckAlert = false
    @State private var showDeleteCategoryAlert = false
    @State private var deckToDelete: CDDeck?
    @State private var categoryToDelete: CDCategory?
    @State private var itemToMove: MoveItem?
    
    var body: some View {
        List {
            // Categories first
            ForEach(rootCategories) { category in
                NavigationLink(destination: CategoryDetailView(category: category)) {
                    CategoryRowLabel(category: category)
                }
                .contextMenu {
                    Button {
                        itemToMove = .category(category)
                    } label: {
                        Label("Move to...", systemImage: "folder.badge.plus")
                    }
                    Button(role: .destructive) {
                        categoryToDelete = category
                        showDeleteCategoryAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        categoryToDelete = category
                        showDeleteCategoryAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        itemToMove = .category(category)
                    } label: {
                        Label("Move", systemImage: "arrow.right")
                    }
                    .tint(.blue)
                }
            }
            
            // Uncategorized decks below
            ForEach(uncategorizedDecks) { deck in
                DeckRow(deck: deck)
                    .contextMenu {
                        Button {
                            itemToMove = .deck(deck)
                        } label: {
                            Label("Move to...", systemImage: "folder.badge.plus")
                        }
                        Button(role: .destructive) {
                            deckToDelete = deck
                            showDeleteDeckAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deckToDelete = deck
                            showDeleteDeckAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            itemToMove = .deck(deck)
                        } label: {
                            Label("Move", systemImage: "arrow.right")
                        }
                        .tint(.blue)
                    }
            }
            .onMove(perform: moveDecks)
            
            // Empty state
            if rootCategories.isEmpty && uncategorizedDecks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 36))
                        .foregroundColor(.gray)
                    Text("No Decks Yet")
                        .font(.headline)
                    Text("Tap + to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .listRowSeparator(.hidden)
            }
        }
        .navigationTitle("FlashFlow")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showAddDeck = true } label: {
                        Label("New Deck", systemImage: "rectangle.stack.badge.plus")
                    }
                    Button { showAddCategory = true } label: {
                        Label("New Category", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddDeck) {
            CreateDeckSheet()
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showAddCategory) {
            CreateCategorySheet(parentCategory: nil)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(item: $itemToMove) { item in
            MoveItemSheet(item: item, currentParent: nil)
                .environment(\.managedObjectContext, viewContext)
        }
        .alert("Delete Deck?", isPresented: $showDeleteDeckAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let deck = deckToDelete { deleteDeck(deck) }
            }
        } message: {
            Text("This will permanently delete the deck and all its cards.")
        }
        .alert("Delete Category?", isPresented: $showDeleteCategoryAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let category = categoryToDelete { deleteCategory(category) }
            }
        } message: {
            Text("This will permanently delete the category, its subcategories, and all decks within.")
        }
    }
    
    private func deleteDeck(_ deck: CDDeck) {
        withAnimation {
            for card in deck.getSortedCards() { card.deleteMediaFiles() }
            viewContext.delete(deck)
            try? viewContext.save()
        }
        deckToDelete = nil
    }
    
    private func deleteCategory(_ category: CDCategory) {
        withAnimation {
            deleteCategoryMedia(category)
            viewContext.delete(category)
            try? viewContext.save()
        }
        categoryToDelete = nil
    }
    
    private func deleteCategoryMedia(_ category: CDCategory) {
        for deck in category.getSortedDecks() {
            for card in deck.getSortedCards() { card.deleteMediaFiles() }
        }
        for sub in category.getSortedSubcategories() { deleteCategoryMedia(sub) }
    }
    
    private func moveDecks(from source: IndexSet, to destination: Int) {
        var decksArray = Array(uncategorizedDecks)
        decksArray.move(fromOffsets: source, toOffset: destination)
        for (index, deck) in decksArray.enumerated() {
            deck.createdAt = Date(timeIntervalSince1970: TimeInterval(index))
        }
        try? viewContext.save()
    }
}

// MARK: - Category Detail View (drill-down inside a category)

struct CategoryDetailView: View {
    @ObservedObject var category: CDCategory
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var showAddDeck = false
    @State private var showAddSubcategory = false
    @State private var showDeleteDeckAlert = false
    @State private var showDeleteCategoryAlert = false
    @State private var deckToDelete: CDDeck?
    @State private var subcategoryToDelete: CDCategory?
    @State private var itemToMove: MoveItem?
    
    var body: some View {
        List {
            // Subcategories
            ForEach(category.getSortedSubcategories()) { sub in
                NavigationLink(destination: CategoryDetailView(category: sub)) {
                    CategoryRowLabel(category: sub)
                }
                .contextMenu {
                    Button {
                        itemToMove = .category(sub)
                    } label: {
                        Label("Move to...", systemImage: "folder.badge.plus")
                    }
                    Button(role: .destructive) {
                        subcategoryToDelete = sub
                        showDeleteCategoryAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        subcategoryToDelete = sub
                        showDeleteCategoryAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        itemToMove = .category(sub)
                    } label: {
                        Label("Move", systemImage: "arrow.right")
                    }
                    .tint(.blue)
                }
            }
            
            // Decks
            ForEach(category.getSortedDecks()) { deck in
                DeckRow(deck: deck)
                    .contextMenu {
                        Button {
                            itemToMove = .deck(deck)
                        } label: {
                            Label("Move to...", systemImage: "folder.badge.plus")
                        }
                        Button(role: .destructive) {
                            deckToDelete = deck
                            showDeleteDeckAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deckToDelete = deck
                            showDeleteDeckAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            itemToMove = .deck(deck)
                        } label: {
                            Label("Move", systemImage: "arrow.right")
                        }
                        .tint(.blue)
                    }
            }
            
            // Empty state
            if category.getSortedSubcategories().isEmpty && category.getSortedDecks().isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 36))
                        .foregroundColor(.gray)
                    Text("Empty Category")
                        .font(.headline)
                    Text("Add decks or subcategories")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .listRowSeparator(.hidden)
            }
        }
        .navigationTitle(category.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showAddDeck = true } label: {
                        Label("New Deck", systemImage: "rectangle.stack.badge.plus")
                    }
                    Button { showAddSubcategory = true } label: {
                        Label("New Subcategory", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddDeck) {
            CreateDeckSheet(parentCategory: category)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showAddSubcategory) {
            CreateCategorySheet(parentCategory: category)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(item: $itemToMove) { item in
            MoveItemSheet(item: item, currentParent: category)
                .environment(\.managedObjectContext, viewContext)
        }
        .alert("Delete Deck?", isPresented: $showDeleteDeckAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let deck = deckToDelete {
                    withAnimation {
                        for card in deck.getSortedCards() { card.deleteMediaFiles() }
                        viewContext.delete(deck)
                        try? viewContext.save()
                    }
                }
            }
        }
        .alert("Delete Category?", isPresented: $showDeleteCategoryAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let sub = subcategoryToDelete {
                    withAnimation {
                        viewContext.delete(sub)
                        try? viewContext.save()
                    }
                }
            }
        } message: {
            Text("This will delete the subcategory and everything inside it.")
        }
    }
}

// MARK: - Category Row (visually distinct with folder-style badge)

struct CategoryRowLabel: View {
    @ObservedObject var category: CDCategory
    
    var body: some View {
        HStack(spacing: 12) {
            // Folder-style icon with colored background
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hexString: category.colorHex).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: category.icon)
                    .foregroundColor(Color(hexString: category.colorHex))
                    .font(.system(size: 18, weight: .medium))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .font(.body)
                    .fontWeight(.semibold)
                
                let deckCount = category.getSortedDecks().count
                let subCount = category.getSortedSubcategories().count
                let cardCount = category.getTotalCardCount()
                Text(summaryText(decks: deckCount, subs: subCount, cards: cardCount))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Chevron-like indicator showing it's a folder
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(hexString: category.colorHex).opacity(0.5))
        }
        .padding(.vertical, 4)
    }
    
    private func summaryText(decks: Int, subs: Int, cards: Int) -> String {
        var parts: [String] = []
        if subs > 0 { parts.append("\(subs) subcategor\(subs == 1 ? "y" : "ies")") }
        if decks > 0 { parts.append("\(decks) deck\(decks == 1 ? "" : "s")") }
        if cards > 0 { parts.append("\(cards) card\(cards == 1 ? "" : "s")") }
        return parts.isEmpty ? "Empty" : parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: - Deck Row (simpler, card-stack look)

struct DeckRow: View {
    @ObservedObject var deck: CDDeck
    
    var body: some View {
        NavigationLink(destination: DeckDetailView(deck: deck)) {
            HStack(spacing: 12) {
                // Simple colored dot icon (no background box)
                Image(systemName: deck.icon)
                    .foregroundColor(Color(hexString: deck.colorHex))
                    .font(.system(size: 16))
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(deck.name)
                        .font(.body)
                    let count = deck.cards?.count ?? 0
                    Text("\(count) card\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Move Item Types

enum MoveItem: Identifiable {
    case category(CDCategory)
    case deck(CDDeck)
    
    var id: String {
        switch self {
        case .category(let c): return "cat_\(c.id)"
        case .deck(let d): return "deck_\(d.id)"
        }
    }
    
    var name: String {
        switch self {
        case .category(let c): return c.name
        case .deck(let d): return d.name
        }
    }
    
    var itemID: String {
        switch self {
        case .category(let c): return c.id
        case .deck(let d): return d.id
        }
    }
}

// MARK: - Move Item Sheet

struct MoveItemSheet: View {
    let item: MoveItem
    let currentParent: CDCategory?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        predicate: NSPredicate(format: "parentCategory == nil"),
        animation: .default)
    private var rootCategories: FetchedResults<CDCategory>
    
    @State private var showDuplicateAlert = false
    @State private var duplicateError = ""
    
    // The ID of the category being moved (to prevent moving into itself)
    private var movingCategoryID: String? {
        if case .category(let c) = item { return c.id }
        return nil
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Section: Move to root
                Section {
                    Button {
                        moveToRoot()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "house.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                            }
                            VStack(alignment: .leading) {
                                Text("Root (FlashFlow)")
                                    .fontWeight(.medium)
                                Text("Top level")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if currentParent == nil {
                                Text("Current")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(UIColor.tertiarySystemFill))
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .disabled(currentParent == nil)
                } header: {
                    Text("CHOOSE DESTINATION")
                }
                
                // Section: Categories
                if !rootCategories.isEmpty {
                    Section {
                        ForEach(rootCategories) { cat in
                            MoveDestinationRow(
                                category: cat,
                                item: item,
                                currentParent: currentParent,
                                movingCategoryID: movingCategoryID,
                                onSelect: { target in moveTo(category: target) }
                            )
                        }
                    } header: {
                        Text("CATEGORIES")
                    }
                }
            }
            .navigationTitle("Move '\(item.name)'")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Cannot Move", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(duplicateError)
            }
        }
    }
    
    private func moveToRoot() {
        if checkRootDuplicate(item.name, excludingID: item.itemID) {
            duplicateError = "An item named '\(item.name)' already exists at the root level."
            showDuplicateAlert = true
            return
        }
        
        switch item {
        case .category(let cat):
            cat.parentCategory = nil
        case .deck(let deck):
            deck.category = nil
        }
        try? viewContext.save()
        dismiss()
    }
    
    private func moveTo(category target: CDCategory) {
        // Prevent circular moves
        if case .category(let cat) = item {
            if cat.id == target.id || isDescendant(target, of: cat) {
                duplicateError = "Cannot move a category into itself or its own subcategory."
                showDuplicateAlert = true
                return
            }
        }
        
        // Prevent moving to same parent (no-op)
        if let current = currentParent, current.id == target.id {
            dismiss()
            return
        }
        
        // Check duplicate name at destination
        if target.hasDuplicateName(item.name, excludingCategoryID: movingCategoryID, excludingDeckID: item.deckID) {
            duplicateError = "An item named '\(item.name)' already exists in '\(target.name)'."
            showDuplicateAlert = true
            return
        }
        
        switch item {
        case .category(let cat):
            cat.parentCategory = target
        case .deck(let deck):
            deck.category = target
        }
        try? viewContext.save()
        dismiss()
    }
    
    private func checkRootDuplicate(_ candidateName: String, excludingID: String) -> Bool {
        let name = candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let request1 = NSFetchRequest<CDCategory>(entityName: "CDCategory")
        request1.predicate = NSPredicate(format: "parentCategory == nil AND name ==[c] %@ AND id != %@", name, excludingID)
        let request2 = NSFetchRequest<CDDeck>(entityName: "CDDeck")
        request2.predicate = NSPredicate(format: "category == nil AND name ==[c] %@ AND id != %@", name, excludingID)
        
        let catCount = (try? viewContext.count(for: request1)) ?? 0
        let deckCount = (try? viewContext.count(for: request2)) ?? 0
        return (catCount + deckCount) > 0
    }
    
    private func isDescendant(_ potential: CDCategory, of ancestor: CDCategory) -> Bool {
        var current: CDCategory? = potential
        while let c = current {
            if c.id == ancestor.id { return true }
            current = c.parentCategory
        }
        return false
    }
}

// Helper extension for MoveItem
extension MoveItem {
    var deckID: String? {
        if case .deck(let d) = self { return d.id }
        return nil
    }
}

// MARK: - Move Destination Row (recursive)

struct MoveDestinationRow: View {
    @ObservedObject var category: CDCategory
    let item: MoveItem
    let currentParent: CDCategory?
    let movingCategoryID: String?
    let onSelect: (CDCategory) -> Void
    
    private var isSelf: Bool {
        movingCategoryID == category.id
    }
    
    private var isCurrentParent: Bool {
        currentParent?.id == category.id
    }
    
    private var hasSubcategories: Bool {
        !category.getSortedSubcategories().isEmpty
    }
    
    var body: some View {
        if hasSubcategories && !isSelf {
            DisclosureGroup {
                // "Move here" button for this category
                Button {
                    onSelect(category)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(Color(hexString: category.colorHex))
                        Text("Move into '\(category.name)'")
                            .font(.subheadline)
                            .foregroundColor(Color(hexString: category.colorHex))
                    }
                    .padding(.vertical, 2)
                }
                .disabled(isCurrentParent)
                
                // Subcategories
                ForEach(category.getSortedSubcategories()) { sub in
                    MoveDestinationRow(
                        category: sub,
                        item: item,
                        currentParent: currentParent,
                        movingCategoryID: movingCategoryID,
                        onSelect: onSelect
                    )
                }
            } label: {
                categoryLabel
            }
        } else {
            // No subcategories — just a tappable row
            Button {
                onSelect(category)
            } label: {
                categoryLabel
            }
            .disabled(isSelf || isCurrentParent)
        }
    }
    
    private var categoryLabel: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hexString: category.colorHex).opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: category.icon)
                    .foregroundColor(Color(hexString: category.colorHex))
                    .font(.system(size: 14))
            }
            
            Text(category.name)
                .fontWeight(.medium)
                .foregroundColor(isSelf ? .secondary : .primary)
            
            Spacer()
            
            if isCurrentParent {
                Text("Current")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(UIColor.tertiarySystemFill))
                    .cornerRadius(6)
            }
            
            if isSelf {
                Text("This item")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

// MARK: - Create Category Sheet

struct CreateCategorySheet: View {
    let parentCategory: CDCategory?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var selectedIcon = "folder"
    @State private var selectedColor = FlashFlowTheme.deckColors[0]
    @State private var showIconPicker = false
    @State private var showColorPicker = false
    @State private var customColors: [String] = []
    @State private var showDuplicateAlert = false
    @State private var duplicateError = ""
    
    let quickIcons = ["folder", "tray.full", "books.vertical", "brain", "lightbulb", "star"]
    
    var body: some View {
        NavigationStack {
            Form {
                if let parent = parentCategory {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: parent.icon)
                                .foregroundColor(Color(hexString: parent.colorHex))
                            Text("Inside: \(parent.name)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("CATEGORY NAME")) {
                    TextField("Enter name", text: $name)
                }
                
                Section(header: Text("ICON")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(quickIcons, id: \.self) { icon in
                                IconButton(
                                    icon: icon,
                                    isEmoji: false,
                                    isSelected: selectedIcon == icon,
                                    color: selectedColor
                                ) {
                                    selectedIcon = icon
                                }
                            }
                            
                            Button(action: { showIconPicker = true }) {
                                VStack {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 60, height: 60)
                                        Image(systemName: "ellipsis.circle")
                                            .font(.system(size: 24))
                                            .foregroundColor(.primary)
                                    }
                                    Text("More")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                
                Section(header: Text("COLOR")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(FlashFlowTheme.deckColors.enumerated()), id: \.offset) { index, color in
                                ColorButton(
                                    color: color,
                                    name: colorName(for: index),
                                    isSelected: selectedColor == color,
                                    showDelete: false
                                ) {
                                    selectedColor = color
                                } onDelete: {}
                            }
                            
                            ForEach(customColors, id: \.self) { color in
                                ColorButton(
                                    color: color,
                                    name: "Custom",
                                    isSelected: selectedColor == color,
                                    showDelete: true
                                ) {
                                    selectedColor = color
                                } onDelete: {
                                    deleteCustomColor(color)
                                }
                            }
                            
                            Button(action: { showColorPicker = true }) {
                                VStack {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(
                                                LinearGradient(
                                                    colors: [.red, .orange, .yellow, .green, .blue, .purple],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 50, height: 50)
                                        
                                        Image(systemName: "plus")
                                            .foregroundColor(.white)
                                            .font(.system(size: 20, weight: .bold))
                                    }
                                    Text("Add")
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(parentCategory != nil ? "New Subcategory" : "New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") { createCategory() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showIconPicker) {
                SFSymbolPickerView(selectedIcon: $selectedIcon, isPresented: $showIconPicker)
            }
            .fullScreenCover(isPresented: $showColorPicker) {
                CustomColorPickerView(customColors: $customColors, selectedColor: $selectedColor, isPresented: $showColorPicker)
            }
            .alert("Duplicate Name", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(duplicateError)
            }
        }
    }
    
    private func colorName(for index: Int) -> String {
        let names = ["Indigo", "Purple", "Pink", "Rose", "Orange", "Yellow", "Green", "Teal", "Cyan", "Blue", "Violet", "Magenta"]
        return index < names.count ? names[index] : "Color"
    }
    
    private func deleteCustomColor(_ color: String) {
        customColors.removeAll { $0 == color }
        if selectedColor == color {
            selectedColor = FlashFlowTheme.deckColors[0]
        }
    }
    
    private func createCategory() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let parent = parentCategory {
            if parent.hasDuplicateName(trimmed) {
                duplicateError = "A category or deck named '\(trimmed)' already exists in '\(parent.name)'."
                showDuplicateAlert = true
                return
            }
        } else {
            if checkRootDuplicate(trimmed) {
                duplicateError = "A category or deck named '\(trimmed)' already exists at the root level."
                showDuplicateAlert = true
                return
            }
        }
        
        let category = CDCategory(context: viewContext)
        category.id = UUID().uuidString
        category.name = trimmed
        category.icon = selectedIcon
        category.colorHex = selectedColor
        category.createdAt = Date()
        category.parentCategory = parentCategory
        
        try? viewContext.save()
        dismiss()
    }
    
    private func checkRootDuplicate(_ candidateName: String) -> Bool {
        let request1 = NSFetchRequest<CDCategory>(entityName: "CDCategory")
        request1.predicate = NSPredicate(format: "parentCategory == nil AND name ==[c] %@", candidateName)
        let request2 = NSFetchRequest<CDDeck>(entityName: "CDDeck")
        request2.predicate = NSPredicate(format: "category == nil AND name ==[c] %@", candidateName)
        
        let catCount = (try? viewContext.count(for: request1)) ?? 0
        let deckCount = (try? viewContext.count(for: request2)) ?? 0
        return (catCount + deckCount) > 0
    }
}
