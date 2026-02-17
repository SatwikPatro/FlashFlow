import SwiftUI
import CoreData
import AVFoundation
import Translation
import NaturalLanguage
import Combine

struct StudyModeView: View {
    let deck: CDDeck
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest var cards: FetchedResults<CDCard>
    
    @State private var currentIndex = 0
    @State private var showingBack = false
    @State private var shuffledIndices: [Int] = []
    @State private var isShuffled = false
    @State private var selectedLinkedCard: CDCard?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var showTranslation = false
    @State private var textToTranslate = ""
    @StateObject private var speechHelper = SpeechHelper()
    
    init(deck: CDDeck) {
        self.deck = deck
        let request = NSFetchRequest<CDCard>(entityName: "CDCard")
        request.predicate = NSPredicate(format: "deck == %@", deck)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        self._cards = FetchRequest(fetchRequest: request)
    }
    
    var currentCard: CDCard? {
        guard !cards.isEmpty else { return nil }
        let index = isShuffled ? shuffledIndices[currentIndex] : currentIndex
        return cards[index]
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("\(currentIndex + 1) / \(cards.count)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: { toggleShuffle() }) {
                        Image(systemName: isShuffled ? "shuffle.circle.fill" : "shuffle.circle")
                            .font(.system(size: 20))
                            .foregroundColor(isShuffled ? Color(hexString: deck.colorHex) : .primary)
                            .frame(width: 44, height: 44)
                    }
                    
                    Button(action: {
                        if let card = currentCard {
                            let text = loadAttributedText(card: card, isBack: showingBack).string
                            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                speechHelper.toggleSpeech(text)
                            }
                        }
                    }) {
                        Image(systemName: speechHelper.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .font(.system(size: 18))
                            .foregroundColor(speechHelper.isSpeaking ? .blue : .primary)
                            .frame(width: 44, height: 44)
                    }
                    
                    Button(action: {
                        if let card = currentCard {
                            let text = loadAttributedText(card: card, isBack: showingBack).string
                            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                textToTranslate = text
                                showTranslation = true
                            }
                        }
                    }) {
                        Image(systemName: "translate")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                
                // Card content
                if let card = currentCard {
                    ZStack(alignment: .bottom) {
                        // Main scrollable content
                        ZStack {
                            Color(UIColor.secondarySystemBackground)
                            
                            ScrollView {
                                VStack(spacing: 0) {
                                    // Fixed header at top with FRONT/BACK label
                                    VStack(spacing: 30) {
                                        Text(showingBack ? "BACK" : "FRONT")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.secondary)
                                            .tracking(1)
                                            .padding(.top, 30)
                                        
                                        // Text content with links
                                        AttributedTextDisplay(
                                            attributedText: loadAttributedText(card: card, isBack: showingBack),
                                            onLinkTap: { url in
                                                handleLinkTap(url)
                                            }
                                        )
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 20)
                                        
                                        // Images (all of them)
                                        let imagePaths = showingBack ? card.backImagePathArray : card.frontImagePathArray
                                        ForEach(Array(imagePaths.enumerated()), id: \.offset) { _, path in
                                            if let image = CDCard.loadImage(from: path) {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(maxWidth: 400)
                                                    .frame(maxHeight: 300)
                                                    .cornerRadius(12)
                                                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                                                    .padding(.horizontal, 40)
                                                    .padding(.top, 20)
                                            }
                                        }
                                        
                                        // Audio players (all of them)
                                        let audioPaths = showingBack ? card.backAudioPathArray : card.frontAudioPathArray
                                        ForEach(Array(audioPaths.enumerated()), id: \.offset) { index, audioPath in
                                            Button(action: { playAudio(path: audioPath) }) {
                                                HStack(spacing: 12) {
                                                    Image(systemName: "play.circle.fill")
                                                        .font(.system(size: 28))
                                                    Text(audioPaths.count == 1 ? "Play Audio" : "Play Audio \(index + 1)")
                                                        .font(.system(size: 16, weight: .semibold))
                                                }
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 16)
                                                .background(Color(hexString: deck.colorHex))
                                                .cornerRadius(12)
                                            }
                                            .padding(.horizontal, 40)
                                            .padding(.top, 20)
                                        }
                                    }
                                    
                                    // Bottom padding to ensure content doesn't hide behind hint
                                    Spacer()
                                        .frame(height: 100)
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                        
                        // Fixed hint overlay at bottom - NOT inside ScrollView
                        if !showingBack {
                            VStack(spacing: 0) {
                                // Gradient fade from transparent to opaque
                                LinearGradient(
                                    colors: [
                                        Color(UIColor.secondarySystemBackground).opacity(0),
                                        Color(UIColor.secondarySystemBackground)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 60)
                                
                                // Solid opaque section with hint content
                                VStack(spacing: 8) {
                                    Image(systemName: "hand.tap.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.secondary.opacity(0.5))
                                    Text("Tap card to reveal answer")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.bottom, 20)
                                .frame(maxWidth: .infinity)
                                .background(Color(UIColor.secondarySystemBackground))
                            }
                        }
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showingBack.toggle()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 2)
                    .padding(.horizontal, 20)
                }
                
                // Bottom navigation
                HStack(spacing: 40) {
                    Button(action: { previousCard() }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(currentIndex > 0 ? Color(hexString: deck.colorHex) : .gray)
                    }
                    .disabled(currentIndex == 0)
                    
                    Spacer()
                    
                    Button(action: { nextCard() }) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(currentIndex < cards.count - 1 ? Color(hexString: deck.colorHex) : .gray)
                    }
                    .disabled(currentIndex >= cards.count - 1)
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
        }
        .sheet(item: $selectedLinkedCard) { linkedCard in
            LinkedCardDetailView(card: linkedCard)
        }
        .translationPresentation(isPresented: $showTranslation, text: textToTranslate)
    }
    
    private func loadAttributedText(card: CDCard, isBack: Bool) -> NSAttributedString {
        if isBack, let rtfData = card.backRTFData,
           let attrString = try? NSMutableAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            fixColorsForCurrentMode(attrString)
            return attrString
        } else if !isBack, let rtfData = card.frontRTFData,
                  let attrString = try? NSMutableAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            fixColorsForCurrentMode(attrString)
            return attrString
        }
        
