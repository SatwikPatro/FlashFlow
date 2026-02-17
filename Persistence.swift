import CoreData
import UIKit

// MARK: - Persistence Controller
class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init() {
        // Build the model programmatically
        let model = NSManagedObjectModel()
        
        // Category Entity
        let categoryEntity = NSEntityDescription()
        categoryEntity.name = "CDCategory"
        categoryEntity.managedObjectClassName = NSStringFromClass(CDCategory.self)
        
        let catId = NSAttributeDescription()
        catId.name = "id"
        catId.attributeType = .stringAttributeType
        
        let catName = NSAttributeDescription()
        catName.name = "name"
        catName.attributeType = .stringAttributeType
        
        let catIcon = NSAttributeDescription()
        catIcon.name = "icon"
        catIcon.attributeType = .stringAttributeType
        catIcon.defaultValue = "folder"
        
        let catColor = NSAttributeDescription()
        catColor.name = "colorHex"
        catColor.attributeType = .stringAttributeType
        catColor.defaultValue = "#6366F1"
        
        let catCreated = NSAttributeDescription()
        catCreated.name = "createdAt"
        catCreated.attributeType = .dateAttributeType
        
        categoryEntity.properties = [catId, catName, catIcon, catColor, catCreated]
        
        // Category -> Subcategories (self-referencing)
        let catSubcategories = NSRelationshipDescription()
        catSubcategories.name = "subcategories"
        catSubcategories.destinationEntity = categoryEntity
        catSubcategories.maxCount = 0
        catSubcategories.deleteRule = .cascadeDeleteRule
        
        let catParent = NSRelationshipDescription()
        catParent.name = "parentCategory"
        catParent.destinationEntity = categoryEntity
        catParent.maxCount = 1
        catParent.isOptional = true
        
        catSubcategories.inverseRelationship = catParent
        catParent.inverseRelationship = catSubcategories
        
        categoryEntity.properties.append(contentsOf: [catSubcategories, catParent])
        
        // Deck Entity
        let deckEntity = NSEntityDescription()
        deckEntity.name = "CDDeck"
        deckEntity.managedObjectClassName = NSStringFromClass(CDDeck.self)
        
        let deckId = NSAttributeDescription()
        deckId.name = "id"
        deckId.attributeType = .stringAttributeType
        
        let deckName = NSAttributeDescription()
        deckName.name = "name"
        deckName.attributeType = .stringAttributeType
        
        let deckIcon = NSAttributeDescription()
        deckIcon.name = "icon"
        deckIcon.attributeType = .stringAttributeType
        deckIcon.defaultValue = "rectangle.stack"
        
        let deckColor = NSAttributeDescription()
        deckColor.name = "colorHex"
        deckColor.attributeType = .stringAttributeType
        deckColor.defaultValue = "#6366F1"
        
        let deckCreated = NSAttributeDescription()
        deckCreated.name = "createdAt"
        deckCreated.attributeType = .dateAttributeType
        
        deckEntity.properties = [deckId, deckName, deckIcon, deckColor, deckCreated]
        
        // Card Entity
        let cardEntity = NSEntityDescription()
        cardEntity.name = "CDCard"
        cardEntity.managedObjectClassName = NSStringFromClass(CDCard.self)
        
        let cardId = NSAttributeDescription()
        cardId.name = "id"
        cardId.attributeType = .stringAttributeType
        
        let cardFront = NSAttributeDescription()
        cardFront.name = "frontText"
        cardFront.attributeType = .stringAttributeType
        cardFront.defaultValue = ""

        let cardFrontRTF = NSAttributeDescription()
        cardFrontRTF.name = "frontRTFData"
        cardFrontRTF.attributeType = .binaryDataAttributeType
        cardFrontRTF.isOptional = true

        let cardBack = NSAttributeDescription()
        cardBack.name = "backText"
        cardBack.attributeType = .stringAttributeType
        cardBack.defaultValue = ""

        let cardBackRTF = NSAttributeDescription()
        cardBackRTF.name = "backRTFData"
        cardBackRTF.attributeType = .binaryDataAttributeType
        cardBackRTF.isOptional = true

