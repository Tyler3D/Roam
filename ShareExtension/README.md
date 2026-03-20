# ShareExtension (reference only)

This folder is **not** wired as an Xcode target in `Roam.xcodeproj`. The app embeds and ships the **`reel-ingestion`** share extension (`reel-ingestion/`), which uses the same flow: extract URL/text → `SharedStore.save` → app group `group.columbiastartupstudio.Roam`.

Files here mirror that logic for documentation or future extraction into a shared framework. Edit **`reel-ingestion/ShareViewController.swift`** for behavior changes.
