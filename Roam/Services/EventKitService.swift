import EventKit
import Foundation

/// Manages native iOS calendar access for adding confirmed plans to the device calendar.
final class EventKitService: @unchecked Sendable {
    private let store = EKEventStore()

    // MARK: - Authorization

    /// Requests write-only calendar access (iOS 17+) or full access (iOS 16).
    /// Returns true if the app can write events.
    func requestCalendarAccess() async -> Bool {
        let current = EKEventStore.authorizationStatus(for: .event)
        switch current {
        case .authorized, .fullAccess, .writeOnly:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            break
        @unknown default:
            return false
        }

        do {
            if #available(iOS 17, *) {
                return try await store.requestWriteOnlyAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }

    var hasWriteAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17, *) {
            return status == .writeOnly || status == .fullAccess
        }
        return status == .authorized
    }

    var hasReadAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    // MARK: - Save Event

    /// Saves a new event to the default calendar. Returns the EKEvent.eventIdentifier.
    func saveEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        location: String?,
        notes: String?
    ) throws -> String {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.location = location
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    // MARK: - Conflict Detection

    /// Returns events overlapping [start, end]. Only works with full read access.
    func conflictingEvents(from start: Date, to end: Date) -> [EKEvent] {
        guard hasReadAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
    }
}
