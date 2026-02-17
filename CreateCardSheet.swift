import SwiftUI
import CoreData
import PhotosUI
import AVFoundation
import PencilKit
import VisionKit
import Vision
import Translation
import NaturalLanguage
import Combine

struct CreateCardSheet: View {
    let deck: CDDeck
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var frontText = NSMutableAttributedString(string: "")
    @State private var backText = NSMutableAttributedString(string: "")
    @State private var selectedSide: CardSide = .front
    @State private var selectedRange = NSRange(location: 0, length: 0)
    
    // Multiple media arrays
    @State private var frontImages: [UIImage] = []
    @State private var backImages: [UIImage] = []
    @State private var frontAudioPaths: [String] = []
    @State private var backAudioPaths: [String] = []
    
    // Recording
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    
    // Pickers
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var showDrawing = false
    @State private var showAudioImporter = false
    @State private var showCardLinkPicker = false
    @State private var pendingLinkedCard: CDCard?
    @State private var showScanner = false
    @State private var showScanImagePicker = false
    @State private var pendingScannedText: String?
    @State private var showTranslation = false
    @State private var textToTranslate = ""
    @StateObject private var speechHelper = SpeechHelper()
    
    enum CardSide: String, CaseIterable {
        case front = "Front"
        case back = "Back"
    }
    
    var currentText: Binding<NSMutableAttributedString> {
        Binding(
            get: {
                selectedSide == .front ? frontText : backText
            },
            set: { newValue in
                if selectedSide == .front {
                    frontText = NSMutableAttributedString(attributedString: newValue)
                } else {
                    backText = NSMutableAttributedString(attributedString: newValue)
                }
            }
        )
    }
    
    var currentImages: [UIImage] {
        selectedSide == .front ? frontImages : backImages
    }
    