        // Legacy single-item fields (kept for backward compatibility / migration)
        let cardFrontImage = NSAttributeDescription()
        cardFrontImage.name = "frontImageData"
        cardFrontImage.attributeType = .binaryDataAttributeType
        cardFrontImage.isOptional = true

        let cardBackImage = NSAttributeDescription()
        cardBackImage.name = "backImageData"
        cardBackImage.attributeType = .binaryDataAttributeType
        cardBackImage.isOptional = true

        let cardFrontAudio = NSAttributeDescription()
        cardFrontAudio.name = "frontAudioPath"
        cardFrontAudio.attributeType = .stringAttributeType
        cardFrontAudio.isOptional = true

        let cardBackAudio = NSAttributeDescription()
        cardBackAudio.name = "backAudioPath"
        cardBackAudio.attributeType = .stringAttributeType
        cardBackAudio.isOptional = true

        // New multi-item fields (JSON arrays of file paths)
        let cardFrontImagePaths = NSAttributeDescription()
        cardFrontImagePaths.name = "frontImagePaths"
        cardFrontImagePaths.attributeType = .stringAttributeType
        cardFrontImagePaths.isOptional = true
        cardFrontImagePaths.defaultValue = "[]"

        let cardBackImagePaths = NSAttributeDescription()
        cardBackImagePaths.name = "backImagePaths"
        cardBackImagePaths.attributeType = .stringAttributeType
        cardBackImagePaths.isOptional = true
        cardBackImagePaths.defaultValue = "[]"

        let cardFrontAudioPaths = NSAttributeDescription()
        cardFrontAudioPaths.name = "frontAudioPathsJSON"
        cardFrontAudioPaths.attributeType = .stringAttributeType
        cardFrontAudioPaths.isOptional = true
        cardFrontAudioPaths.defaultValue = "[]"

        let cardBackAudioPaths = NSAttributeDescription()
        cardBackAudioPaths.name = "backAudioPathsJSON"
        cardBackAudioPaths.attributeType = .stringAttributeType
        cardBackAudioPaths.isOptional = true
        cardBackAudioPaths.defaultValue = "[]"
        
        let cardCreated = NSAttributeDescription()
        cardCreated.name = "createdAt"
        cardCreated.attributeType = .dateAttributeType
        
        let cardLinks = NSAttributeDescription()
        cardLinks.name = "linkedCardIDs"
        cardLinks.attributeType = .stringAttributeType
        cardLinks.isOptional = true
        cardLinks.defaultValue = ""
        
        cardEntity.properties = [cardId, cardFront, cardFrontRTF, cardBack, cardBackRTF, cardFrontImage, cardBackImage, cardFrontAudio, cardBackAudio, cardFrontImagePaths, cardBackImagePaths, cardFrontAudioPaths, cardBackAudioPaths, cardCreated, cardLinks]
        
        // Relationships
        // Category -> Decks
        let catDecks = NSRelationshipDescription()
        catDecks.name = "decks"
        catDecks.destinationEntity = deckEntity
        catDecks.maxCount = 0
        catDecks.deleteRule = .cascadeDeleteRule
        
        let deckCategory = NSRelationshipDescription()
        deckCategory.name = "category"
        deckCategory.destinationEntity = categoryEntity
        deckCategory.maxCount = 1
        deckCategory.isOptional = true
        
        catDecks.inverseRelationship = deckCategory
        deckCategory.inverseRelationship = catDecks
        
        // Deck -> Cards
        let deckCards = NSRelationshipDescription()
        deckCards.name = "cards"
        deckCards.destinationEntity = cardEntity
        deckCards.maxCount = 0
        deckCards.deleteRule = .cascadeDeleteRule
        
        let cardDeck = NSRelationshipDescription()
        cardDeck.name = "deck"
        cardDeck.destinationEntity = deckEntity
        cardDeck.maxCount = 1
        cardDeck.isOptional = true
        
        deckCards.inverseRelationship = cardDeck
        cardDeck.inverseRelationship = deckCards
        
        categoryEntity.properties.append(contentsOf: [catDecks])
        deckEntity.properties.append(contentsOf: [deckCategory, deckCards])
        cardEntity.properties.append(contentsOf: [cardDeck])
        
