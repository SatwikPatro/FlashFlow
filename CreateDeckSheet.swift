import SwiftUI
import CoreData

struct CreateDeckSheet: View {
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
    
    init(parentCategory: CDCategory? = nil) {
        self.parentCategory = parentCategory
    }
    
    let icons = ["folder", "book", "graduationcap", "lightbulb", "atom", "brain"]
    
    var allColors: [String] {
        FlashFlowTheme.deckColors + customColors
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("DECK NAME")) {
                    TextField("Enter name", text: $name)
                }
                
                Section(header: Text("ICON")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            // System icons
                            ForEach(icons, id: \.self) { icon in
                                IconButton(
                                    icon: icon,
                                    isEmoji: false,
                                    isSelected: selectedIcon == icon,
                                    color: selectedColor
                                ) {
                                    selectedIcon = icon
                                }
                            }
                            
                            // Browse more icons button
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
                            // Preset colors
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
                            
                            // Custom colors with delete option
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
                            
                            // Custom color picker button
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
            .navigationTitle("New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") { createDeck() }
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
        // If the deleted color was selected, switch to default
        if selectedColor == color {
            selectedColor = FlashFlowTheme.deckColors[0]
        }
    }
    
    private func createDeck() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for duplicates
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
        
        let deck = CDDeck(context: viewContext)
        deck.id = UUID().uuidString
        deck.name = trimmed
        deck.icon = selectedIcon
        deck.colorHex = selectedColor
        deck.createdAt = Date()
        deck.category = parentCategory
        
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

// MARK: - Icon Button
struct IconButton: View {
    let icon: String
    let isEmoji: Bool
    let isSelected: Bool
    let color: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hexString: color).opacity(isSelected ? 0.3 : 0.1))
                        .frame(width: 60, height: 60)
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hexString: color), lineWidth: 3)
                            .frame(width: 60, height: 60)
                    }
                    
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(Color(hexString: color))
                }
                Text(icon.capitalized)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
    }
}

// MARK: - Color Button
struct ColorButton: View {
    let color: String
    let name: String
    let isSelected: Bool
    let showDelete: Bool
    let action: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Main color circle button
                Button(action: action) {
                    ZStack {
                        Circle()
                            .fill(Color(hexString: color))
                            .frame(width: 50, height: 50)
                        
                        if isSelected {
                            Circle()
                                .stroke(Color.primary, lineWidth: 3)
                                .frame(width: 50, height: 50)
                        }
                    }
                }
                
                // Delete button overlay for custom colors
                if showDelete {
                    Button(action: onDelete) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 20, height: 20)
                            
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 20))
                        }
                    }
                    .offset(x: 10, y: -10)
                }
            }
            .frame(width: 60, height: 60) // Extra space for delete button
            
            Text(name)
                .font(.caption)
                .foregroundColor(Color(hexString: color))
        }
    }
}

// MARK: - Custom Color Picker View
struct CustomColorPickerView: View {
    @Binding var customColors: [String]
    @Binding var selectedColor: String
    @Binding var isPresented: Bool
    
    @State private var pickedColor: Color = .blue
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview of selected color
                RoundedRectangle(cornerRadius: 16)
                    .fill(pickedColor)
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal)
                
                // SwiftUI ColorPicker
                ColorPicker("Select a color", selection: $pickedColor, supportsOpacity: false)
                    .labelsHidden()
                    .scaleEffect(1.5)
                    .frame(width: 60, height: 60)
                
                Text("Tap the circle above to pick a color")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Custom Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let hexColor = pickedColor.toHex()
                        if !customColors.contains(hexColor) {
                            customColors.append(hexColor)
                        }
                        selectedColor = hexColor
                        isPresented = false
                    }
                }
            }
            .onAppear {
                pickedColor = Color(hexString: selectedColor)
            }
        }
        .interactiveDismissDisabled()
    }
}

extension Color {
    func toHex() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

// MARK: - SF Symbol Picker View
struct SFSymbolPickerView: View {
    @Binding var selectedIcon: String
    @Binding var isPresented: Bool
    
    let symbols = [
        // Education
        "book", "book.fill", "books.vertical", "graduationcap", "pencil", "pencil.circle",
        "pencil.and.outline", "note.text", "doc.text", "newspaper",
        
        // Science
        "atom", "brain", "brain.head.profile", "eyeglasses", "cube", "cube.fill",
        "flask", "testtube.2", "bolt", "bolt.fill",
        
        // Nature
        "leaf", "leaf.fill", "tree", "globe", "globe.americas", "moon",
        "sun.max", "sun.max.fill", "cloud", "cloud.fill",
        
        // Symbols
        "star", "star.fill", "heart", "heart.fill", "flag", "flag.fill",
        "bell", "bell.fill", "tag", "tag.fill",
        
        // Objects
        "folder", "folder.fill", "tray", "tray.fill", "archivebox", "archivebox.fill",
        "paperplane", "paperplane.fill", "envelope", "envelope.fill",
        
        // Tech
        "lightbulb", "lightbulb.fill", "cpu", "memorychip", "display", "keyboard",
        "printer", "scanner", "headphones", "mic",
        
        // Activities
        "figure.walk", "sportscourt", "dumbbell", "trophy", "trophy.fill", "medal",
        "paintbrush", "paintbrush.fill", "camera", "camera.fill",
        
        // Transport
        "car", "car.fill", "bicycle", "airplane", "airplane.circle", "ferry",
        "train.side.front.car", "bus", "skateboard", "tent",
        
        // Food
        "fork.knife", "cup.and.saucer", "birthday.cake", "carrot", "apple.logo", "cart",
        
        // Shapes
        "circle", "circle.fill", "square", "square.fill", "triangle", "triangle.fill",
        "hexagon", "hexagon.fill", "diamond", "diamond.fill"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 16) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button(action: {
                            selectedIcon = symbol
                            isPresented = false
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: symbol)
                                    .font(.system(size: 30))
                                    .foregroundColor(selectedIcon == symbol ? .blue : .primary)
                                    .frame(width: 60, height: 60)
                                    .background(selectedIcon == symbol ? Color.blue.opacity(0.1) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}
