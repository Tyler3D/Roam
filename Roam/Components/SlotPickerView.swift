import EventKit
import SwiftUI

struct SlotPickerView: View {
    let slots: [APIClient.SlotSuggestion]
    let conflicts: [Date: [EKEvent]]
    let hasConflictData: Bool
    @Binding var selectedSlot: APIClient.SlotSuggestion?
    let isConfirming: Bool
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(slots) { slot in
                slotRow(slot)
            }

            Button(action: onConfirm) {
                Group {
                    if isConfirming {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Confirm time")
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .background(selectedSlot != nil ? RoamColors.loganDeep : RoamColors.logan)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .disabled(selectedSlot == nil || isConfirming)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func slotRow(_ slot: APIClient.SlotSuggestion) -> some View {
        let isSelected = selectedSlot?.start == slot.start
        let conflictList = conflicts[slot.start] ?? []

        Button {
            selectedSlot = slot
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(slot.label)
                    .font(RoamFont.mono(11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? RoamColors.loganDeep : RoamColors.text)

                if hasConflictData {
                    if conflictList.isEmpty {
                        Text("You're free")
                            .font(RoamFont.mono(9))
                            .foregroundStyle(RoamColors.greenDeep)
                    } else {
                        Text("Conflicts with \(conflictList.count) event\(conflictList.count == 1 ? "" : "s")")
                            .font(RoamFont.mono(9))
                            .foregroundStyle(RoamColors.error)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? RoamColors.lavender : RoamColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? RoamColors.loganDeep.opacity(0.6) : RoamColors.reviewBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
