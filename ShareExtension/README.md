# ShareExtension (reference only)

This folder is **not** wired as an Xcode target in `Roam.xcodeproj`. The app embeds and ships the **`reel-ingestion`** share extension (`reel-ingestion/`), which:

1. Extracts URL/text from the share sheet  
2. Enqueues into app-group [`ShareQueueStore`](../Roam/ShareQueue/ShareQueueStore.swift) and runs [`ReelMetadataService`](../Roam/Services/ReelMetadataService.swift)  
3. Presents [`ShareReelsConfirmationView`](../reel-ingestion/ShareReelsConfirmationView.swift) (reels-style grid + “Reel saved” ribbon) before dismissing  

The main app writes a slim [`ReelsGridPreviewSnapshot`](../Roam/ShareQueue/ReelsGridPreviewSnapshot.swift) into the app group when reels refresh so the extension can show placeholder tiles next to the new item.

Edit **`reel-ingestion/ShareViewController.swift`** and **`reel-ingestion/ShareReelsConfirmationView.swift`** for share UX changes.
