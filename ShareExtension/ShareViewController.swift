import UIKit
import UniformTypeIdentifiers
import PBNCore
import ImageIO

/// Share Extension entry point. Accepts exactly one image, writes it into the
/// App Group inbox, and opens the host app via the `paintbynumbers://import`
/// URL scheme so the image can be turned into a puzzle.
final class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        extractImageAndHandoff()
    }

    private func extractImageAndHandoff() {
        guard
            let item = extensionContext?.inputItems.compactMap({ $0 as? NSExtensionItem }).first,
            let attachment = item.attachments?.first
        else {
            completeOnMain()
            return
        }

        let typeIdentifier: String
        if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            typeIdentifier = UTType.image.identifier
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            typeIdentifier = UTType.fileURL.identifier
        } else {
            completeOnMain()
            return
        }

        attachment.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] data, _ in
            guard let self else { return }
            let image: UIImage? = {
                if let img = data as? UIImage { return img }
                if let url = data as? URL, let d = try? Data(contentsOf: url) { return UIImage(data: d) }
                if let d = data as? Data { return UIImage(data: d) }
                return nil
            }()
            guard let image,
                  let cgImage = image.cgImage,
                  cgImage.width <= 12_000,
                  cgImage.height <= 12_000,
                  cgImage.width.multipliedReportingOverflow(by: cgImage.height).overflow == false,
                  cgImage.width * cgImage.height <= 40_000_000,
                  let pngData = image.pngData(),
                  pngData.count <= 25 * 1_024 * 1_024 else {
                self.completeOnMain()
                return
            }
            self.persistAndOpen(pngData: pngData)
        }
    }

    private func persistAndOpen(pngData: Data) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConfiguration.appGroupIdentifier
        ) else {
            completeOnMain()
            return
        }
        let inbox = container.appendingPathComponent("SharedInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        removeAbandonedHandoffs(in: inbox)

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
            completeOnMain()
            return
        }

        /// Prevent failed or never-opened handoffs from accumulating indefinitely.
        private func removeAbandonedHandoffs(in inbox: URL) {
            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: inbox,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { return }
            for file in files {
                guard ShareImport.isSafeFilename(file.lastPathComponent),
                      let values = try? file.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      modified < cutoff else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }

        let openURL = ShareImport.openURL(for: token)
        DispatchQueue.main.async { [weak self] in
            self?.open(url: openURL)
            self?.complete()
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

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
