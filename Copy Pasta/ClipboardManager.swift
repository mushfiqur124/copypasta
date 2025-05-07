import Foundation
import SwiftUI
import AppKit

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    private let maxItems = 30
    private let maxTextLength = 1_000_000 // 1MB text limit
    private let userDefaultsKey = "savedClipboardItems"
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var lastPasteboardCheck = Date()
    private let minimumCheckInterval: TimeInterval = 0.3 // Minimum time between checks
    
    // Use NSCache for memory-efficient image caching
    let imageCache = NSCache<NSString, NSImage>()
    
    @Published private(set) var clipboardItems: [ClipboardItem] = []
    private var timer: Timer?
    private var saveWorkItem: DispatchWorkItem?
    
    private init() {
        // Configure image cache limits
        imageCache.countLimit = maxItems
        imageCache.totalCostLimit = 50_000_000 // 50MB limit for image cache
        
        loadSavedItems()
        startMonitoring()
        
        // Register for notifications
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(applicationWillTerminate),
                                     name: NSApplication.willTerminateNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationDidResignActive),
                                     name: NSApplication.didResignActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationDidBecomeActive),
                                     name: NSApplication.didBecomeActiveNotification, object: nil)
    }
    
    deinit {
        timer?.invalidate()
        saveWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func applicationWillTerminate() {
        // Cancel any pending save operations
        saveWorkItem?.cancel()
        
        // Perform final save synchronously to ensure data is persisted
        saveItems(immediately: true)
    }
    
    @objc private func applicationDidResignActive() {
        // Clear sensitive data from memory when app is not active
        autoreleasepool {
            for item in clipboardItems {
                if case .image = item.type {
                    // Clear image from cache
                    if let imageId = item.imageId {
                        imageCache.removeObject(forKey: imageId as NSString)
                    }
                }
            }
        }
    }
    
    @objc private func applicationDidBecomeActive() {
        // Restore monitoring when app becomes active
        startMonitoring()
    }
    
    private func sanitizeText(_ text: String) -> String? {
        // Check text length
        guard text.utf8.count <= maxTextLength else { return nil }
        
        // Basic sanitization - remove control characters except newlines and tabs
        let sanitized = text.components(separatedBy: CharacterSet.controlCharacters
            .subtracting(CharacterSet(charactersIn: "\n\t")))
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure it's not just whitespace or empty
        guard !sanitized.isEmpty else { return nil }
        
        // Ensure it's valid UTF-8
        guard sanitized.utf8.count == sanitized.utf8.count else { return nil }
        
        return sanitized
    }
    
    private func saveItems(immediately: Bool = false) {
        if immediately {
            // Save synchronously
            saveWorkItem?.cancel()
            let itemsToSave = clipboardItems.map { item -> [String: Any] in
                var dict: [String: Any] = [
                    "id": item.id,
                    "type": item.type.rawValue
                ]
                
                switch item.type {
                case .text:
                    dict["text"] = item.text
                case .image:
                    if let image = item.image,
                       let tiffData = image.tiffRepresentation,
                       let compressedData = NSBitmapImageRep(data: tiffData)?.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                        dict["imageData"] = compressedData.base64EncodedString()
                    }
                }
                return dict
            }
            
            if let data = try? JSONSerialization.data(withJSONObject: itemsToSave) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
                UserDefaults.standard.synchronize()
            }
            return
        }
        
        // Asynchronous save for normal operations
        saveWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            let itemsToSave = self.clipboardItems.map { item -> [String: Any] in
                var dict: [String: Any] = [
                    "id": item.id,
                    "type": item.type.rawValue
                ]
                
                switch item.type {
                case .text:
                    dict["text"] = item.text
                case .image:
                    if let image = item.image,
                       let tiffData = image.tiffRepresentation,
                       let compressedData = NSBitmapImageRep(data: tiffData)?.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                        dict["imageData"] = compressedData.base64EncodedString()
                    }
                }
                return dict
            }
            
            if let data = try? JSONSerialization.data(withJSONObject: itemsToSave) {
                UserDefaults.standard.set(data, forKey: self.userDefaultsKey)
            }
        }
        
        saveWorkItem = workItem
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }
    
    private func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        timer?.tolerance = 0.2
    }
    
    private func checkClipboard() {
        // Rate limiting for clipboard checks
        let now = Date()
        guard now.timeIntervalSince(lastPasteboardCheck) >= minimumCheckInterval else { return }
        lastPasteboardCheck = now
        
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        // Get available types
        let types = pasteboard.types ?? []
        
        // Filter out file URLs and other non-text/image types
        if types.contains(where: { $0 == .fileURL }) {
            return
        }
        
        // Try reading rich text first
        if let rtfdData = pasteboard.data(forType: .rtfd),
           let attributedString = try? NSAttributedString(data: rtfdData, 
                                                        options: [:], 
                                                        documentAttributes: nil) {
            // Extract plain text from rich text to avoid storing formatting
            addItem(ClipboardItem(type: .text, 
                                text: attributedString.string))
            
        } else if let rtfData = pasteboard.data(forType: .rtf),
                  let attributedString = try? NSAttributedString(data: rtfData, 
                                                               options: [:], 
                                                               documentAttributes: nil) {
            // Extract plain text from rich text to avoid storing formatting
            addItem(ClipboardItem(type: .text, 
                                text: attributedString.string))
            
        } else if let text = pasteboard.string(forType: .string),
                  let sanitizedText = sanitizeText(text) {
            addItem(ClipboardItem(type: .text, text: sanitizedText))
            
        } else if let image = pasteboard.data(forType: .tiff),
                  !image.isEmpty,
                  let nsImage = NSImage(data: image) {
            // Validate it's actually an image
            guard nsImage.isValid else { return }
            processImage(nsImage)
        }
    }
    
    private func processImage(_ image: NSImage) {
        // Additional image validation
        guard image.isValid,
              !image.representations.isEmpty,
              image.representations.allSatisfy({ $0.bitsPerSample >= 1 }),
              image.size.width > 0,
              image.size.height > 0,
              image.size.width <= 10000,
              image.size.height <= 10000 else { return }
        
        // Optimize image on background thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            let optimizedImage = self.optimizeImageForStorage(image)
            guard let tiffData = optimizedImage.tiffRepresentation,
                  tiffData.count <= 10_000_000,
                  NSImage(data: tiffData)?.isValid == true else { return }
            
            // Cache the optimized image
            let imageId = UUID().uuidString
            self.imageCache.setObject(optimizedImage, 
                                    forKey: imageId as NSString, 
                                    cost: tiffData.count)
            
            DispatchQueue.main.async {
                self.addItem(ClipboardItem(type: .image, 
                                         imageId: imageId, 
                                         image: optimizedImage))
            }
        }
    }
    
    private func optimizeImageForStorage(_ image: NSImage) -> NSImage {
        let maxDimension: CGFloat = 1024.0 // Maximum dimension for stored images
        
        let size = image.size
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }
        
        let ratio = size.width / size.height
        let newSize: NSSize
        if size.width > size.height {
            newSize = NSSize(width: maxDimension, height: maxDimension / ratio)
        } else {
            newSize = NSSize(width: maxDimension * ratio, height: maxDimension)
        }
        
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: size),
                  operation: .copy,
                  fraction: 1.0)
        resizedImage.unlockFocus()
        
        return resizedImage
    }
    
    private func addItem(_ item: ClipboardItem) {
        // Check if item already exists - improved comparison
        if case .text = item.type {
            if clipboardItems.contains(where: { 
                $0.type == .text && $0.text == item.text 
            }) {
                return
            }
        } else if case .image = item.type {
            // For images, we'll compare by data to avoid duplicates
            if let newImageData = item.image?.tiffRepresentation,
               clipboardItems.contains(where: { 
                   $0.type == .image && 
                   $0.image?.tiffRepresentation == newImageData 
               }) {
                return
            }
        }
        
        DispatchQueue.main.async {
            self.clipboardItems.insert(item, at: 0)
            if self.clipboardItems.count > self.maxItems {
                self.clipboardItems.removeLast()
            }
            self.saveItems()
        }
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .image:
            if let image = item.image {
                pasteboard.writeObjects([image])
            }
        }
    }
    
    private func loadSavedItems() {
        guard let savedData = UserDefaults.standard.data(forKey: userDefaultsKey),
              let items = try? JSONSerialization.jsonObject(with: savedData) as? [[String: Any]] else {
            return
        }
        
        clipboardItems = items.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let typeRaw = dict["type"] as? String,
                  let type = ClipboardItemType(rawValue: typeRaw) else {
                return nil
            }
            
            switch type {
            case .text:
                guard let text = dict["text"] as? String else {
                    return nil
                }
                return ClipboardItem(id: id, type: .text, text: text)
            case .image:
                guard let imageDataBase64 = dict["imageData"] as? String,
                      let imageData = Data(base64Encoded: imageDataBase64),
                      let image = NSImage(data: imageData) else {
                    return nil
                }
                return ClipboardItem(id: id, type: .image, image: image)
            }
        }
    }
}