        model.entities = [categoryEntity, deckEntity, cardEntity]
        
        // Create container with the programmatic model
        container = NSPersistentContainer(name: "FlashFlowModel", managedObjectModel: model)
        
        // Enable lightweight migration for schema changes (new optional attributes)
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data failed: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}

// MARK: - Category Entity
@objc(CDCategory)
public class CDCategory: NSManagedObject, Identifiable {
    @NSManaged public var id: String
    @NSManaged public var name: String
    @NSManaged public var icon: String
    @NSManaged public var colorHex: String
    @NSManaged public var createdAt: Date
    @NSManaged public var decks: NSSet?
    @NSManaged public var parentCategory: CDCategory?
    @NSManaged public var subcategories: NSSet?
    
    func getSortedDecks() -> [CDDeck] {
        (decks?.allObjects as? [CDDeck])?.sorted { $0.createdAt < $1.createdAt } ?? []
    }
    
    func getSortedSubcategories() -> [CDCategory] {
        (subcategories?.allObjects as? [CDCategory])?.sorted { $0.createdAt < $1.createdAt } ?? []
    }
    
    func getTotalCardCount() -> Int {
        let deckCards = getSortedDecks().reduce(0) { $0 + ($1.cards?.count ?? 0) }
        let subCards = getSortedSubcategories().reduce(0) { $0 + $1.getTotalCardCount() }
        return deckCards + subCards
    }
    
    /// Build breadcrumb path: "Root > Parent > This"
    /// Check if a name already exists among sibling categories and decks at this level
    func hasDuplicateName(_ candidateName: String, excludingCategoryID: String? = nil, excludingDeckID: String? = nil) -> Bool {
        let trimmed = candidateName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let siblingCats = getSortedSubcategories().filter { $0.id != (excludingCategoryID ?? "") }
        let siblingDecks = getSortedDecks().filter { $0.id != (excludingDeckID ?? "") }
        return siblingCats.contains { $0.name.lowercased() == trimmed } ||
               siblingDecks.contains { $0.name.lowercased() == trimmed }
    }
}

// MARK: - Deck Entity
@objc(CDDeck)
public class CDDeck: NSManagedObject, Identifiable {
    @NSManaged public var id: String
    @NSManaged public var name: String
    @NSManaged public var icon: String
    @NSManaged public var colorHex: String
    @NSManaged public var createdAt: Date
    @NSManaged public var category: CDCategory?
    @NSManaged public var cards: NSSet?
    
    func getSortedCards() -> [CDCard] {
        (cards?.allObjects as? [CDCard])?.sorted { $0.createdAt < $1.createdAt } ?? []
    }
    
    /// Build breadcrumb: "Root > Parent > Deck"
    func getBreadcrumbPath() -> String {
        var parts: [String] = [name]
        var current = category
        while let cat = current {
            parts.insert(cat.name, at: 0)
            current = cat.parentCategory
        }
        return parts.joined(separator: " › ")
    }
}

// MARK: - Card Entity
@objc(CDCard)
public class CDCard: NSManagedObject, Identifiable {
    @NSManaged public var id: String
    @NSManaged public var frontText: String
    @NSManaged public var frontRTFData: Data?
    @NSManaged public var backText: String
    @NSManaged public var backRTFData: Data?
    // Legacy single fields (kept for backward compat)
    @NSManaged public var frontImageData: Data?
    @NSManaged public var backImageData: Data?
    @NSManaged public var frontAudioPath: String?
    @NSManaged public var backAudioPath: String?
    // New multi-item JSON fields
    @NSManaged public var frontImagePaths: String?
    @NSManaged public var backImagePaths: String?
    @NSManaged public var frontAudioPathsJSON: String?
    @NSManaged public var backAudioPathsJSON: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var linkedCardIDs: String?
    @NSManaged public var deck: CDDeck?
    
    // Helper to get linked card IDs as array
    var linkedCards: [String] {
        get {
            guard let data = linkedCardIDs?.data(using: .utf8),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return ids
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let string = String(data: data, encoding: .utf8) {
                linkedCardIDs = string
            }
        }
    }
    