    var currentAudioPaths: [String] {
        selectedSide == .front ? frontAudioPaths : backAudioPaths
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Side picker
                Picker("Side", selection: $selectedSide) {
                    ForEach(CardSide.allCases, id: \.self) { side in
                        Text(side.rawValue).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                Form {
                    // Rich Text Editor
                    Section(header:
                        HStack {
                            Text("TEXT")
                            Spacer()
                            Button(action: {
                                let text = currentText.wrappedValue.string
                                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                speechHelper.toggleSpeech(text)
                            }) {
                                Image(systemName: speechHelper.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                                    .foregroundColor(speechHelper.isSpeaking ? .blue : .secondary)
                                    .font(.system(size: 14))
                            }
                        }
                    ) {
                        AttributedTextEditor(
                            attributedText: currentText,
                            selectedRange: $selectedRange,
                            onScanDocument: { showScanner = true },
                            onScanPhoto: { showScanImagePicker = true },
                            onTranslate: {
                                textToTranslate = currentText.wrappedValue.string
                                showTranslation = true
                            },
                            onCardLink: { showCardLinkPicker = true }
                        )
                        .frame(minHeight: 150)
                        .id(selectedSide)
                    }
                    
                    // Images
                    Section(header: Text("IMAGES (\(currentImages.count))")) {
                        ForEach(Array(currentImages.enumerated()), id: \.offset) { index, image in
                            HStack {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                Text("Image \(index + 1)")
                                
                                Spacer()
                                
                                Button(role: .destructive, action: { removeImage(at: index) }) {
                                    Image(systemName: "trash.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        Button(action: { showCamera = true }) {
                            Label("Take Photo", systemImage: "camera")
                        }
                        
                        Button(action: { showImagePicker = true }) {
                            Label("Choose from Library", systemImage: "photo")
                        }
                        
                        Button(action: { showDrawing = true }) {
                            Label("Draw Image", systemImage: "pencil.tip.crop.circle")
                        }
                    }
                    
                    // Audio
                    Section(header: Text("AUDIO (\(currentAudioPaths.count))")) {
                        ForEach(Array(currentAudioPaths.enumerated()), id: \.offset) { index, path in
                            HStack {
                                Button(action: { playAudio(path) }) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.borderless)
                                
                                Text("Recording \(index + 1)")
                                
                                Spacer()
                                
                                Button(role: .destructive, action: { removeAudio(at: index) }) {
                                    Image(systemName: "trash.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        
                        if isRecording {
                            HStack {
                                Image(systemName: "waveform")
                                    .foregroundColor(.red)
                                Text("Recording: \(formatTime(recordingTime))")
                                    .foregroundColor(.red)
                                    .monospacedDigit()
                                Spacer()
                                Button("Stop") { stopRecording() }
                                    .foregroundColor(.red)
                            }
                        } else {
                            Button(action: { startRecording() }) {
                                Label("Record Audio", systemImage: "mic")
                            }
                            
                            Button(action: { showAudioImporter = true }) {
                                Label("Import Audio", systemImage: "arrow.down.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { saveCard() }
                        .disabled(frontText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera) { image in
                    addImage(image)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(sourceType: .photoLibrary) { image in
                    addImage(image)
                }
            }
            .sheet(isPresented: $showDrawing) {
                DrawingView { image in
                    addImage(image)
                }
            }
            .sheet(isPresented: $showCardLinkPicker, onDismiss: {
                if let card = pendingLinkedCard {
                    insertCardLink(card)
                    pendingLinkedCard = nil
                }
            }) {
                CardLinkPickerView(
                    deck: deck,
                    excludeCardID: nil
                ) { linkedCard in
                    pendingLinkedCard = linkedCard
                }
            }
            .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio]) { result in
                handleAudioImport(result)
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView { scannedText in
                    pendingScannedText = scannedText
                }
            }
            .sheet(isPresented: $showScanImagePicker) {
                ImagePicker(sourceType: .photoLibrary) { image in
                    ocrFromImage(image)
                }
            }
            .sheet(item: Binding(
                get: { pendingScannedText.map { IdentifiableString(value: $0) } },
                set: { if $0 == nil { pendingScannedText = nil } }
            )) { item in
                ScannedTextReviewSheet(scannedText: item.value) { finalText in
                    insertScannedText(finalText)
                    pendingScannedText = nil
                }
            }
            .translationPresentation(isPresented: $showTranslation, text: textToTranslate) { translatedText in
                let translated = NSMutableAttributedString(string: translatedText, attributes: [
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: UIColor.label
                ])
                currentText.wrappedValue = translated
            }
        }
    }
    
    // MARK: - Image Management
    
    private func addImage(_ image: UIImage) {
        if selectedSide == .front {
            frontImages.append(image)
        } else {
            backImages.append(image)
        }
    }
    
    private func removeImage(at index: Int) {
        if selectedSide == .front {
            frontImages.remove(at: index)
        } else {
            backImages.remove(at: index)
        }
    }
    
    // MARK: - Audio Management
    
    private func removeAudio(at index: Int) {
        if selectedSide == .front {
            let path = CDCard.resolvedPath(for: frontAudioPaths[index])
            try? FileManager.default.removeItem(atPath: path)
            frontAudioPaths.remove(at: index)
        } else {
            let path = CDCard.resolvedPath(for: backAudioPaths[index])
            try? FileManager.default.removeItem(atPath: path)
            backAudioPaths.remove(at: index)
        }
    }
    
    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)
        
        let filename = UUID().uuidString + ".m4a"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        audioRecorder = try? AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.record()
        isRecording = true
        recordingTime = 0
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingTime += 0.1
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        
        if let url = audioRecorder?.url {
            let filename = url.lastPathComponent
            if selectedSide == .front {
                frontAudioPaths.append(filename)
            } else {
                backAudioPaths.append(filename)
            }
        }
    }
    
    private func playAudio(_ path: String) {
        let resolved = CDCard.resolvedPath(for: path)
        let url = URL(fileURLWithPath: resolved)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Failed to play audio: \(error)")
        }
    }
    
    private func handleAudioImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        
        let filename = UUID().uuidString + ".m4a"
        let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        
        _ = url.startAccessingSecurityScopedResource()
        try? FileManager.default.copyItem(at: url, to: destination)
        url.stopAccessingSecurityScopedResource()
        
        if selectedSide == .front {
            frontAudioPaths.append(filename)
        } else {
            backAudioPaths.append(filename)
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func saveCard() {
        let trimmedFront = frontText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFront.isEmpty else { return }
        
        let card = CDCard(context: viewContext)
        card.id = UUID().uuidString
        card.frontText = trimmedFront
        card.backText = backText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Save rich text as RTF data
        if frontText.length > 0, let rtfData = try? frontText.data(from: NSRange(location: 0, length: frontText.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            card.frontRTFData = rtfData
        }
        
        if backText.length > 0, let rtfData = try? backText.data(from: NSRange(location: 0, length: backText.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            card.backRTFData = rtfData
        }
        
        // Save ALL images as files
        let savedFrontPaths = frontImages.compactMap { CDCard.saveImageToFile(image: $0) }
        card.frontImagePathArray = savedFrontPaths
        
        let savedBackPaths = backImages.compactMap { CDCard.saveImageToFile(image: $0) }
        card.backImagePathArray = savedBackPaths
        
        // Save ALL audio paths
        card.frontAudioPathArray = frontAudioPaths
        card.backAudioPathArray = backAudioPaths
        
        card.createdAt = Date()
        card.deck = deck
        
        try? viewContext.save()
        dismiss()
    }
    
    private func insertCardLink(_ linkedCard: CDCard) {
        let linkText = "\u{1F517} \(CardLinkHelper.plainText(card: linkedCard).prefix(30))"
        let linkString = NSMutableAttributedString(string: linkText)
        let fullRange = NSRange(location: 0, length: linkString.length)
        
        linkString.addAttribute(.link, value: "card://\(linkedCard.id)", range: fullRange)
        linkString.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: fullRange)
        linkString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
        linkString.addAttribute(.font, value: UIFont.systemFont(ofSize: 12), range: fullRange)
        linkString.addAttribute(.baselineOffset, value: -2, range: fullRange)
        
        let result = NSMutableAttributedString(attributedString: currentText.wrappedValue)
        result.append(NSAttributedString(string: " "))
        result.append(linkString)
        result.append(NSAttributedString(string: " ", attributes: [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.label,
            .baselineOffset: 0
        ]))
        
        // Defer to next run loop so view hierarchy is fully settled
        DispatchQueue.main.async {
            currentText.wrappedValue = result
        }
    }
    
    private func insertScannedText(_ text: String) {
        let scanned = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.label
        ])
        let result = NSMutableAttributedString(attributedString: currentText.wrappedValue)
        if result.length > 0 {
            result.append(NSAttributedString(string: "\n"))
        }
        result.append(scanned)
        
        DispatchQueue.main.async {
            currentText.wrappedValue = result
        }
    }
    
    private func ocrFromImage(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        
        if let observations = request.results {
            let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            if !text.isEmpty {
                pendingScannedText = text
            }
        }
    }
}

// MARK: - Attributed Text Editor (with keyboard accessory toolbar)
struct AttributedTextEditor: UIViewRepresentable {
    @Binding var attributedText: NSMutableAttributedString
    @Binding var selectedRange: NSRange
    var onScanDocument: (() -> Void)?
    var onScanPhoto: (() -> Void)?
    var onTranslate: (() -> Void)?
    var onCardLink: (() -> Void)?
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 16)
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.backgroundColor = UIColor.systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.label
        ]
        
        // Build scrollable input accessory view
        let accessoryHeight: CGFloat = 44
        let accessoryView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: accessoryHeight))
        accessoryView.backgroundColor = UIColor.secondarySystemBackground
        
        // Top separator line
        let separator = UIView()
        separator.backgroundColor = UIColor.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        accessoryView.addSubview(separator)
        
        // Done button (fixed on right)
        let doneBtn = UIButton(type: .system)
        doneBtn.setTitle("Done", for: .normal)
        doneBtn.titleLabel?.font = .boldSystemFont(ofSize: 16)
        doneBtn.addTarget(context.coordinator, action: #selector(Coordinator.doneTapped), for: .touchUpInside)
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        accessoryView.addSubview(doneBtn)
        
        // Scrollable button strip
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        accessoryView.addSubview(scrollView)
        
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        
        let icons: [(String, Selector)] = [
            ("bold", #selector(Coordinator.boldTapped)),
            ("italic", #selector(Coordinator.italicTapped)),
            ("underline", #selector(Coordinator.underlineTapped)),
            ("strikethrough", #selector(Coordinator.strikethroughTapped)),
            ("textformat.subscript", #selector(Coordinator.subscriptTapped)),
            ("textformat.superscript", #selector(Coordinator.superscriptTapped)),
        ]
        
        let toolIcons: [(String, Selector)] = [
            ("doc.text.viewfinder", #selector(Coordinator.scanTapped)),
            ("translate", #selector(Coordinator.translateTapped)),
            ("link.badge.plus", #selector(Coordinator.cardLinkTapped)),
        ]
        
        for (icon, sel) in icons {
            let btn = UIButton(type: .system)
            btn.setImage(UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)), for: .normal)
            btn.addTarget(context.coordinator, action: sel, for: .touchUpInside)
            btn.widthAnchor.constraint(equalToConstant: 40).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
            stack.addArrangedSubview(btn)
        }
        
        // Divider between formatting and tools
        let divider = UIView()
        divider.backgroundColor = UIColor.separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(divider)
        
        for (icon, sel) in toolIcons {
            let btn = UIButton(type: .system)
            btn.setImage(UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)), for: .normal)
            btn.addTarget(context.coordinator, action: sel, for: .touchUpInside)
            btn.widthAnchor.constraint(equalToConstant: 40).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
            stack.addArrangedSubview(btn)
        }
        
        // Fade hint on right edge of scroll view to show it's scrollable
        let fadeWidth: CGFloat = 20
        let fadeView = UIView()
        fadeView.isUserInteractionEnabled = false
        fadeView.translatesAutoresizingMaskIntoConstraints = false
        accessoryView.addSubview(fadeView)
        
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: accessoryView.topAnchor),
            separator.leadingAnchor.constraint(equalTo: accessoryView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: accessoryView.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
            
            doneBtn.trailingAnchor.constraint(equalTo: accessoryView.trailingAnchor, constant: -12),
            doneBtn.centerYAnchor.constraint(equalTo: accessoryView.centerYAnchor),
            doneBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            
            scrollView.leadingAnchor.constraint(equalTo: accessoryView.leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: doneBtn.leadingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: accessoryView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: accessoryView.bottomAnchor),
            
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            
            fadeView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            fadeView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            fadeView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            fadeView.widthAnchor.constraint(equalToConstant: fadeWidth),
        ])
        
        // Add gradient fade after layout
        DispatchQueue.main.async {
            let gradient = CAGradientLayer()
            gradient.frame = CGRect(x: 0, y: 0, width: fadeWidth, height: accessoryHeight)
            gradient.colors = [UIColor.secondarySystemBackground.withAlphaComponent(0).cgColor, UIColor.secondarySystemBackground.cgColor]
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            fadeView.layer.addSublayer(gradient)
        }
        
        textView.inputAccessoryView = accessoryView
        
        // Store button references for active state highlighting
        context.coordinator.formatButtons = [
            "bold": stack.arrangedSubviews[0] as? UIButton,
            "italic": stack.arrangedSubviews[1] as? UIButton,
            "underline": stack.arrangedSubviews[2] as? UIButton,
            "strikethrough": stack.arrangedSubviews[3] as? UIButton,
            "subscript": stack.arrangedSubviews[4] as? UIButton,
            "superscript": stack.arrangedSubviews[5] as? UIButton,
        ].compactMapValues { $0 }
        
        context.coordinator.textView = textView
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.attributedText.string != attributedText.string ||
           !uiView.attributedText.isEqual(to: attributedText) {
            context.coordinator.isUpdating = true
            uiView.attributedText = attributedText
            let newPos = attributedText.length
            uiView.selectedRange = NSRange(location: newPos, length: 0)
            context.coordinator.isUpdating = false
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: AttributedTextEditor
        weak var textView: UITextView?
        var isUpdating = false
        var formatButtons: [String: UIButton] = [:]
        // Track active toggles for typing mode (no selection)
        var boldActive = false
        var italicActive = false
        var underlineActive = false
        var strikethroughActive = false
        var subscriptActive = false
        var superscriptActive = false
        
        init(_ parent: AttributedTextEditor) { self.parent = parent }
        
        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            parent.attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
            // Update button highlight states based on current position/selection
            updateButtonStates(textView)
        }
        
        private func updateButtonStates(_ textView: UITextView) {
            let range = textView.selectedRange
            if range.length > 0 && range.location < parent.attributedText.length {
                let font = parent.attributedText.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
                let traits = font?.fontDescriptor.symbolicTraits ?? []
                boldActive = traits.contains(.traitBold)
                italicActive = traits.contains(.traitItalic)
                underlineActive = parent.attributedText.attribute(.underlineStyle, at: range.location, effectiveRange: nil) != nil
                strikethroughActive = parent.attributedText.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) != nil
                let offset = parent.attributedText.attribute(.baselineOffset, at: range.location, effectiveRange: nil) as? NSNumber
                subscriptActive = (offset?.doubleValue ?? 0) < 0
                superscriptActive = (offset?.doubleValue ?? 0) > 0
            } else if range.location > 0 && range.location <= parent.attributedText.length {
                let attrs = textView.typingAttributes
                let font = attrs[.font] as? UIFont
                let traits = font?.fontDescriptor.symbolicTraits ?? []
                boldActive = traits.contains(.traitBold)
                italicActive = traits.contains(.traitItalic)
                underlineActive = attrs[.underlineStyle] != nil
                strikethroughActive = attrs[.strikethroughStyle] != nil
                let offset = attrs[.baselineOffset] as? NSNumber
                subscriptActive = (offset?.doubleValue ?? 0) < 0
                superscriptActive = (offset?.doubleValue ?? 0) > 0
            }
            
            highlightButton("bold", active: boldActive)
            highlightButton("italic", active: italicActive)
            highlightButton("underline", active: underlineActive)
            highlightButton("strikethrough", active: strikethroughActive)
            highlightButton("subscript", active: subscriptActive)
            highlightButton("superscript", active: superscriptActive)
        }
        
        private func highlightButton(_ key: String, active: Bool) {
            guard let btn = formatButtons[key] else { return }
            btn.backgroundColor = active ? UIColor.systemBlue.withAlphaComponent(0.2) : .clear
            btn.tintColor = active ? .systemBlue : .label
            btn.layer.cornerRadius = 6
        }
        
        private func rebuildTypingAttributes() {
            guard let tv = textView else { return }
            let fontSize: CGFloat = 16
            let effectiveSize: CGFloat = (subscriptActive || superscriptActive) ? fontSize * 0.7 : fontSize
            var font: UIFont = .systemFont(ofSize: effectiveSize)
            var traits = UIFontDescriptor.SymbolicTraits()
            if boldActive { traits.insert(.traitBold) }
            if italicActive { traits.insert(.traitItalic) }
            if let desc = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: desc, size: effectiveSize)
            }
            
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.label
            ]
            if underlineActive { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if strikethroughActive { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if subscriptActive { attrs[.baselineOffset] = -4 }
            else if superscriptActive { attrs[.baselineOffset] = 8 }
            tv.typingAttributes = attrs
        }
        
        @objc func doneTapped() { textView?.resignFirstResponder() }
        
        @objc func scanTapped() {
            guard let tv = textView, let vc = tv.findViewController() else { return }
            let alert = UIAlertController(title: "Scan Text", message: nil, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Scan Document", style: .default) { [weak self] _ in self?.parent.onScanDocument?() })
            alert.addAction(UIAlertAction(title: "Scan Text from Photo", style: .default) { [weak self] _ in self?.parent.onScanPhoto?() })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            if let pop = alert.popoverPresentationController {
                pop.sourceView = tv
                pop.sourceRect = CGRect(x: tv.bounds.midX, y: tv.bounds.maxY, width: 0, height: 0)
            }
            vc.present(alert, animated: true)
        }
        
        @objc func translateTapped() { parent.onTranslate?() }
        @objc func cardLinkTapped() { parent.onCardLink?() }
        
        // MARK: - Formatting actions
        @objc func boldTapped() {
            guard let tv = textView else { return }
            if tv.selectedRange.length > 0 {
                applyFormatting { text, range in
                    text.enumerateAttribute(.font, in: range) { val, r, _ in
                        let font = val as? UIFont ?? .systemFont(ofSize: 16)
                        var t = font.fontDescriptor.symbolicTraits
                        if t.contains(.traitBold) { t.remove(.traitBold) } else { t.insert(.traitBold) }
                        if let d = font.fontDescriptor.withSymbolicTraits(t) { text.addAttribute(.font, value: UIFont(descriptor: d, size: font.pointSize), range: r) }
                    }
                }
            } else {
                boldActive.toggle()
                rebuildTypingAttributes()
            }
            updateButtonStates(tv)
        }
        
        @objc func italicTapped() {
            guard let tv = textView else { return }
            if tv.selectedRange.length > 0 {
                applyFormatting { text, range in
                    text.enumerateAttribute(.font, in: range) { val, r, _ in
                        let font = val as? UIFont ?? .systemFont(ofSize: 16)
                        var t = font.fontDescriptor.symbolicTraits
                        if t.contains(.traitItalic) { t.remove(.traitItalic) } else { t.insert(.traitItalic) }
                        if let d = font.fontDescriptor.withSymbolicTraits(t) { text.addAttribute(.font, value: UIFont(descriptor: d, size: font.pointSize), range: r) }
                    }
                }
            } else {
                italicActive.toggle()
                rebuildTypingAttributes()
            }
            updateButtonStates(tv)
        }
        
        @objc func underlineTapped() {
            guard let tv = textView else { return }
            if tv.selectedRange.length > 0 {
                applyFormatting { text, range in
                    if text.attribute(.underlineStyle, at: range.location, effectiveRange: nil) != nil {
                        text.removeAttribute(.underlineStyle, range: range)
                    } else {
                        text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    }
                }
            } else {
                underlineActive.toggle()
                rebuildTypingAttributes()
            }
            updateButtonStates(tv)
        }
        
        @objc func strikethroughTapped() {
            guard let tv = textView else { return }
            if tv.selectedRange.length > 0 {
                applyFormatting { text, range in
                    if text.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) != nil {
                        text.removeAttribute(.strikethroughStyle, range: range)
                    } else {
                        text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    }
                }
            } else {
                strikethroughActive.toggle()
                rebuildTypingAttributes()
            }
            updateButtonStates(tv)
        }
        
        @objc func subscriptTapped() {
            guard let tv = textView else { return }
            if tv.selectedRange.length > 0 {
                applyFormatting { text, range in
                    let offset = text.attribute(.baselineOffset, at: range.location, effectiveRange: nil) as? NSNumber
                    if (offset?.doubleValue ?? 0) < 0 {
                        // Remove subscript — restore normal size
                        text.removeAttribute(.baselineOffset, range: range)
                        text.enumerateAttribute(.font, in: range) { val, r, _ in
                            let font = val as? UIFont ?? .systemFont(ofSize: 16)
                            let restored = UIFont(descriptor: font.fontDescriptor, size: 16)
                            text.addAttribute(.font, value: restored, range: r)
                        }
                    } else {
                        // Apply subscript — clear superscript first
                        text.removeAttribute(.baselineOffset, range: range)
                        let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont ?? .systemFont(ofSize: 16)
                        text.addAttribute(.font, value: UIFont.systemFont(ofSize: font.pointSize * 0.7), range: range)
                        text.addAttribute(.baselineOffset, value: -4, range: range)
                    }
                }
            } else {
                if subscriptActive {
                    subscriptActive = false
                } else {
                    subscriptActive = true
                    superscriptActive = false
                }
                rebuildTypingAttributes()
            }
            updateButtonStates(tv)
        }
        
        @objc func superscriptTapped() {
            guard let tv = textView else { return }
            if tv.selectedRange.length > 0 {
                applyFormatting { text, range in
                    let offset = text.attribute(.baselineOffset, at: range.location, effectiveRange: nil) as? NSNumber
                    if (offset?.doubleValue ?? 0) > 0 {
                        // Remove superscript — restore normal size
                        text.removeAttribute(.baselineOffset, range: range)
                        text.enumerateAttribute(.font, in: range) { val, r, _ in
                            let font = val as? UIFont ?? .systemFont(ofSize: 16)
                            let restored = UIFont(descriptor: font.fontDescriptor, size: 16)
                            text.addAttribute(.font, value: restored, range: r)
                        }
                    } else {
                        // Apply superscript — clear subscript first
                        text.removeAttribute(.baselineOffset, range: range)
                        let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont ?? .systemFont(ofSize: 16)
                        text.addAttribute(.font, value: UIFont.systemFont(ofSize: font.pointSize * 0.7), range: range)
                        text.addAttribute(.baselineOffset, value: 8, range: range)
                    }
                }
            } else {
                if superscriptActive {
                    superscriptActive = false
                } else {
                    superscriptActive = true
                    subscriptActive = false
                }
                rebuildTypingAttributes()
            }
            updateButtonStates(tv)
        }
        
        private func applyFormatting(_ op: (NSMutableAttributedString, NSRange) -> Void) {
            guard let tv = textView else { return }
            let range = tv.selectedRange
            guard range.length > 0, range.location + range.length <= parent.attributedText.length else { return }
            op(parent.attributedText, range)
            parent.attributedText = NSMutableAttributedString(attributedString: parent.attributedText)
        }
    }
}

private extension UIView {
    func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }
}


// MARK: - Drawing View
struct DrawingView: View {
    let onSave: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()
    
    var body: some View {
        NavigationStack {
            CanvasView(canvas: $canvas)
                .navigationTitle("Draw")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            let drawing = canvas.drawing
                            var bounds = drawing.bounds
                            let padding: CGFloat = 20
                            bounds = bounds.insetBy(dx: -padding, dy: -padding)
                            
                            if bounds.isEmpty || bounds.isInfinite || bounds.isNull {
                                bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
                            }
                            
                            // Force light appearance so strokes render correctly in dark mode
                            let format = UIGraphicsImageRendererFormat()
                            format.scale = 3.0
                            let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
                            let image = renderer.image { ctx in
                                UIColor.white.setFill()
                                ctx.fill(bounds)
                                // Render drawing in light mode trait collection
                                let lightTraits = UITraitCollection(userInterfaceStyle: .light)
                                lightTraits.performAsCurrent {
                                    let drawingImage = drawing.image(from: bounds, scale: 3.0)
                                    drawingImage.draw(in: bounds)
                                }
                            }
                            onSave(image)
                            dismiss()
                        }
                    }
                }
        }
    }
}

struct CanvasView: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.overrideUserInterfaceStyle = .light
        
