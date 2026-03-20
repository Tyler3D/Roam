import UIKit
import UniformTypeIdentifiers

/// Saves URL/text from the share sheet into app-group [`SharedStore`](Roam/SharedStore.swift), opens the host app, then completes (minimal chrome).
///
/// Instagram and other hosts sometimes never invoke some `loadItem` callbacks; we use a timeout so the extension never hangs.
final class ShareViewController: UIViewController {

    private let extractTimeoutSeconds: TimeInterval = 5
    private let openFallbackSeconds: TimeInterval = 1.5
    private var didFinishExtension = false

    override func loadView() {
        let v = UIView()
        v.backgroundColor = .clear
        v.isOpaque = false
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        extractAndSave()
    }

    private func extractAndSave() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            saveOpenAndClose(url: nil, text: nil, typeIds: [])
            return
        }

        let group = DispatchGroup()
        var sharedURL: String?
        var sharedText: String?
        var typeIdentifiers: [String] = []

        func mergeFromAttributedItems() {
            for item in extensionItems {
                if let attr = item.attributedContentText {
                    let s = attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty {
                        if sharedText == nil { sharedText = s }
                        if sharedURL == nil, let u = URL(string: s), u.scheme == "http" || u.scheme == "https" {
                            sharedURL = s
                        }
                    }
                }
            }
        }

        mergeFromAttributedItems()

        let urlTypeIds = [
            UTType.url.identifier,
            "public.url",
            UTType.fileURL.identifier,
            "public.file-url",
        ]

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                typeIdentifiers.append(contentsOf: provider.registeredTypeIdentifiers)

                for typeId in urlTypeIds where provider.hasItemConformingToTypeIdentifier(typeId) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: typeId) { data, _ in
                        DispatchQueue.main.async {
                            defer { group.leave() }
                            if let url = data as? URL {
                                sharedURL = url.absoluteString
                            } else if let nsUrl = data as? NSURL, let url = nsUrl as URL? {
                                sharedURL = url.absoluteString
                            } else if let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                                sharedURL = url.absoluteString
                            } else if let str = data as? String, let url = URL(string: str), url.scheme == "http" || url.scheme == "https" {
                                sharedURL = str
                            }
                        }
                    }
                    break
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                        DispatchQueue.main.async {
                            defer { group.leave() }
                            if let text = data as? String {
                                if sharedURL == nil, let url = URL(string: text), url.scheme == "http" || url.scheme == "https" {
                                    sharedURL = text
                                } else if sharedText == nil {
                                    sharedText = text
                                }
                            }
                        }
                    }
                }
            }
        }

        var didScheduleCompletion = false
        func completeExtraction() {
            guard !didScheduleCompletion else { return }
            didScheduleCompletion = true
            saveOpenAndClose(url: sharedURL, text: sharedText, typeIds: typeIdentifiers)
        }

        group.notify(queue: .main) {
            completeExtraction()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + extractTimeoutSeconds) {
            completeExtraction()
        }
    }

    private func saveOpenAndClose(url: String?, text: String?, typeIds: [String]) {
        let newItem = SharedItem(
            id: UUID(),
            url: url,
            text: text,
            dateShared: Date(),
            attachmentTypeIdentifiers: typeIds
        )
        SharedStore.save(newItem)
        SharedStore.markPendingShareHandoff()
        openHostAppThenFinish()
    }

    private func openHostAppThenFinish() {
        guard let url = URL(string: "roam://share") else {
            closeExtension()
            return
        }

        extensionContext?.open(url) { [weak self] _ in
            self?.closeExtension()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + openFallbackSeconds) { [weak self] in
            self?.closeExtension()
        }
    }

    private func closeExtension() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didFinishExtension else { return }
            self.didFinishExtension = true
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
