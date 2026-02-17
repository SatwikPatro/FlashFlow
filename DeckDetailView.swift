import SwiftUI
import CoreData

struct DeckDetailView: View {
    let deck: CDDeck
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest var cards: FetchedResults<CDCard>
    
    @State private var showAddCard = false
    @State private var showDeleteAlert = false
    @State private var cardToDelete: CDCard?
    @State private var editingCard: CDCard?
    @State private var showStudyMode = false
    @State private var showExportURL: IdentifiableURL?
    @State private var showImportPicker = false
    @State private var showImportResult = false
    @State private var importResultMessage = ""
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    
    init(deck: CDDeck) {
        self.deck = deck
        let request = NSFetchRequest<CDCard>(entityName: "CDCard")
        request.predicate = NSPredicate(format: "deck == %@", deck)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        self._cards = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        List {
            // Deck info header
            Section {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hexString: deck.colorHex).opacity(0.2))
                            .frame(width: 50, height: 50)
                        Image(systemName: deck.icon)
                            .font(.system(size: 24))
                            .foregroundColor(Color(hexString: deck.colorHex))
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(deck.name)
                            .font(.headline)
                        Text("\(cards.count) card\(cards.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Study button
            if !cards.isEmpty {
                Section {
                    Button(action: { showStudyMode = true }) {
                        HStack {
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18))
                            Text("Study Deck")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .background(Color(hexString: deck.colorHex))
                        .cornerRadius(12)
                    }
                }
            }
            
            // Cards list
            if !cards.isEmpty {
                Section(header: Text("CARDS")) {
                    ForEach(cards) { card in
                        Button(action: { editingCard = card }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(getDisplayText(card: card))
                                    .font(.body)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: requestDelete)
                    .onMove(perform: moveCards)
                }
            } else {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 36))
                            .foregroundColor(.gray)
                        Text("No Cards Yet")
                            .font(.headline)
                        Text("Tap + to add your first card")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
            
            // Add card button
            Section {
                Button(action: { showAddCard = true }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("New Card")
                    }
                    .foregroundColor(Color(hexString: deck.colorHex))
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Menu {
                        Section("Import") {
                            Button {
                                showImportPicker = true
                            } label: {
                                Label("Import Cards from File", systemImage: "square.and.arrow.down")
                            }
                        }
                        Section("Export") {
                            Button {
                                exportAsJSON()
                            } label: {
                                Label("Export as JSON (full)", systemImage: "doc.zipper")
                            }
                            Button {
                                exportAsCSV()
                            } label: {
                                Label("Export as CSV", systemImage: "tablecells")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showAddCard) {
            CreateCardSheet(deck: deck)
                .environment(\.managedObjectContext, viewContext)
        }
        .alert("Delete Card?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let card = cardToDelete {
                    deleteCard(card)
                }
            }
        }
        .sheet(item: $editingCard) { card in
            EditCardSheet(card: card)
                .environment(\.managedObjectContext, viewContext)
        }
        .fullScreenCover(isPresented: $showStudyMode) {
            StudyModeView(deck: deck)
        }
        .sheet(item: $showExportURL) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: $showImportPicker) {
            DocumentImportPicker { url in
                performImport(url: url)
            }
        }
        .alert("Import Successful", isPresented: $showImportResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Imported \(importResultMessage)")
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage)
        }
    }
    
    // MARK: - Export
    
    private func exportAsJSON() {
        if let url = ImportExportManager.shared.exportDeckAsJSON(deck) {
            showExportURL = IdentifiableURL(url: url)
        }
    }
    
    private func exportAsCSV() {
        if let url = ImportExportManager.shared.exportDeckAsCSV(deck) {
            showExportURL = IdentifiableURL(url: url)
        }
    }
    
    private func performImport(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importErrorMessage = "Could not access the selected file."
            showImportError = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let result = try ImportExportManager.shared.importCardsIntoDeck(
                url: url, deck: deck, context: viewContext
            )
            importResultMessage = "\(result) card\(result == 1 ? "" : "s")"
            showImportResult = true
        } catch {
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }
    
    private func requestDelete(offsets: IndexSet) {
        if let index = offsets.first {
            cardToDelete = cards[index]
            showDeleteAlert = true
        }
    }
    
    private func deleteCard(_ card: CDCard) {
        withAnimation {
            card.deleteMediaFiles() // Clean up image/audio files from disk
            viewContext.delete(card)
            try? viewContext.save()
        }
        cardToDelete = nil
    }
    
    private func moveCards(from source: IndexSet, to destination: Int) {
        var cardsArray = Array(cards)
        cardsArray.move(fromOffsets: source, toOffset: destination)
        
        // Update createdAt to maintain order
        for (index, card) in cardsArray.enumerated() {
            card.createdAt = Date(timeIntervalSince1970: TimeInterval(index))
        }
        
        try? viewContext.save()
    }
    
    private func getDisplayText(card: CDCard) -> AttributedString {
        if card.frontText.isEmpty {
            return AttributedString("(Empty)")
        }
        
        // If there's RTF data, process it
        if let rtfData = card.frontRTFData,
           let nsAttrString = try? NSAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            
            let mutableAttr = NSMutableAttributedString(attributedString: nsAttrString)
            
            // Find all links and make them smaller/subscript
            nsAttrString.enumerateAttribute(.link, in: NSRange(location: 0, length: nsAttrString.length)) { value, range, _ in
                if value != nil {
                    // Make links smaller and add visual distinction
                    mutableAttr.addAttribute(.font, value: UIFont.systemFont(ofSize: 12), range: range)
                    mutableAttr.addAttribute(.baselineOffset, value: -2, range: range)
                    mutableAttr.addAttribute(.foregroundColor, value: UIColor.systemBlue.withAlphaComponent(0.7), range: range)
                }
            }
            
            // Convert to AttributedString
            if let attributedString = try? AttributedString(mutableAttr, including: \.uiKit) {
                return attributedString
            }
        }
        
        return AttributedString(card.frontText)
    }
}

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}