        let toolPicker = PKToolPicker()
        context.coordinator.toolPicker = toolPicker
        context.coordinator.canvas = canvas
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        
        return canvas
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // becomeFirstResponder only works once the view is in the window
        if uiView.window != nil && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var toolPicker: PKToolPicker?
        weak var canvas: PKCanvasView?
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onSelect: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onSelect(image)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Identifiable String wrapper
struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

// MARK: - Document Scanner (VisionKit OCR)
struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        
        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var allText = ""
            
            for pageIndex in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageIndex)
                guard let cgImage = image.cgImage else { continue }
                
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
                
                if let observations = request.results {
                    let pageText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    if !pageText.isEmpty {
                        if !allText.isEmpty { allText += "\n\n" }
                        allText += pageText
                    }
                }
            }
            
            parent.onScan(allText)
            parent.dismiss()
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}

// MARK: - Scanned Text Review Sheet
struct ScannedTextReviewSheet: View {
    @State var scannedText: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Review and edit the scanned text before inserting.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 12)
                
                TextEditor(text: $scannedText)
                    .padding()
                    .font(.body)
            }
            .navigationTitle("Scanned Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") {
                        onConfirm(scannedText)
                        dismiss()
                    }
                    .disabled(scannedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Speech Helper (Text-to-Speech with auto language detection)
class SpeechHelper: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()
    private let languageRecognizer = NLLanguageRecognizer()
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func toggleSpeech(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            return
        }
        
        // Detect language
        languageRecognizer.reset()
        languageRecognizer.processString(text)
        let lang = languageRecognizer.dominantLanguage?.rawValue ?? "en-US"
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: lang)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
        
        isSpeaking = true
        synthesizer.speak(utterance)
    }
    
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
