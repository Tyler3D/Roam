import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

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
                typeIdentifiers.append(
                    contentsOf: provider.registeredTypeIdentifiers
                )

                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { data, _ in
                        if let url = data as? URL {
                            sharedURL = url.absoluteString
                        }
                        group.leave()
                    }
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                        if let text = data as? String {
                            sharedText = text
                        }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) {
            let item = SharedItem(
                id: UUID(),
                url: sharedURL,
                text: sharedText,
                dateShared: Date(),
                attachmentTypeIdentifiers: typeIdentifiers
            )
            SharedStore.save(item)
            self.close()
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
