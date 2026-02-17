import Foundation
import CoreData
import UIKit
import UniformTypeIdentifiers
import SwiftUI

// MARK: - Export Data Models

struct ExportedDeck: Codable {
    let version: Int
    let exportDate: Date
    let name: String
    let icon: String
    let colorHex: String
    let cards: [ExportedCard]
}

struct ExportedCard: Codable {
    let frontText: String
    let backText: String
    let frontRTFBase64: String?
    let backRTFBase64: String?
    let frontImages: [String]   // base64 encoded
    let backImages: [String]
    let frontAudios: [String]   // base64 encoded
    let backAudios: [String]
}

// MARK: - Import Export Manager

class ImportExportManager {
    
    static let shared = ImportExportManager()
    
    // MARK: - Export Deck as JSON
    
    func exportDeckAsJSON(_ deck: CDDeck) -> URL? {
        let exported = ExportedDeck(
            version: 1,
            exportDate: Date(),
            name: deck.name,
            icon: deck.icon,
            colorHex: deck.colorHex,
            cards: deck.getSortedCards().map { exportCard($0) }
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        guard let jsonData = try? encoder.encode(exported) else { return nil }
        
        let safeName = deck.name.replacingOccurrences(of: " ", with: "_")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName)
            .appendingPathExtension("json")
        
        do {
            try jsonData.write(to: fileURL)
            return fileURL
        } catch {
            print("Export write failed: \(error)")
            return nil
        }
    }
    
    // MARK: - Export Deck as CSV
    
