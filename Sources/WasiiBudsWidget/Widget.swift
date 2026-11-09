import BudsWidgetData
import SwiftUI
import WidgetKit

@main
struct WasiiBudsWidgetBundle: WidgetBundle {
    var body: some Widget { WasiiBudsStatusWidget() }
}

private struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, snapshot: WidgetSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: .now, snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        completion(Timeline(entries: [
            StatusEntry(date: .now, snapshot: WidgetSnapshotStore.load())
        ], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

private struct WasiiBudsStatusWidget: Widget {
    let kind = "WasiiBudsStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(Color.white, for: .widget)
        }
        .configurationDisplayName("WasiiBuds")
        .description("Earbud battery and quick access to listening modes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct StatusWidgetView: View {
    let entry: StatusEntry
    @Environment(\.widgetFamily) private var family
    private let ink = Color(red: 0.055, green: 0.065, blue: 0.075)
    private let muted = Color(red: 0.37, green: 0.39, blue: 0.41)
    private let accent = Color(red: 0.78, green: 0.22, blue: 0.08)

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("WASII / BUDS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(0.7).foregroundStyle(accent)
                Spacer()
                Circle().fill(entry.snapshot?.connected == true ? accent : muted.opacity(0.4))
                    .frame(width: 7, height: 7)
            }
            HStack(spacing: family == .systemSmall ? 10 : 23) {
                battery("LEFT", level: entry.snapshot?.left)
                battery("RIGHT", level: entry.snapshot?.right)
                if family == .systemMedium {
                    battery("CASE", level: entry.snapshot?.caseLevel)
                }
            }
            Spacer(minLength: 0)
            if family == .systemMedium {
                HStack(spacing: 7) {
                    modeLink("Off", path: "off")
                    modeLink("ANC", path: "deep")
                    modeLink("Aware", path: "transparency")
                }
            } else {
                Text(entry.snapshot?.mode ?? "Open to connect")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
            }
            if let updated = entry.snapshot?.batteryUpdatedAt {
                Text("Battery · \(updated, style: .relative) ago")
                    .font(.system(size: 9))
                    .foregroundStyle(muted)
                    .lineLimit(1)
            } else {
                Text("Open WasiiBuds for battery")
                    .font(.system(size: 9))
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
        }
        .padding(family == .systemSmall ? 13 : 17)
        .widgetURL(URL(string: "wasiibuds://buds"))
    }

    private func battery(_ label: String, level: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(0.5).foregroundStyle(muted)
            Text(level.map { "\($0)%" } ?? "—")
                .font(.system(size: family == .systemSmall ? 23 : 29,
                              weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modeLink(_ title: String, path: String) -> some View {
        Link(destination: URL(string: "wasiibuds://anc/\(path)")!) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(Color(red: 0.965, green: 0.965, blue: 0.955),
                            in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
