import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []

        let group = DispatchGroup()
        var sharedURL: String?
        var sharedText: String?
        var typeIdentifiers: [String] = []

        // Grab any text the user typed in the compose box
        if let composedText = contentText, !composedText.isEmpty {
            sharedText = composedText
        }

        for item in extensionItems {
            if let content = item.attributedContentText?.string,
               sharedText == nil {
                sharedText = content
            }

            for provider in item.attachments ?? [] {
                typeIdentifiers.append(
                    contentsOf: provider.registeredTypeIdentifiers
                )

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
                            } else {
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
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