    func exportDeckAsCSV(_ deck: CDDeck) -> URL? {
        var csv = "front,back\n"
        for card in deck.getSortedCards() {
            csv += "\(escapeCSV(card.frontText)),\(escapeCSV(card.backText))\n"
        }
        
        let safeName = deck.name.replacingOccurrences(of: " ", with: "_")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).csv")
        
        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("CSV export failed: \(error)")
            return nil
        }
    }
    
    // MARK: - Import Cards Into Existing Deck
    
    func importCardsIntoDeck(url: URL, deck: CDDeck, context: NSManagedObjectContext) throws -> Int {
        let data = try Data(contentsOf: url)
        
        if url.pathExtension.lowercased() == "csv" {
            return try importCSVIntoDeck(data: data, deck: deck, context: context)
        } else {
            return try importJSONIntoDeck(data: data, deck: deck, context: context)
        }
    }
    
    // MARK: - Private: JSON Import
    
    private func importJSONIntoDeck(data: Data, deck: CDDeck, context: NSManagedObjectContext) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(ExportedDeck.self, from: data)
        
        let existingFronts = Set(
            deck.getSortedCards().map { $0.frontText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        
        var cardCount = 0
        for exportedCard in exported.cards {
            let front = exportedCard.frontText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !existingFronts.contains(front) else { continue }
            importCard(exportedCard, context: context, deck: deck)
            cardCount += 1
        }
        
        try context.save()
        return cardCount
    }
    
    // MARK: - Private: CSV Import
    
    private func importCSVIntoDeck(data: Data, deck: CDDeck, context: NSManagedObjectContext) throws -> Int {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidFormat
        }
        
        let rows = parseCSV(content)
        
        var startIndex = 0
        if rows.count > 1 {
            let firstRow = rows[0].map { $0.lowercased() }
            if firstRow.contains("front") || firstRow.contains("question") || firstRow.contains("term") {
                startIndex = 1
            }
        }
        
        guard rows.count > startIndex else {
            throw ImportError.emptyFile
        }
        
        let existingFronts = Set(
            deck.getSortedCards().map { $0.frontText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        
        var cardCount = 0
        for i in startIndex..<rows.count {
            let row = rows[i]
            guard row.count >= 2 else { continue }
            
            let front = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let back = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty else { continue }
            guard !existingFronts.contains(front.lowercased()) else { continue }
            
            let card = CDCard(context: context)
            card.id = UUID().uuidString
            card.frontText = front
            card.backText = back
            card.createdAt = Date()
            card.deck = deck
            cardCount += 1
        }
        
        try context.save()
        return cardCount
    }
    
    // MARK: - Private: Export Card
    
    private func exportCard(_ card: CDCard) -> ExportedCard {
        let frontImgs = card.frontImagePathArray.compactMap { path -> String? in
            guard let img = CDCard.loadImage(from: path),
                  let data = img.jpegData(compressionQuality: 0.8) else { return nil }
            return data.base64EncodedString()
        }
        let backImgs = card.backImagePathArray.compactMap { path -> String? in
            guard let img = CDCard.loadImage(from: path),
                  let data = img.jpegData(compressionQuality: 0.8) else { return nil }
            return data.base64EncodedString()
        }
        
        let frontAuds = card.frontAudioPathArray.compactMap { path -> String? in
            let resolved = CDCard.resolvedPath(for: path)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: resolved)) else { return nil }
            return data.base64EncodedString()
        }
        let backAuds = card.backAudioPathArray.compactMap { path -> String? in
            let resolved = CDCard.resolvedPath(for: path)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: resolved)) else { return nil }
            return data.base64EncodedString()
        }
        
        return ExportedCard(
            frontText: card.frontText,
            backText: card.backText,
            frontRTFBase64: card.frontRTFData?.base64EncodedString(),
            backRTFBase64: card.backRTFData?.base64EncodedString(),
            frontImages: frontImgs,
            backImages: backImgs,
            frontAudios: frontAuds,
            backAudios: backAuds
        )
    }
    
    // MARK: - Private: Import Card
    
    private func importCard(_ exported: ExportedCard, context: NSManagedObjectContext, deck: CDDeck) {
        let card = CDCard(context: context)
        card.id = UUID().uuidString
        card.frontText = exported.frontText
        card.backText = exported.backText
        card.createdAt = Date()
        card.deck = deck
        
        // RTF data
        if let rtfBase64 = exported.frontRTFBase64 {
            card.frontRTFData = Data(base64Encoded: rtfBase64)
        }
        if let rtfBase64 = exported.backRTFBase64 {
            card.backRTFData = Data(base64Encoded: rtfBase64)
        }
        
        // Images
        card.frontImagePathArray = exported.frontImages.compactMap { base64 in
            guard let data = Data(base64Encoded: base64),
                  let filename = CDCard.saveImageToFile(data: data) else { return nil }
            return filename
        }
        card.backImagePathArray = exported.backImages.compactMap { base64 in
            guard let data = Data(base64Encoded: base64),
                  let filename = CDCard.saveImageToFile(data: data) else { return nil }
            return filename
        }
        
        // Audio
        card.frontAudioPathArray = exported.frontAudios.compactMap { base64 in
            guard let data = Data(base64Encoded: base64) else { return nil }
            let filename = UUID().uuidString + ".m4a"
            let url = CDCard.documentsDirectory.appendingPathComponent(filename)
            guard (try? data.write(to: url)) != nil else { return nil }
            return filename
        }
        card.backAudioPathArray = exported.backAudios.compactMap { base64 in
            guard let data = Data(base64Encoded: base64) else { return nil }
            let filename = UUID().uuidString + ".m4a"
            let url = CDCard.documentsDirectory.appendingPathComponent(filename)
            guard (try? data.write(to: url)) != nil else { return nil }
            return filename
        }
    }
    
    // MARK: - Private: CSV Helpers
    
    private func escapeCSV(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\"", with: "\"\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: "")
        return "\"\(escaped)\""
    }
    
    private func parseCSV(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = content.startIndex
        
        while i < content.endIndex {
            let char = content[i]
            
            if inQuotes {
                if char == "\"" {
                    let next = content.index(after: i)
                    if next < content.endIndex && content[next] == "\"" {
                        currentField.append("\"")
                        i = content.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == "," {
                    currentRow.append(currentField)
                    currentField = ""
                } else if char == "\n" || char == "\r" {
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    if char == "\r" {
                        let next = content.index(after: i)
                        if next < content.endIndex && content[next] == "\n" {
                            i = next
                        }
                    }
                } else {
                    currentField.append(char)
                }
            }
            
            i = content.index(after: i)
        }
        
        currentRow.append(currentField)
        if !currentRow.allSatisfy({ $0.isEmpty }) {
            rows.append(currentRow)
        }
        
        return rows
    }
}

// MARK: - Import Errors

enum ImportError: LocalizedError {
    case invalidFormat
    case emptyFile
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "The file format is not recognized."
        case .emptyFile: return "The file contains no importable data."
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Document Picker for Import

struct DocumentImportPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [.json, .commaSeparatedText]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        
        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