enum ClipboardItemType: String, Codable {
    case text
    case image
}

struct ClipboardItem: Identifiable, Equatable {
    let id: String
    let type: ClipboardItemType
    let text: String?
    let imageId: String?
    
    var image: NSImage? {
        if let imageId = imageId {
            return ClipboardManager.shared.imageCache.object(forKey: imageId as NSString)
        }
        return nil
    }
    
    init(id: String = UUID().uuidString,
         type: ClipboardItemType,
         text: String? = nil,
         imageId: String? = nil,
         image: NSImage? = nil) {
        self.id = id
        self.type = type
        self.text = text
        self.imageId = imageId
        
        // Cache image if provided
        if let image = image, let imageId = imageId {
            ClipboardManager.shared.imageCache.setObject(image, 
                                                       forKey: imageId as NSString,
                                                       cost: image.tiffRepresentation?.count ?? 0)
        }
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        // Compare IDs for basic equality
        if lhs.id == rhs.id { return true }
        
        // If IDs are different, compare content
        if lhs.type != rhs.type { return false }
        
        switch lhs.type {
        case .text:
            return lhs.text == rhs.text
        case .image:
            // Compare image data if available
            if let lhsData = lhs.image?.tiffRepresentation,
               let rhsData = rhs.image?.tiffRepresentation {
                return lhsData == rhsData
            }
            return false
        }
    }
} 