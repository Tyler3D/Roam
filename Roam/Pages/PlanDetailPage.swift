import EventKit
import SwiftUI

struct PlanDetailPage: View {
    let planId: String
    @Environment(\.apiClient) private var apiClient
    @Environment(\.eventKitService) private var eventKitService
    @Environment(\.roamStores) private var stores

    @State private var plan: Plan?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var vm: PlanSchedulingViewModel?

    var body: some View {
        Group {
            if let plan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection(plan)
                        if plan.status == .draft {
                            scheduleSection(plan)
                        }
                        if plan.status == .confirmed, plan.scheduledAt != nil {
                            calendarSection(plan)
                        }
                        membersSection(plan)
                        infoSection(plan)
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            } else if isLoading {
                ProgressView("Loading…")
                    .tint(RoamColors.loganDeep)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let errorText {
                Text(errorText)
                    .font(RoamFont.mono(11))
                    .foregroundStyle(RoamColors.error)
                    .padding()
            }
        }
        .background(RoamColors.background)
        .navigationTitle("plan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerSection(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.title)
                .font(RoamFont.display(22, italic: true))
                .foregroundStyle(RoamColors.text)

            statusPill(plan.status)

            if let at = plan.scheduledAt {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(RoamColors.textMid)
                    Text(at.formatted(date: .long, time: .shortened))
                        .font(RoamFont.mono(11))
                        .foregroundStyle(RoamColors.textMid)
                }
            }

            if let place = plan.placeName, !place.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "mappin")
                        .font(.system(size: 11))
                        .foregroundStyle(RoamColors.loganDeep)
                    Text(place)
                        .font(RoamFont.notes(14, italic: true))
                        .foregroundStyle(RoamColors.loganDark)
                }
            }
        }
    }

    @ViewBuilder
    private func statusPill(_ status: PlanStatus) -> some View {
        let (bg, fg): (Color, Color) = {
            switch status {
            case .draft: return (RoamColors.lavender, RoamColors.loganDeep)
            case .confirmed: return (RoamColors.greenTint, RoamColors.greenDeep)
            case .completed: return (RoamColors.loganDeep, .white)
            case .cancelled: return (RoamColors.error.opacity(0.12), RoamColors.error)
            }
        }()
        Text(status.rawValue.uppercased())
            .font(RoamFont.mono(9, weight: .semibold))
            .foregroundStyle(fg)
            .tracking(1.2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .clipShape(Capsule())
    }

    // MARK: - Schedule (draft only)

    @ViewBuilder
    private func scheduleSection(_ plan: Plan) -> some View {
        if let vm {
            VStack(alignment: .leading, spacing: 12) {
                Text("Schedule")
                    .font(RoamFont.mono(10, weight: .medium))
                    .foregroundStyle(RoamColors.textMuted)
                    .textCase(.uppercase)
                    .tracking(1)

                if let err = vm.errorText {
                    Text(err)
                        .font(RoamFont.mono(10))
                        .foregroundStyle(RoamColors.error)
                }

                if vm.isFetchingSlots {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(RoamColors.loganDeep)
                            .scaleEffect(0.8)
                        Text("Finding times…")
                            .font(RoamFont.mono(11))
                            .foregroundStyle(RoamColors.textMid)
                    }
                } else if vm.slots.isEmpty {
                    Button {
                        Task { await vm.loadSlots() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.clock")
                            Text("Suggest times")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(RoamColors.loganDeep)
                } else {
                    SlotPickerView(
                        slots: vm.slots,
                        conflicts: vm.slotConflicts,
                        hasConflictData: eventKitService.hasReadAccess,
                        selectedSlot: Binding(
                            get: { vm.selectedSlot },
                            set: { vm.selectedSlot = $0 }
                        ),
                        isConfirming: vm.isConfirming,
                        onConfirm: {
                            guard let slot = vm.selectedSlot else { return }
                            Task {
                                if let updated = await vm.confirmSlot(slot, stores: stores.plans) {
                                    self.plan = updated
                                }
                            }
                        }
                    )
                }
            }
            .padding(16)
            .background(RoamColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(RoamColors.reviewBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Calendar (confirmed only)

    @ViewBuilder
    private func calendarSection(_ plan: Plan) -> some View {
        if let vm {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add to calendar")
                    .font(RoamFont.mono(10, weight: .medium))
                    .foregroundStyle(RoamColors.textMuted)
                    .textCase(.uppercase)
                    .tracking(1)

                if let err = vm.errorText {
                    Text(err)
                        .font(RoamFont.mono(10))
                        .foregroundStyle(RoamColors.error)
                }

                // Native calendar button
                Button {
                    Task { await vm.addToNativeCalendar(plan: plan) }
                } label: {
                    HStack(spacing: 8) {
                        if vm.isAddingToEK {
                            ProgressView().tint(RoamColors.loganDeep).scaleEffect(0.8)
                        } else if vm.ekEventIdentifier != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(RoamColors.greenDeep)
                        } else {
                            Image(systemName: "calendar.badge.plus")
                        }
                        Text(vm.ekEventIdentifier != nil ? "Added to device calendar" : "Add to device calendar")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                }
                .background(RoamColors.surface)
                .foregroundStyle(vm.ekEventIdentifier != nil ? RoamColors.greenDeep : RoamColors.loganDeep)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            vm.ekEventIdentifier != nil ? RoamColors.greenDeep.opacity(0.4) : RoamColors.reviewBorder,
                            lineWidth: 1
                        )
                )
                .disabled(vm.isAddingToEK || vm.ekEventIdentifier != nil)

                // Google Calendar button
                Button {
                    Task { await vm.addToGoogleCalendar() }
                } label: {
                    HStack(spacing: 8) {
                        if vm.isAddingToGCal {
                            ProgressView().tint(RoamColors.loganDeep).scaleEffect(0.8)
                        } else if vm.calendarResponse?.flow == "oauth" {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(RoamColors.greenDeep)
                        } else {
                            Image(systemName: "calendar")
                        }
                        Text(vm.calendarResponse?.flow == "oauth" ? "Added to Google Calendar" : "Add to Google Calendar")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                }
                .background(RoamColors.surface)
                .foregroundStyle(vm.calendarResponse?.flow == "oauth" ? RoamColors.greenDeep : RoamColors.loganDeep)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            vm.calendarResponse?.flow == "oauth" ? RoamColors.greenDeep.opacity(0.4) : RoamColors.reviewBorder,
                            lineWidth: 1
                        )
                )
                .disabled(vm.isAddingToGCal || vm.calendarResponse?.flow == "oauth")
            }
            .padding(16)
            .background(RoamColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(RoamColors.reviewBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Members

    @ViewBuilder
    private func membersSection(_ plan: Plan) -> some View {
        let members = plan.resolvedMembers
        if !members.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Attendees")
                    .font(RoamFont.mono(10, weight: .medium))
                    .foregroundStyle(RoamColors.textMuted)
                    .textCase(.uppercase)
                    .tracking(1)

                ForEach(members) { member in
                    HStack(spacing: 10) {
                        // Initials avatar
                        let initials = memberInitials(member)
                        Text(initials)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(RoamColors.loganDeep)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text([member.firstName, member.lastName]
                                .compactMap { $0 }
                                .filter { !$0.isEmpty }
                                .joined(separator: " ")
                                .nilIfEmpty ?? "Member")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(RoamColors.text)
                            Text(member.role.rawValue.capitalized)
                                .font(RoamFont.mono(9))
                                .foregroundStyle(RoamColors.textMuted)
                        }

                        Spacer()

                        rsvpPill(member.rsvpStatus)
                    }
                }
            }
            .padding(16)
            .background(RoamColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(RoamColors.reviewBorder, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func rsvpPill(_ status: RsvpStatus) -> some View {
        let (label, fg, bg): (String, Color, Color) = {
            switch status {
            case .pending: return ("Pending", RoamColors.textMuted, RoamColors.lavender)
            case .accepted: return ("Going", RoamColors.greenDeep, RoamColors.greenTint)
            case .declined: return ("Declined", RoamColors.error, RoamColors.error.opacity(0.1))
            }
        }()
        Text(label)
            .font(RoamFont.mono(9, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .clipShape(Capsule())
    }

    // MARK: - Info

    @ViewBuilder
    private func infoSection(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 11))
                    .foregroundStyle(RoamColors.textMuted)
                Text(formatDuration(plan.estimatedMinutes))
                    .font(RoamFont.mono(11))
                    .foregroundStyle(RoamColors.textMid)
            }

            if !plan.taskNotes.isEmpty {
                Text(plan.taskNotes)
                    .font(RoamFont.mono(11))
                    .foregroundStyle(RoamColors.textMid)
            }

            Text("Code: \(plan.shareCode)")
                .font(RoamFont.mono(9))
                .foregroundStyle(RoamColors.textMuted)
        }
    }

    // MARK: - Helpers

    private func memberInitials(_ member: PlanMemberRead) -> String {
        let f = member.firstName?.first.map(String.init) ?? ""
        let l = member.lastName?.first.map(String.init) ?? ""
        let combined = (f + l).uppercased()
        return combined.isEmpty ? "?" : combined
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let fetched = try await apiClient.getPlan(id: planId)
            plan = fetched
            vm = PlanSchedulingViewModel(
                planId: planId,
                apiClient: apiClient,
                eventKitService: eventKitService
            )
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
