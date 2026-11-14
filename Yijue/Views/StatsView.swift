import Charts
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var store: SleepStore
    @State private var period: StatsPeriod = .week

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("范围", selection: $period) {
                        ForEach(StatsPeriod.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    summaryGrid

                    if hasData {
                        durationCard
                        bedtimeCard
                        wakeCard
                    } else {
                        emptyCard
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("统计")
        }
    }

    // MARK: - 数据

    private var points: [NightPoint] {
        SleepStatistics.points(records: store.records, period: period)
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
