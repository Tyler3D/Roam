import UIKit
import UniformTypeIdentifiers

/// Saves URL/text from the share sheet into app-group [`SharedStore`](Roam/SharedStore.swift) and completes immediately (no compose UI).
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        extractAndSave()
    }

    private func extractAndSave() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            close()
            return
        }

        let group = DispatchGroup()
        var sharedURL: String?
        var sharedText: String?
        var typeIdentifiers: [String] = []

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                typeIdentifiers.append(contentsOf: provider.registeredTypeIdentifiers)

                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { data, _ in
                        if let url = data as? URL {
                            sharedURL = url.absoluteString
                        } else if let urlData = data as? Data,
                                  let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                            sharedURL = url.absoluteString
                        }
                        group.leave()
                    }
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                        if let text = data as? String {
                            if sharedURL == nil, let url = URL(string: text),
                               url.scheme == "http" || url.scheme == "https" {
                                sharedURL = text
                            } else if sharedText == nil {
                                sharedText = text
                            }
                        }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) {
            let newItem = SharedItem(
                id: UUID(),
                url: sharedURL,
                text: sharedText,
                dateShared: Date(),
                attachmentTypeIdentifiers: typeIdentifiers
            )
            SharedStore.save(newItem)
            self.close()
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
