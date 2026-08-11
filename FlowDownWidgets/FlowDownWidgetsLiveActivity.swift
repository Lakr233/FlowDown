//
//  FlowDownWidgetsLiveActivity.swift
//  FlowDownWidgets
//
//  Created by qaq on 7/1/2026.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct FlowDownWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlowDownWidgetsAttributes.self) { context in
            let finished = context.state.conversationCount <= 0
            let text = finished
                ? String(localized: "All conversation(s) completed.")
                : String(localized: "Streaming \(context.state.conversationCount) conversation(s).")

            VStack {
                HStack(spacing: 16) {
                    Image(systemName: "bird")
                        .font(.largeTitle)
                        .bold()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center, spacing: 4) {
                            Text(String("FlowDown"))
                                .bold()
                            Spacer()
                            Group {
                                if finished {
                                    Image(systemName: "checkmark.circle.fill")
                                } else {
                                    Image(systemName: "arrow.down")
                                    Text(String(context.state.streamingSessionTextCount))
                                }
                            }
                            .monospaced()
                            .opacity(0.5)
                        }
                        Text(text)
                            .contentTransition(.numericText())
                    }
                    .font(.body)
                }
            }
            .foregroundStyle(.white)
            .padding()
            .animation(.interactiveSpring, value: context.state)
            .activityBackgroundTint(.accent)
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "flowdown://live-activity"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    let finished = context.state.conversationCount <= 0
                    let text = finished
                        ? String(localized: "All conversation(s) completed.")
                        : String(localized: "Streaming \(context.state.conversationCount) conversation(s).")

                    VStack(spacing: 8) {
                        Spacer()

                        Image(systemName: "bird.fill")
                            .bold()

                        Text(text)
                            .contentTransition(.numericText())
                            .animation(.interactiveSpring, value: context.state)
                    }
                    .font(.footnote)
                }
            } compactLeading: {
                let finished = context.state.conversationCount <= 0

                Image(systemName: "bird.fill")
                    .foregroundStyle(finished ? .accent : .white)
                    .animation(.interactiveSpring, value: context.state)
            } compactTrailing: {
                let finished = context.state.conversationCount <= 0
                let tokenCount = context.state.streamingSessionTextCount

                if finished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(finished ? .accent : .white)
                        .animation(.interactiveSpring, value: context.state)
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                        Text(String(tokenCount))
                            .contentTransition(.numericText())
                    }
                    .font(.footnote)
                    .animation(.interactiveSpring, value: context.state)
                }
            } minimal: {
                let finished = context.state.conversationCount <= 0

                Image(systemName: "bird.fill")
                    .foregroundStyle(finished ? .accent : .white)
                    .animation(.interactiveSpring, value: context.state)
                    .widgetURL(URL(string: "flowdown://live-activity"))
            }
        }
    }
}

private extension FlowDownWidgetsAttributes {
    static var preview: FlowDownWidgetsAttributes {
        FlowDownWidgetsAttributes()
    }
}

private extension FlowDownWidgetsAttributes.ContentState {
    static var none: FlowDownWidgetsAttributes.ContentState {
        FlowDownWidgetsAttributes.ContentState(
            conversationCount: 0,
            streamingSessionTextCount: 0,
        )
    }

    static var doing: FlowDownWidgetsAttributes.ContentState {
        FlowDownWidgetsAttributes.ContentState(
            conversationCount: 1,
            streamingSessionTextCount: 100,
        )
    }

    static var done: FlowDownWidgetsAttributes.ContentState {
        FlowDownWidgetsAttributes.ContentState(
            conversationCount: 0,
            streamingSessionTextCount: 114_514,
        )
    }
}

@available(iOS 17.0, *)
#Preview("Notification", as: .content, using: FlowDownWidgetsAttributes.preview) {
    FlowDownWidgetsLiveActivity()
} contentStates: {
    FlowDownWidgetsAttributes.ContentState.none
    FlowDownWidgetsAttributes.ContentState.doing
    FlowDownWidgetsAttributes.ContentState.done
}
