import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Saves the share payload into the app-group queue, enriches with metadata, then shows a reels-style confirmation before dismissing.
final class ShareViewController: UIViewController {

    private let extractTimeoutSeconds: TimeInterval = 2
    private var didFinishExtension = false
    private var hostingChild: UIViewController?

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
            saveQueueAndFinish(url: nil, text: nil, typeIds: [])
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

        if sharedURL != nil || !(sharedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            saveQueueAndFinish(url: sharedURL, text: sharedText, typeIds: typeIdentifiers)
            return
        }

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
            saveQueueAndFinish(url: sharedURL, text: sharedText, typeIds: typeIdentifiers)
        }

        group.notify(queue: .main) {
            completeExtraction()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + extractTimeoutSeconds) {
            completeExtraction()
        }
    }

    private func saveQueueAndFinish(url: String?, text: String?, typeIds: [String]) {
        let reelUrl: String? = {
            if let u = url?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty { return u }
            if let t = text?.trimmingCharacters(in: .whitespacesAndNewlines),
               let u = URL(string: t), u.scheme == "http" || u.scheme == "https" {
                return t
            }
            return nil
        }()
        guard let u = reelUrl else {
            presentNoLinkChrome()
            return
        }

        let id = ShareQueueStore.enqueue(reelUrl: u, shareText: text, attachmentTypeIdentifiers: typeIds)
        Task { @MainActor in
            guard let urlObj = URL(string: u) else {
                presentNoLinkChrome()
                return
            }
            let pack = await ReelMetadataService.extract(url: urlObj, shareText: text)
            ShareQueueStore.attachPack(id: id, pack: pack)
            if SharedStore.shareExtensionShowsConfirmationUI {
                presentConfirmation(queueItemId: id)
            } else {
                closeExtension()
            }
        }
    }

    private func presentNoLinkChrome() {
        let root = ShareExtensionNoLinkView { [weak self] in
            self?.teardownHostingAndComplete()
        }
        embedFullScreen(UIHostingController(rootView: root))
    }

    private func presentConfirmation(queueItemId: UUID) {
        let root = ShareReelsConfirmationView(
            queueItemId: queueItemId,
            onDone: { [weak self] in
                self?.teardownHostingAndComplete()
            },
            onOpenRoam: { [weak self] in
                self?.openRoamAppThenFinish()
            }
        )
        embedFullScreen(UIHostingController(rootView: root))
    }

    private func embedFullScreen<V: View>(_ host: UIHostingController<V>) {
        teardownHosting()
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        hostingChild = host
    }

    private func teardownHosting() {
        hostingChild?.willMove(toParent: nil)
        hostingChild?.view.removeFromSuperview()
        hostingChild?.removeFromParent()
        hostingChild = nil
    }

    private func teardownHostingAndComplete() {
        teardownHosting()
        closeExtension()
    }

    private func openRoamAppThenFinish() {
        if let url = URL(string: "roam://share") {
            extensionContext?.open(url, completionHandler: nil)
        }
        teardownHostingAndComplete()
    }

    private func closeExtension() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didFinishExtension else { return }
            self.didFinishExtension = true
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
