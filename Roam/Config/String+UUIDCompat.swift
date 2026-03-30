import Foundation

/// Temporary compatibility shim: allow `.uuidString` on `String` where callers already
/// have a UUID string. This avoids compile errors if a `String` is mistakenly treated
/// like a `UUID`. Prefer correcting call sites to avoid relying on this.
extension String {
    /// Returns `self` so code that expects a UUID string can proceed.
    var uuidString: String { self }
}
