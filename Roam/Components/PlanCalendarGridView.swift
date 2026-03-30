import SwiftUI

struct PlanCalendarGridView: View {
    let plans: [Plan]

    @State private var displayedMonth = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDay: Date?

    private let calendar = Calendar.current
    private let dayColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
            weekdayRow
            daysGrid
            if let day = selectedDay {
                planListForDay(day)
            }
        }
    }

    // MARK: - Month header

    private var monthHeader: some View {
        HStack {
            Button {
                displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                selectedDay = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RoamColors.loganDeep)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(RoamFont.display(17, italic: true))
                .foregroundStyle(RoamColors.text)

            Spacer()

            Button {
                displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                selectedDay = nil
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RoamColors.loganDeep)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Weekday row

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(RoamFont.mono(9, weight: .medium))
                    .foregroundStyle(RoamColors.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    // MARK: - Days grid

    private var daysGrid: some View {
        let cells = makeDayCells()
        return LazyVGrid(columns: dayColumns, spacing: 4) {
            ForEach(cells, id: \.date) { cell in
                DayCell(
                    cell: cell,
                    isToday: calendar.isDateInToday(cell.date),
                    isSelected: selectedDay.map { calendar.isDate($0, inSameDayAs: cell.date) } ?? false,
                    hasPlans: !plansOnDay(cell.date).isEmpty
                )
                .onTapGesture {
                    if !plansOnDay(cell.date).isEmpty {
                        selectedDay = calendar.isDate(cell.date, inSameDayAs: selectedDay ?? .distantPast) ? nil : cell.date
                    }
                }
                .opacity(cell.isCurrentMonth ? 1 : 0.3)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Plan list for selected day

    @ViewBuilder
    private func planListForDay(_ day: Date) -> some View {
        let dayPlans = plansOnDay(day)
        if !dayPlans.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(day.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(RoamFont.mono(10, weight: .medium))
                    .foregroundStyle(RoamColors.textMuted)
                    .textCase(.uppercase)
                    .tracking(1)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                ForEach(dayPlans) { plan in
                    NavigationLink(value: plan.id.uuidString.lowercased()) {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(RoamColors.loganDeep)
                                .frame(width: 4, height: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(RoamColors.text)
                                if let at = plan.scheduledAt {
                                    Text(at.formatted(.dateTime.hour().minute()))
                                        .font(RoamFont.mono(10))
                                        .foregroundStyle(RoamColors.textMid)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundStyle(RoamColors.textMuted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(RoamColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Helpers

    private func plansOnDay(_ date: Date) -> [Plan] {
        plans.filter { plan in
            guard let at = plan.scheduledAt else { return false }
            return calendar.isDate(at, inSameDayAs: date)
        }
        .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }
    }

    private struct DayCell: View {
        let cell: CalendarDayCell
        let isToday: Bool
        let isSelected: Bool
        let hasPlans: Bool

        var body: some View {
            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: cell.date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? .white : (isSelected ? RoamColors.loganDeep : RoamColors.text))
                    .frame(width: 32, height: 32)
                    .background(
                        Group {
                            if isToday {
                                Circle().fill(RoamColors.loganDeep)
                            } else if isSelected {
                                Circle().fill(RoamColors.lavender)
                            } else {
                                Circle().fill(Color.clear)
                            }
                        }
                    )

                Circle()
                    .fill(hasPlans ? RoamColors.reviewAccent : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
    }

    private struct CalendarDayCell {
        let date: Date
        let isCurrentMonth: Bool
    }

    private func makeDayCells() -> [CalendarDayCell] {
        var cells: [CalendarDayCell] = []
        let firstOfMonth = displayedMonth
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) - 1
        let range = calendar.range(of: .day, in: .month, for: firstOfMonth)!

        // Leading days from previous month
        for i in (0..<firstWeekday).reversed() {
            if let date = calendar.date(byAdding: .day, value: -(i + 1), to: firstOfMonth) {
                cells.append(CalendarDayCell(date: date, isCurrentMonth: false))
            }
        }

        // Days of current month
        for day in 1...range.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                cells.append(CalendarDayCell(date: date, isCurrentMonth: true))
            }
        }

        // Trailing days to fill grid (up to 42 cells)
        while cells.count < 42 {
            if let last = cells.last, let date = calendar.date(byAdding: .day, value: 1, to: last.date) {
                cells.append(CalendarDayCell(date: date, isCurrentMonth: false))
            } else { break }
        }

        return cells
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
