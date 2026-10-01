import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct SessionWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: "clock").font(.title2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("FrekiHub · OJT").font(.headline)
                    Text("Clocked in \(context.state.started.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    Text(context.state.started, style: .timer).monospacedDigit().font(.title2)
                }
                Spacer()
                if #available(iOS 17.0, *) {
                    Button(intent: ClockOutIntent(id: context.attributes.id)) { Image(systemName: "stop.fill") }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                } else { Link("Clock out", destination: URL(string: "frekihub://clock-out")!) }
            }.padding(20).activityBackgroundTint(Color(white: 0.14)).activitySystemActionForegroundColor(.white).foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("FrekiHub", systemImage: "clock").font(.caption) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.state.started, style: .timer).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Clocked in \(context.state.started.formatted(date: .omitted, time: .shortened))").font(.caption)
                            HStack { Text("Today"); Text(context.state.started.addingTimeInterval(-Double(context.state.todaySeconds)), style: .timer).monospacedDigit() }.font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if #available(iOS 17.0, *) { Button("Clock out", intent: ClockOutIntent(id: context.attributes.id)).buttonStyle(.bordered).buttonBorderShape(.capsule) }
                        else { Link("Clock out", destination: URL(string: "frekihub://clock-out")!) }
                    }.padding(.top, 12)
                }
            } compactLeading: { Image(systemName: "clock") } compactTrailing: { Text(context.state.started, style: .timer).monospacedDigit().frame(width: 62) } minimal: {
                ZStack { ProgressView(timerInterval: context.state.started...context.state.started.addingTimeInterval(8 * 3600), countsDown: false).progressViewStyle(.circular).tint(.white); Image(systemName: "clock").font(.system(size: 10)) }.frame(width: 20, height: 20)
            }.keylineTint(.white)
        }
    }
}
@main
struct FrekiHubWidgetBundle: WidgetBundle {
    var body: some Widget { SessionWidget() }
}
