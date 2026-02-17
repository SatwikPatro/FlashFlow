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

struct EditCardSheet: View {
    let card: CDCard
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var frontText = NSMutableAttributedString(string: "")
    @State private var backText = NSMutableAttributedString(string: "")
    @State private var selectedSide: CardSide = .front
    @State private var selectedRange = NSRange(location: 0, length: 0)
    
    @State private var frontImages: [UIImage] = []
    @State private var backImages: [UIImage] = []
    @State private var frontAudioPaths: [String] = []
    @State private var backAudioPaths: [String] = []
    
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var showDrawing = false
    @State private var showAudioImporter = false
    @State private var showCardLinkPicker = false
    @State private var pendingLinkedCard: CDCard?
    @State private var viewingLinkedCardID: String?
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
            get: { selectedSide == .front ? frontText : backText },
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
                Picker("Side", selection: $selectedSide) {
                    ForEach(CardSide.allCases, id: \.self) { side in
                        Text(side.rawValue).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                Form {
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
                        EditableAttributedTextView(
                            attributedText: currentText,
                            selectedRange: $selectedRange,
                            onLinkTap: { cardID in
                                viewingLinkedCardID = cardID
                            },
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
                            Label("Add from Library", systemImage: "photo")
                        }
                        
                        Button(action: { showDrawing = true }) {
                            Label("Draw Image", systemImage: "pencil.tip.crop.circle")
                        }
                    }
                    
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
            .navigationTitle("Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCard() }
                }
            }
            .onAppear {
                loadCard()
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
            .sheet(isPresented: $showCardLinkPicker, onDismiss: {
                if let card = pendingLinkedCard {
                    insertCardLink(card)
                    pendingLinkedCard = nil
                }
            }) {
                CardLinkPickerView(
                    deck: card.deck,
                    excludeCardID: card.id
                ) { linkedCard in
                    pendingLinkedCard = linkedCard
                }
            }
            .sheet(isPresented: Binding(
                get: { viewingLinkedCardID != nil },
                set: { if !$0 { viewingLinkedCardID = nil } }
            )) {
                if let cardID = viewingLinkedCardID,
                   let linkedCard = getLinkedCard(byID: cardID) {
                    LinkedCardDetailView(card: linkedCard)
                }
            }
        }
    }
    
    private func getLinkedCard(byID cardID: String) -> CDCard? {
        let request = NSFetchRequest<CDCard>(entityName: "CDCard")
        request.predicate = NSPredicate(format: "id == %@", cardID)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
    
    private func loadCard() {
        if let rtfData = card.frontRTFData,
           let attrString = try? NSMutableAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            frontText = attrString
        } else {
            frontText = NSMutableAttributedString(string: card.frontText)
        }
        
        if let rtfData = card.backRTFData,
           let attrString = try? NSMutableAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            backText = attrString
        } else {
            backText = NSMutableAttributedString(string: card.backText)
        }
        
        // Load ALL images from file paths (with backward compat via the helper)
        frontImages = card.frontImagePathArray.compactMap { CDCard.loadImage(from: $0) }
        backImages = card.backImagePathArray.compactMap { CDCard.loadImage(from: $0) }
        
