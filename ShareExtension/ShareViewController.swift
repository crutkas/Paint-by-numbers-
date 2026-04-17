import UIKit
import UniformTypeIdentifiers
import PBNCore

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
            complete()
            return
        }

        let typeIdentifier: String
        if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            typeIdentifier = UTType.image.identifier
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            typeIdentifier = UTType.fileURL.identifier
        } else {
            complete()
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
            guard let image, let pngData = image.pngData() else {
                self.complete()
                return
            }
            self.persistAndOpen(pngData: pngData)
        }
    }

    private func persistAndOpen(pngData: Data) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.example.paintbynumbers"
        ) else {
            complete()
            return
        }
        let inbox = container.appendingPathComponent("SharedInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let token = UUID().uuidString
        let filename = "\(token).png"
        let imageURL = inbox.appendingPathComponent(filename)
        do {
            try pngData.write(to: imageURL, options: .atomic)
            let payload = ShareImportPayload(token: token, filename: filename)
            let metaURL = inbox.appendingPathComponent("\(token).json")
            try JSONEncoder().encode(payload).write(to: metaURL, options: .atomic)
        } catch {
            complete()
            return
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

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
