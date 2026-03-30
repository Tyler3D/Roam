import EventKit
import Foundation
import UIKit

@MainActor
@Observable
final class PlanSchedulingViewModel {
    let planId: String
    private let apiClient: APIClient
    private let eventKitService: EventKitService

    // Slot suggestion state
    var slots: [APIClient.SlotSuggestion] = []
    var isFetchingSlots = false
    var selectedSlot: APIClient.SlotSuggestion?
    var slotConflicts: [Date: [EKEvent]] = [:]

    // Confirm state
    var isConfirming = false

    // Google Calendar state
    var calendarResponse: APIClient.CalendarEventResponse?
    var isAddingToGCal = false

    // Native calendar state
    var ekEventIdentifier: String?
    var isAddingToEK = false

    var errorText: String?

    init(planId: String, apiClient: APIClient, eventKitService: EventKitService) {
        self.planId = planId
        self.apiClient = apiClient
        self.eventKitService = eventKitService
    }

    // MARK: - Slot suggestion

    func loadSlots() async {
        isFetchingSlots = true
        errorText = nil
        defer { isFetchingSlots = false }
        do {
            slots = try await apiClient.suggestSlots(planId: planId)
            checkConflicts()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func checkConflicts() {
        guard eventKitService.hasReadAccess else { return }
        var result: [Date: [EKEvent]] = [:]
        for slot in slots {
            let conflicts = eventKitService.conflictingEvents(from: slot.start, to: slot.end)
            result[slot.start] = conflicts
        }
        slotConflicts = result
    }

    // MARK: - Confirm slot

    func confirmSlot(_ slot: APIClient.SlotSuggestion, stores: PlansQueryStore) async -> Plan? {
        isConfirming = true
        errorText = nil
        defer { isConfirming = false }
        do {
            let payload = APIClient.PlanUpdatePayload(
                scheduledAt: slot.start,
                status: "confirmed",
                estimatedMinutes: Int(slot.end.timeIntervalSince(slot.start) / 60)
            )
            let updated = try await apiClient.updatePlan(id: planId, payload: payload)
            stores.upsert(updated)
            return updated
        } catch {
            errorText = error.localizedDescription
            return nil
        }
    }

    // MARK: - Google Calendar

    func addToGoogleCalendar() async {
        isAddingToGCal = true
        errorText = nil
        defer { isAddingToGCal = false }
        do {
            let response = try await apiClient.createGCalEvent(planId: planId)
            calendarResponse = response
            if response.flow == "link", let urlString = response.gcalLink, let url = URL(string: urlString) {
                await UIApplication.shared.open(url)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Native Calendar

    func addToNativeCalendar(plan: Plan) async {
        isAddingToEK = true
        errorText = nil
        defer { isAddingToEK = false }

        let granted = await eventKitService.requestCalendarAccess()
        guard granted else {
            errorText = "Calendar access denied. Enable it in Settings → Roam."
            return
        }

        guard let startDate = plan.scheduledAt else {
            errorText = "Plan has no scheduled time."
            return
        }
        let endDate = startDate.addingTimeInterval(Double(plan.estimatedMinutes) * 60)
        let notes = "Planned via Roam · roam.app/plans/\(plan.shareCode)"

        do {
            let identifier = try eventKitService.saveEvent(
                title: plan.title,
                startDate: startDate,
                endDate: endDate,
                location: plan.placeName,
                notes: notes
            )
            ekEventIdentifier = identifier
        } catch {
            errorText = "Could not save to calendar: \(error.localizedDescription)"
        }
    }
}