        // Load ALL audio paths
        frontAudioPaths = card.frontAudioPathArray
        backAudioPaths = card.backAudioPathArray
    }
    
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
        card.frontText = frontText.string
        card.backText = backText.string
        
        if frontText.length > 0, let rtfData = try? frontText.data(from: NSRange(location: 0, length: frontText.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            card.frontRTFData = rtfData
        }
        
        if backText.length > 0, let rtfData = try? backText.data(from: NSRange(location: 0, length: backText.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            card.backRTFData = rtfData
        }
        
        // Delete old image files (new files are always created fresh)
        let oldFrontImagePaths = card.frontImagePathArray
        let oldBackImagePaths = card.backImagePathArray
        
        // Save ALL images as new files
        let newFrontPaths = frontImages.compactMap { CDCard.saveImageToFile(image: $0) }
        let newBackPaths = backImages.compactMap { CDCard.saveImageToFile(image: $0) }
        
        // Clean up old image files
        let fm = FileManager.default
        for storedPath in oldFrontImagePaths {
            try? fm.removeItem(atPath: CDCard.resolvedPath(for: storedPath))
        }
        for storedPath in oldBackImagePaths {
            try? fm.removeItem(atPath: CDCard.resolvedPath(for: storedPath))
        }
        
        card.frontImagePathArray = newFrontPaths
        card.backImagePathArray = newBackPaths
        card.frontImageData = nil // Clear legacy
        card.backImageData = nil
        
        // Save ALL audio paths
        card.frontAudioPathArray = frontAudioPaths
        card.backAudioPathArray = backAudioPaths
        card.frontAudioPath = nil // Clear legacy
        card.backAudioPath = nil
        
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

// MARK: - Editable Attributed Text View (with keyboard accessory toolbar)
struct EditableAttributedTextView: UIViewRepresentable {
    @Binding var attributedText: NSMutableAttributedString
    @Binding var selectedRange: NSRange
    var onLinkTap: ((String) -> Void)? = nil
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
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.label
        ]
        
        // Build scrollable input accessory view
        let accessoryHeight: CGFloat = 44
        let accessoryView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: accessoryHeight))
        accessoryView.backgroundColor = UIColor.secondarySystemBackground
        
        let separator = UIView()
        separator.backgroundColor = UIColor.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        accessoryView.addSubview(separator)
        
        let doneBtn = UIButton(type: .system)
        doneBtn.setTitle("Done", for: .normal)
        doneBtn.titleLabel?.font = .boldSystemFont(ofSize: 16)
        doneBtn.addTarget(context.coordinator, action: #selector(Coordinator.doneTapped), for: .touchUpInside)
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        accessoryView.addSubview(doneBtn)
        
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
        
        // Fade hint on right edge of scroll view
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
        
        DispatchQueue.main.async {
            let gradient = CAGradientLayer()
            gradient.frame = CGRect(x: 0, y: 0, width: fadeWidth, height: accessoryHeight)
            gradient.colors = [UIColor.secondarySystemBackground.withAlphaComponent(0).cgColor, UIColor.secondarySystemBackground.cgColor]
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            fadeView.layer.addSublayer(gradient)
        }
        
        textView.inputAccessoryView = accessoryView
        
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
        let currentString = uiView.attributedText.string
        let newString = attributedText.string
        
        if currentString != newString || !uiView.attributedText.isEqual(to: attributedText) {
            context.coordinator.isUpdating = true
            uiView.attributedText = NSMutableAttributedString(attributedString: attributedText)
            uiView.selectedRange = NSRange(location: attributedText.length, length: 0)
            context.coordinator.isUpdating = false
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditableAttributedTextView
        weak var textView: UITextView?
        var isUpdating = false
        var formatButtons: [String: UIButton] = [:]
        var boldActive = false
        var italicActive = false
        var underlineActive = false
        var strikethroughActive = false
        var subscriptActive = false
        var superscriptActive = false
        
        init(_ parent: EditableAttributedTextView) { self.parent = parent }
        
        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            parent.attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
            updateButtonStates(textView)
        }
        
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange) -> Bool {
            if URL.scheme == "card", let cardID = URL.host {
                parent.onLinkTap?(cardID)
            }
            return false
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
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
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
                        text.removeAttribute(.baselineOffset, range: range)
                        text.enumerateAttribute(.font, in: range) { val, r, _ in
                            let font = val as? UIFont ?? .systemFont(ofSize: 16)
                            let restored = UIFont(descriptor: font.fontDescriptor, size: 16)
                            text.addAttribute(.font, value: restored, range: r)
                        }
                    } else {
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
                        text.removeAttribute(.baselineOffset, range: range)
                        text.enumerateAttribute(.font, in: range) { val, r, _ in
                            let font = val as? UIFont ?? .systemFont(ofSize: 16)
                            let restored = UIFont(descriptor: font.fontDescriptor, size: 16)
                            text.addAttribute(.font, value: restored, range: r)
                        }
                    } else {
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
