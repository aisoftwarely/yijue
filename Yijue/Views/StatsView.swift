import Charts
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var store: SleepStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var period: StatsPeriod = .week
    /// 正在查看的时间段：周视图按 7 天、月视图按自然月。
    @State private var anchor: Date = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    periodPicker
                    periodHeader
                    content
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("统计")
            .onChange(of: period) { _, _ in
                anchor = Date()
            }
        }
    }

    private var periodPicker: some View {
        Picker("范围", selection: $period) {
            ForEach(StatsPeriod.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var content: some View {
        if hasData {
            narrativeCard
            summaryGrid

            if period == .month {
                calendarCard
            }

            durationCard
            bedtimeCard
            wakeCard
        } else {
            emptyCard
        }
    }

    // MARK: - 时间段切换

    private var periodHeader: some View {
        HStack {
            Button {
                shiftPeriod(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(period == .week ? "上一周" : "上个月")

            Spacer()

            Text(periodTitle)
                .font(.headline)

            Spacer()

            Button {
                shiftPeriod(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isCurrentPeriod)
            .accessibilityLabel(period == .week ? "下一周" : "下个月")
        }
    }

    private var periodTitle: String {
        if period == .month {
            let components = Calendar.current.dateComponents([.year, .month], from: anchor)
            return "\(components.year ?? 0) 年 \(components.month ?? 0) 月"
        }
        guard let first = points.first?.day, let last = points.last?.day else {
            return "最近 7 晚"
        }
        return "\(SleepCalendar.shortDayFormatter.string(from: first)) – \(SleepCalendar.shortDayFormatter.string(from: last))"
    }

    private var isCurrentPeriod: Bool {
        let calendar = Calendar.current
        switch period {
        case .week:
            return anchor >= calendar.startOfDay(for: Date())
        case .month:
            return calendar.isDate(anchor, equalTo: Date(), toGranularity: .month)
        }
    }

    private func shiftPeriod(_ direction: Int) {
        let calendar = Calendar.current
        switch period {
        case .week:
            anchor = calendar.date(byAdding: .day, value: 7 * direction, to: anchor) ?? anchor
        case .month:
            anchor = calendar.date(byAdding: .month, value: direction, to: anchor) ?? anchor
        }
    }

    // MARK: - 数据

    private var points: [NightPoint] {
        SleepStatistics.points(records: store.records, period: period, now: anchor)
    }

    private var periodRecords: [SleepRecord] {
        points.compactMap(\.record)
    }

    private var completeRecords: [SleepRecord] {
        SleepStatistics.completedRecords(periodRecords)
    }

    private var hasData: Bool { !completeRecords.isEmpty }

    private var averageDurationText: String {
        guard let average = SleepStatistics.averageDuration(periodRecords) else { return "—" }
        return SleepCalendar.durationText(average)
    }

    private var averageBedText: String {
        guard let minutes = SleepStatistics.averageBedMinutes(periodRecords) else { return "—" }
        return SleepCalendar.clockText(minutes: minutes)
    }

    private var averageWakeText: String {
        guard let minutes = SleepStatistics.averageWakeMinutes(periodRecords) else { return "—" }
        return SleepCalendar.clockText(minutes: minutes)
    }

    private var metGoalText: String {
        let met = SleepStatistics.metGoalCount(periodRecords, goalMinutes: store.settings.goalMinutes)
        return "\(met)/\(completeRecords.count) 晚"
    }

    private var streakText: String {
        "\(SleepStatistics.streak(records: store.records, goalMinutes: store.settings.goalMinutes)) 晚"
    }

    private var spreadText: String {
        guard let spread = SleepStatistics.bedtimeSpreadMinutes(periodRecords) else { return "—" }
        return "±\(Int(spread.rounded())) 分"
    }

    private var maxDurationHours: Double {
        completeRecords.compactMap(\.duration).map { $0 / 3600 }.max() ?? 8
    }

    private var durationDomain: ClosedRange<Double> {
        0...max(10, maxDurationHours + 1)
    }

    private var bedDomain: ClosedRange<Double> {
        let values = completeRecords.compactMap { record in
            record.bedTime.map { SleepCalendar.signedMinutes($0) }
        }.map(Double.init)
        guard let low = values.min(), let high = values.max() else { return -240...120 }
        return (low - 30)...(high + 30)
    }

    private var wakeDomain: ClosedRange<Double> {
        let values = completeRecords.compactMap { record in
            record.wakeTime.map { SleepCalendar.minutesOfDay($0) }
        }.map(Double.init)
        guard let low = values.min(), let high = values.max() else { return 240...720 }
        return max(0, low - 30)...min(1440, max(high + 30, low + 60))
    }

    // MARK: - 摘要

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            statTile(title: "平均睡眠", value: averageDurationText)
            statTile(title: "平均入睡", value: averageBedText)
            statTile(title: "平均起床", value: averageWakeText)
            statTile(title: "达标天数", value: metGoalText)
            statTile(title: "连续达标", value: streakText)
            statTile(title: "入睡波动", value: spreadText)
        }
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    // MARK: - 文字小结

    private var narrativeText: String {
        guard let average = SleepStatistics.averageDuration(periodRecords) else {
            return "这个时段还没有完整记录。"
        }

        var parts: [String] = ["平均每晚 \(SleepCalendar.durationText(average))"]

        if let previous = previousAverage {
            let delta = average - previous
            if abs(delta) < 5 * 60 {
                parts.append("和上一期差不多")
            } else if delta > 0 {
                parts.append("比上一期多睡 \(SleepCalendar.durationText(delta))")
            } else {
                parts.append("比上一期少睡 \(SleepCalendar.durationText(-delta))")
            }
        }

        let met = SleepStatistics.metGoalCount(periodRecords, goalMinutes: store.settings.goalMinutes)
        if !completeRecords.isEmpty {
            parts.append("达标 \(met)/\(completeRecords.count) 晚")
        }

        let debt = SleepStatistics.sleepDebt(periodRecords, goalMinutes: store.settings.goalMinutes)
        if debt < 60 {
            parts.append("没有睡眠债")
        } else {
            parts.append("本期睡眠债 \(SleepCalendar.durationText(debt))")
        }

        return parts.joined(separator: "，") + "。"
    }

    private var previousAverage: TimeInterval? {
        let calendar = Calendar.current
        let component: Calendar.Component = period == .week ? .day : .month
        let step = period == .week ? -7 : -1
        guard let previousAnchor = calendar.date(byAdding: component, value: step, to: anchor) else {
            return nil
        }
        let records = SleepStatistics
            .points(records: store.records, period: period, now: previousAnchor)
            .compactMap(\.record)
        return SleepStatistics.averageDuration(records)
    }

    private var narrativeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text("小结")
                    .font(.subheadline.weight(.semibold))
                Text(narrativeText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 月历热力图

    private var calendarCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("每日睡眠")
                    .font(.subheadline.weight(.semibold))

                LazyVGrid(columns: heatColumns, spacing: 4) {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(0..<leadingBlankCount, id: \.self) { _ in
                        Color.clear.frame(height: 42)
                    }
                    ForEach(points) { point in
                        heatCell(point)
                    }
                }

                HStack(spacing: 6) {
                    Text("少")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(0..<4, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(heatColor(level: level))
                            .frame(width: 18, height: 8)
                    }
                    Text("多")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("深色 = 达到目标")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var heatColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    /// 月份第一天之前要空几格；中文习惯周一开头。
    private var leadingBlankCount: Int {
        guard let first = points.first?.day else { return 0 }
        let weekday = Calendar.current.component(.weekday, from: first)
        return (weekday + 5) % 7
    }

    private func heatLevel(for point: NightPoint) -> Int? {
        guard let duration = point.duration else { return nil }
        let ratio = duration / max(60, store.goalInterval)
        if ratio >= 1 { return 3 }
        if ratio >= 0.85 { return 2 }
        if ratio >= 0.6 { return 1 }
        return 0
    }

    private func heatColor(level: Int) -> Color {
        let steps: [Double] = colorScheme == .dark
            ? [0.32, 0.55, 0.78, 1.0]
            : [0.15, 0.38, 0.65, 1.0]
        let index = min(max(level, 0), steps.count - 1)
        return Color.accentColor.opacity(steps[index])
    }

    private func heatCell(_ point: NightPoint) -> some View {
        let day = Calendar.current.component(.day, from: point.day)
        let level = heatLevel(for: point)

        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(level.map { heatColor(level: $0) } ?? Color(.systemFill))
            Text("\(day)")
                .font(.caption2)
                .foregroundStyle(level == 3 ? Color.white : Color.primary)
        }
        .frame(height: 42)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day) 日")
        .accessibilityValue(heatAccessibilityText(for: point))
    }

    private func heatAccessibilityText(for point: NightPoint) -> String {
        guard let duration = point.duration else { return "没有记录" }
        return "睡了 \(SleepCalendar.durationText(duration))"
    }

    // MARK: - 图表

    private var durationCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("睡眠时长")
                    .font(.subheadline.weight(.semibold))

                Chart {
                    ForEach(points) { point in
                        if let duration = point.duration {
                            BarMark(
                                x: .value("夜晚", point.day, unit: .day),
                                y: .value("小时", duration / 3600)
                            )
                            .foregroundStyle(
                                store.meetsGoal(point.record)
                                    ? Color.accentColor
                                    : Color.accentColor.opacity(0.35)
                            )
                            .cornerRadius(3)
                        }
                    }

                    RuleMark(y: .value("目标", Double(store.settings.goalMinutes) / 60))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
                .chartYScale(domain: durationDomain)
                .chartXAxis { xAxis }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartLegend(.hidden)
                .frame(height: 170)
            }
        }
    }

    private var bedtimeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("入睡时间")
                    .font(.subheadline.weight(.semibold))

                Chart {
                    ForEach(points) { point in
                        if let minutes = point.bedSignedMinutes {
                            LineMark(
                                x: .value("夜晚", point.day, unit: .day),
                                y: .value("入睡", Double(minutes))
                            )
                            .foregroundStyle(Color.accentColor)
                            .interpolationMethod(.monotone)

                            PointMark(
                                x: .value("夜晚", point.day, unit: .day),
                                y: .value("入睡", Double(minutes))
                            )
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .chartYScale(domain: bedDomain)
                .chartXAxis { xAxis }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(SleepCalendar.clockText(minutes: Int(minutes)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 150)
            }
        }
    }

    private var wakeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("起床时间")
                    .font(.subheadline.weight(.semibold))

                Chart {
                    ForEach(points) { point in
                        if let minutes = point.wakeMinutes {
                            LineMark(
                                x: .value("夜晚", point.day, unit: .day),
                                y: .value("起床", Double(minutes))
                            )
                            .foregroundStyle(Color.orange)
                            .interpolationMethod(.monotone)

                            PointMark(
                                x: .value("夜晚", point.day, unit: .day),
                                y: .value("起床", Double(minutes))
                            )
                            .foregroundStyle(Color.orange)
                        }
                    }
                }
                .chartYScale(domain: wakeDomain)
                .chartXAxis { xAxis }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(SleepCalendar.clockText(minutes: Int(minutes)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 150)
            }
        }
    }

    @AxisContentBuilder
    private var xAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 5)) { value in
            AxisGridLine()
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(SleepCalendar.shortDayFormatter.string(from: date))
                        .font(.caption2)
                }
            }
        }
    }

    private var emptyCard: some View {
        card {
            VStack(spacing: 10) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                Text("还没有足够的数据")
                    .font(.headline)
                Text("记录几晚之后，这里会显示时长和作息趋势。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

#Preview {
    StatsView()
        .environmentObject(SleepStore.shared)
}