    // MARK: - Multi-Image Helpers
    
    /// Get front image file paths as array, with backward compat migration
    var frontImagePathArray: [String] {
        get {
            if let json = frontImagePaths, let paths = Self.decodePaths(json), !paths.isEmpty {
                return paths
            }
            // Backward compat: migrate legacy binary data to file
            if let data = frontImageData {
                let path = Self.saveImageToFile(data: data)
                if let path = path {
                    frontImagePaths = Self.encodePaths([path])
                    frontImageData = nil // Clear legacy
                    return [path]
                }
            }
            return []
        }
        set {
            frontImagePaths = Self.encodePaths(newValue)
        }
    }
    
    var backImagePathArray: [String] {
        get {
            if let json = backImagePaths, let paths = Self.decodePaths(json), !paths.isEmpty {
                return paths
            }
            if let data = backImageData {
                let path = Self.saveImageToFile(data: data)
                if let path = path {
                    backImagePaths = Self.encodePaths([path])
                    backImageData = nil
                    return [path]
                }
            }
            return []
        }
        set {
            backImagePaths = Self.encodePaths(newValue)
        }
    }
    
    /// Get front audio file paths as array, with backward compat
    var frontAudioPathArray: [String] {
        get {
            if let json = frontAudioPathsJSON, let paths = Self.decodePaths(json), !paths.isEmpty {
                return paths
            }
            if let path = frontAudioPath, !path.isEmpty {
                frontAudioPathsJSON = Self.encodePaths([path])
                frontAudioPath = nil
                return [path]
            }
            return []
        }
        set {
            frontAudioPathsJSON = Self.encodePaths(newValue)
        }
    }
    
    var backAudioPathArray: [String] {
        get {
            if let json = backAudioPathsJSON, let paths = Self.decodePaths(json), !paths.isEmpty {
                return paths
            }
            if let path = backAudioPath, !path.isEmpty {
                backAudioPathsJSON = Self.encodePaths([path])
                backAudioPath = nil
                return [path]
            }
            return []
        }
        set {
            backAudioPathsJSON = Self.encodePaths(newValue)
        }
    }
    
    // MARK: - Static Helpers
    
    /// Documents directory URL
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    static func encodePaths(_ paths: [String]) -> String {
        (try? JSONEncoder().encode(paths)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
    
    static func decodePaths(_ json: String) -> [String]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }
    
    /// Resolve a stored filename (or legacy full path) to the current Documents directory path
    static func resolvedPath(for storedPath: String) -> String {
        // If it's just a filename (no slashes), resolve against Documents dir
        if !storedPath.contains("/") {
            return documentsDirectory.appendingPathComponent(storedPath).path
        }
        // Legacy full path — extract the filename and resolve
        let filename = (storedPath as NSString).lastPathComponent
        let resolved = documentsDirectory.appendingPathComponent(filename).path
        // If the legacy path still works, use it; otherwise try resolved
        if FileManager.default.fileExists(atPath: storedPath) {
            return storedPath
        }
        return resolved
    }
    
    /// Save image data to Documents directory and return just the FILENAME
    static func saveImageToFile(data: Data, quality: CGFloat = 0.8) -> String? {
        let filename = UUID().uuidString + ".jpg"
        let url = documentsDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return filename  // Store only filename, not full path
        } catch {
            print("Failed to save image file: \(error)")
            return nil
        }
    }
    
    /// Save UIImage to Documents directory and return just the FILENAME
    static func saveImageToFile(image: UIImage, quality: CGFloat = 0.8) -> String? {
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        return saveImageToFile(data: data, quality: quality)
    }
    
    /// Load UIImage from a stored path (filename or legacy full path)
    static func loadImage(from storedPath: String) -> UIImage? {
        let path = resolvedPath(for: storedPath)
        return UIImage(contentsOfFile: path)
    }
    
    /// Delete media files for this card (call before deleting the card)
    func deleteMediaFiles() {
        let fm = FileManager.default
        for storedPath in frontImagePathArray + backImagePathArray + frontAudioPathArray + backAudioPathArray {
            let path = Self.resolvedPath(for: storedPath)
            try? fm.removeItem(atPath: path)
        }
    }
}