        return NSAttributedString(string: isBack ? card.backText : card.frontText, attributes: [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 18)
        ])
    }
    
    /// RTF stores hardcoded color values (e.g. black text) which become invisible in dark mode.
    /// This replaces non-link text colors with the current label color so text is always visible.
    private func fixColorsForCurrentMode(_ attrString: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attrString.length)
        attrString.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            // Don't change link colors — those are handled by linkTextAttributes
            if attrString.attribute(.link, at: range.location, effectiveRange: nil) == nil {
                attrString.addAttribute(.foregroundColor, value: UIColor.label, range: range)
            }
        }
    }
    
    private func handleLinkTap(_ url: URL) {
        guard url.scheme == "card", let cardID = url.host else { return }
        
        // Search all cards (not just current deck) for the linked card
        let request = NSFetchRequest<CDCard>(entityName: "CDCard")
        request.predicate = NSPredicate(format: "id == %@", cardID)
        request.fetchLimit = 1
        if let linkedCard = try? viewContext.fetch(request).first {
            selectedLinkedCard = linkedCard
        }
    }
    
    private func playAudio(path: String) {
        let resolved = CDCard.resolvedPath(for: path)
        let url = URL(fileURLWithPath: resolved)
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Failed to play audio")
        }
    }
    
    private func nextCard() {
        speechHelper.stop()
        if currentIndex < cards.count - 1 {
            currentIndex += 1
            showingBack = false
        }
    }
    
    private func previousCard() {
        speechHelper.stop()
        if currentIndex > 0 {
            currentIndex -= 1
            showingBack = false
        }
    }
    
    private func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled {
            shuffledIndices = Array(0..<cards.count).shuffled()
            currentIndex = 0
            showingBack = false
        } else {
            currentIndex = 0
            showingBack = false
        }
    }
}

// MARK: - Attributed Text Display with Link Support
struct AttributedTextDisplay: UIViewRepresentable {
    let attributedText: NSAttributedString
    let onLinkTap: (URL) -> Void
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 18)
        textView.textAlignment = .left
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.dataDetectorTypes = []
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = attributedText
        // Force layout so the text view reports correct intrinsic size
        uiView.invalidateIntrinsicContentSize()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTap: onLinkTap)
    }
    
    // Use sizeThatFits to tell SwiftUI the correct height
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: fittingSize.height)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        let onLinkTap: (URL) -> Void
        
        init(onLinkTap: @escaping (URL) -> Void) {
            self.onLinkTap = onLinkTap
        }
        
        @available(iOS 17.0, *)
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            if case .link(let url) = textItem.content {
                return UIAction { [weak self] _ in
                    self?.onLinkTap(url)
                }
            }
            return defaultAction
        }
        
        // Fallback for iOS 16 and below
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange) -> Bool {
            onLinkTap(URL)
            return false
        }
    }
}

// MARK: - Linked Card Detail View
struct LinkedCardDetailView: View {
    let card: CDCard
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Front
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FRONT")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(card.frontText)
                            .font(.body)
                        
                        ForEach(Array(card.frontImagePathArray.enumerated()), id: \.offset) { _, path in
                            if let image = CDCard.loadImage(from: path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(8)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Back
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BACK")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(card.backText)
                            .font(.body)
                        
                        ForEach(Array(card.backImagePathArray.enumerated()), id: \.offset) { _, path in
                            if let image = CDCard.loadImage(from: path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Linked Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
