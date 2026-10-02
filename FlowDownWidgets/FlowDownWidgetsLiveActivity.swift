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
                                if context.state.isFinished {
                                    Image(systemName: "checkmark.circle.fill")
                                } else {
                                    Image(systemName: "arrow.down")
                                    Text(String(context.state.streamingSessionTextCount))
                                }
                            }
                            .monospaced()
                            .opacity(0.5)
                        }
                        Text(context.state.statusText)
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
                    VStack(spacing: 8) {
                        Spacer()

                        Image(systemName: "bird.fill")
                            .bold()

                        Text(context.state.statusText)
                            .contentTransition(.numericText())
                            .animation(.interactiveSpring, value: context.state)
                    }
                    .font(.footnote)
                }
            } compactLeading: {
                Image(systemName: "bird.fill")
                    .foregroundStyle(context.state.isFinished ? .accent : .white)
                    .animation(.interactiveSpring, value: context.state)
            } compactTrailing: {
                let tokenCount = context.state.streamingSessionTextCount

                if context.state.isFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.accent)
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
                Image(systemName: "bird.fill")
                    .foregroundStyle(context.state.isFinished ? .accent : .white)
                    .animation(.interactiveSpring, value: context.state)
                    .widgetURL(URL(string: "flowdown://live-activity"))
            }
        }
    }
}

private extension FlowDownWidgetsAttributes.ContentState {
    var isFinished: Bool {
        conversationCount <= 0
    }

    var statusText: String {
        isFinished
            ? String(localized: "All conversation(s) completed.")
            : String(localized: "Streaming \(conversationCount) conversation(s).")
    }

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
#Preview("Notification", as: .content, using: FlowDownWidgetsAttributes()) {
    FlowDownWidgetsLiveActivity()
} contentStates: {
    FlowDownWidgetsAttributes.ContentState.none
    FlowDownWidgetsAttributes.ContentState.doing
    FlowDownWidgetsAttributes.ContentState.done
}
