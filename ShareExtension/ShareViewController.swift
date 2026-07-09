import UIKit
import UniformTypeIdentifiers
import PBNCore
import ImageIO

/// Share Extension entry point. Accepts exactly one image, writes it into the
/// App Group inbox, and opens the host app via the `paintbynumbers://import`
/// URL scheme so the image can be turned into a puzzle.
final class ShareViewController: UIViewController {
    private static let maximumFileBytes = 25 * 1_024 * 1_024
    private static let maximumDimension = 12_000
    private static let maximumPixels = 40_000_000

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        extractImageAndHandoff()
    }

    private func extractImageAndHandoff() {
        guard
            let item = extensionContext?.inputItems.compactMap({ $0 as? NSExtensionItem }).first,
            let attachment = item.attachments?.first
        else {
            failOnMain("No image was included in this share.")
            return
        }

        let typeIdentifier: String
        if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            typeIdentifier = UTType.image.identifier
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            typeIdentifier = UTType.fileURL.identifier
        } else {
            failOnMain("This item is not a supported image.")
            return
        }

        attachment.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] data, error in
            guard let self else { return }
            do {
                let pngData = try self.validatedPNG(from: data)
                self.persistAndOpen(pngData: pngData)
            } catch {
                self.failOnMain(
                    error.localizedDescription.isEmpty
                        ? "The shared image could not be opened safely."
                        : error.localizedDescription
                )
                NSLog("Share import failed: \(error)")
                return
            }
        }
    }

    private func persistAndOpen(pngData: Data) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConfiguration.appGroupIdentifier
        ) else {
            failOnMain("Shared storage is unavailable. Open Paint by Numbers once, then try again.")
            return
        }
        let inbox = container.appendingPathComponent("SharedInbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            try removeAbandonedHandoffs(in: inbox)
        } catch {
            failOnMain("Shared storage could not be prepared. \(error.localizedDescription)")
            return
        }

        // UUID strings match `ShareImport.isValidToken`'s allowlist, so the
        // host app will accept this token when it parses the open-URL.
        let token = UUID().uuidString
        let filename = "\(token).png"
        let imageURL = inbox.appendingPathComponent(filename)
        do {
            try pngData.write(to: imageURL, options: .atomic)
            let payload = ShareImportPayload(token: token, filename: filename)
            let metaURL = inbox.appendingPathComponent("\(token).json")
            try JSONEncoder().encode(payload).write(to: metaURL, options: .atomic)
        } catch {
            failOnMain("The image could not be saved for import. \(error.localizedDescription)")
            return
        }

        let openURL = ShareImport.openURL(for: token)
        DispatchQueue.main.async { [weak self] in
            self?.open(url: openURL)
            self?.complete()
        }
    }

    private func validatedPNG(from item: NSSecureCoding?) throws -> Data {
        let image: UIImage
        if let suppliedImage = item as? UIImage {
            image = suppliedImage
        } else {
            let data: Data
            if let url = item as? URL {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true else { throw ShareError.invalidImage }
                guard (values.fileSize ?? Self.maximumFileBytes + 1) <= Self.maximumFileBytes else {
                    throw ShareError.fileTooLarge
                }
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } else if let suppliedData = item as? Data {
                data = suppliedData
            } else {
                throw ShareError.invalidImage
            }
            guard data.count <= Self.maximumFileBytes else { throw ShareError.fileTooLarge }
            try validateEncodedDimensions(data)
            guard let decoded = UIImage(data: data) else { throw ShareError.invalidImage }
            image = decoded
        }

        guard let cgImage = image.cgImage else { throw ShareError.invalidImage }
        try validateDimensions(width: cgImage.width, height: cgImage.height)
        guard let pngData = image.pngData(), pngData.count <= Self.maximumFileBytes else {
            throw ShareError.fileTooLarge
        }
        return pngData
    }

    private func validateEncodedDimensions(_ data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ShareError.invalidImage
        }
        try validateDimensions(width: width, height: height)
    }

    private func validateDimensions(width: Int, height: Int) throws {
        let pixels = width.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0,
              width <= Self.maximumDimension, height <= Self.maximumDimension,
              !pixels.overflow, pixels.partialValue <= Self.maximumPixels else {
            throw ShareError.dimensionsTooLarge
        }
    }

    /// Prevent failed or never-opened handoffs from accumulating indefinitely.
    private func removeAbandonedHandoffs(in inbox: URL) throws {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        let files = try FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        for file in files where ShareImport.isSafeFilename(file.lastPathComponent) {
            let values = try file.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate, modified < cutoff else { continue }
            try FileManager.default.removeItem(at: file)
        }
    }

    /// Share extensions can't call `UIApplication.shared.open`. Walk up the
    /// responder chain to find an `openURL:` selector the runtime will
    /// accept. (Standard, documented technique.)
    private func open(url: URL) {
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let r = responder {
            if r.responds(to: selector) {
                _ = r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
    }

    /// Always complete the extension request on the main queue — AppKit/UIKit
    /// extension lifecycle APIs are not documented as thread-safe.
    private func completeOnMain() {
        if Thread.isMainThread {
            complete()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.complete()
            }
        }
    }

    private func failOnMain(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = UIAlertController(
                title: "Couldn’t import image",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.complete()
            })
            self.present(alert, animated: true)
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private enum ShareError: LocalizedError {
        case fileTooLarge
        case dimensionsTooLarge
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .fileTooLarge:
                return "The image is larger than the 25 MB import limit."
            case .dimensionsTooLarge:
                return "The image has too many pixels to process safely."
            case .invalidImage:
                return "The shared item is not a valid supported image."
            }
        }
    }
}
