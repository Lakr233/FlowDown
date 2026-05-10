@testable import FlowDown
import EventKit
import Foundation
import Testing

/// EventKit-backed integration tests. These touch the real Reminders database
/// on the simulator (or host), so they're gated behind an opt-in environment
/// flag and require the test runner to have been granted Reminders access.
///
/// Enable locally with:
///     FLOWDOWN_ENABLE_REMINDER_INTEGRATION=1 make test-unit
///
/// On a simulator, also run once interactively to grant Reminders permission
/// to the test host before the suite can use the store.
@Suite(.serialized, .enabled(if: ReminderIntegrationGate.isEnabled))
struct ReminderToolsIntegrationTests {
    let environment: ReminderTestEnvironment

    init() async throws {
        environment = try await ReminderTestEnvironment.make()
    }

    // MARK: - Shared layer

    @Test
    func `resolveCalendarRequiringName returns the named test calendar`() throws {
        let calendar = try ReminderToolsShared.resolveCalendarRequiringName(
            named: environment.calendarTitle,
            eventStore: environment.eventStore,
        )
        #expect(calendar.calendarIdentifier == environment.calendar.calendarIdentifier)
    }

    @Test
    func `resolveCalendarRequiringName matches case-insensitively`() throws {
        let calendar = try ReminderToolsShared.resolveCalendarRequiringName(
            named: environment.calendarTitle.uppercased(),
            eventStore: environment.eventStore,
        )
        #expect(calendar.calendarIdentifier == environment.calendar.calendarIdentifier)
    }

    @Test
    func `resolveCalendarRequiringName throws on a typo'd list name`() {
        // The whole point of Fix A. A non-empty unknown name must surface as a
        // domain error, not silently land on the default list.
        #expect(throws: NSError.self) {
            try ReminderToolsShared.resolveCalendarRequiringName(
                named: "FlowDown-NonExistent-\(UUID().uuidString)",
                eventStore: environment.eventStore,
            )
        }
    }

    @Test
    func `resolveCalendarRequiringName falls back to default for empty name`() throws {
        guard environment.eventStore.defaultCalendarForNewReminders() != nil else {
            // Some hosts may not have a default reminders calendar configured.
            return
        }
        let calendar = try ReminderToolsShared.resolveCalendarRequiringName(
            named: "",
            eventStore: environment.eventStore,
        )
        #expect(calendar.allowedEntityTypes.contains(.reminder))
    }

    // MARK: - Round trip add → query → update → complete → delete

    @Test
    func `add reminder is visible to query and survives update with clear flags`() async throws {
        let store = environment.eventStore
        let calendar = environment.calendar

        // Seed: add reminder with notes, due date and priority.
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Integration target"
        reminder.notes = "starting notes"
        reminder.calendar = calendar
        reminder.priority = 5
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Date().addingTimeInterval(3600),
        )
        try store.save(reminder, commit: true)
        environment.track(reminder)
        let id = reminder.calendarItemIdentifier

        // Query through the formatter and confirm presence.
        let predicate = store.predicateForReminders(in: [calendar])
        let fetched = try await fetchReminders(store: store, predicate: predicate)
        #expect(fetched.contains { $0.calendarItemIdentifier == id })
        let formatted = ReminderToolsShared.formatReminders(fetched)
        #expect(formatted.contains("Integration target"))
        #expect(formatted.contains("[id: \(id)]"))

        // Apply parsed changes that exercise the new clear flags. Mirror the
        // saver block in MTUpdateReminderTool so we exercise the real branches.
        let changes = MTUpdateReminderTool.ParsedChanges(
            newTitle: "Integration renamed",
            newNotes: nil, clearNotes: true,
            newDueDate: nil, clearDueDate: true,
            newPriority: nil, clearPriority: true,
            newListName: nil,
        )
        try applyChanges(changes, to: reminder, eventStore: store)

        let reloaded = try #require(ReminderToolsShared.fetchReminder(id: id, eventStore: store))
        #expect(reloaded.title == "Integration renamed")
        #expect(reloaded.notes == nil || reloaded.notes?.isEmpty == true)
        #expect(reloaded.dueDateComponents == nil)
        #expect(reloaded.priority == 0)

        // Mark complete and verify completion-only predicate sees it.
        reloaded.isCompleted = true
        try store.save(reloaded, commit: true)
        let completedPredicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: nil, ending: nil, calendars: [calendar],
        )
        let completed = try await fetchReminders(store: store, predicate: completedPredicate)
        #expect(completed.contains { $0.calendarItemIdentifier == id })

        // Delete and verify it disappears.
        try store.remove(reloaded, commit: true)
        environment.untrack(id)
        let afterDelete = try await fetchReminders(store: store, predicate: predicate)
        #expect(!afterDelete.contains { $0.calendarItemIdentifier == id })
    }

    @Test
    func `applying changes to a reminder with a typo'd list name throws`() throws {
        let store = environment.eventStore
        let calendar = environment.calendar
        let reminder = EKReminder(eventStore: store)
        reminder.title = "List move target"
        reminder.calendar = calendar
        try store.save(reminder, commit: true)
        environment.track(reminder)

        let badChanges = MTUpdateReminderTool.ParsedChanges(
            newTitle: nil,
            newNotes: nil, clearNotes: false,
            newDueDate: nil, clearDueDate: false,
            newPriority: nil, clearPriority: false,
            newListName: "FlowDown-NonExistent-\(UUID().uuidString)",
        )
        #expect(throws: NSError.self) {
            try applyChanges(badChanges, to: reminder, eventStore: store)
        }
    }

    // MARK: - Helpers

    /// Mirrors the Update action block in `MTUpdateReminderTool`. Centralized
    /// here so that the tests cover the same branches the production tool
    /// uses, without standing up a full alert/UI pipeline.
    private func applyChanges(
        _ changes: MTUpdateReminderTool.ParsedChanges,
        to reminder: EKReminder,
        eventStore: EKEventStore,
    ) throws {
        if let newTitle = changes.newTitle { reminder.title = newTitle }
        if changes.clearNotes {
            reminder.notes = nil
        } else if let newNotes = changes.newNotes {
            reminder.notes = newNotes
        }
        if changes.clearDueDate {
            reminder.dueDateComponents = nil
        } else if let newDueDate = changes.newDueDate, let date = ReminderToolsShared.parseISODate(newDueDate) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date,
            )
        }
        if changes.clearPriority {
            reminder.priority = 0
        } else if let newPriority = changes.newPriority {
            reminder.priority = newPriority
        }
        if let newListName = changes.newListName {
            reminder.calendar = try ReminderToolsShared.resolveCalendarRequiringName(
                named: newListName,
                eventStore: eventStore,
            )
        }
        try eventStore.save(reminder, commit: true)
    }

    private func fetchReminders(
        store: EKEventStore,
        predicate: NSPredicate,
    ) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders ?? [])
            }
        }
    }
}

// MARK: - Gate / environment

enum ReminderIntegrationGate {
    static let enableFlag = "FLOWDOWN_ENABLE_REMINDER_INTEGRATION"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[enableFlag] == "1"
    }
}

/// Owns the test calendar lifecycle. Created once per test instance, removed
/// (with all its reminders) when the instance deallocates.
final class ReminderTestEnvironment: @unchecked Sendable {
    let eventStore: EKEventStore
    let calendar: EKCalendar
    let calendarTitle: String
    private var trackedIds: Set<String> = []

    private init(eventStore: EKEventStore, calendar: EKCalendar, title: String) {
        self.eventStore = eventStore
        self.calendar = calendar
        calendarTitle = title
    }

    static func make() async throws -> ReminderTestEnvironment {
        let store = EKEventStore()
        try await requestAccess(store: store)

        guard let source = preferredSource(in: store) else {
            throw NSError(domain: "ReminderTestEnvironment", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No EventKit source supports reminders. Grant access or run on a host with a Reminders source.",
            ])
        }

        let title = "FlowDown-Test-\(UUID().uuidString.prefix(8))"
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = String(title)
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return ReminderTestEnvironment(eventStore: store, calendar: calendar, title: String(title))
    }

    func track(_ reminder: EKReminder) {
        trackedIds.insert(reminder.calendarItemIdentifier)
    }

    func untrack(_ id: String) {
        trackedIds.remove(id)
    }

    deinit {
        // Best-effort cleanup so a failing test doesn't leave artifacts behind.
        for id in trackedIds {
            if let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder {
                try? eventStore.remove(reminder, commit: false)
            }
        }
        try? eventStore.removeCalendar(calendar, commit: true)
    }

    private static func requestAccess(store: EKEventStore) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let handler: (Bool, Error?) -> Void = { granted, error in
                if let error {
                    cont.resume(throwing: error)
                } else if !granted {
                    cont.resume(throwing: NSError(domain: "ReminderTestEnvironment", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Reminders access not granted to test host.",
                    ]))
                } else {
                    cont.resume(returning: ())
                }
            }
            if #available(iOS 17, macCatalyst 17, *) {
                store.requestFullAccessToReminders(completion: handler)
            } else {
                store.requestAccess(to: .reminder, completion: handler)
            }
        }
    }

    private static func preferredSource(in store: EKEventStore) -> EKSource? {
        // Prefer the same source the system uses for new reminders so the temp
        // calendar lands somewhere the user can clean up if a teardown is missed.
        if let defaultCalendar = store.defaultCalendarForNewReminders() {
            return defaultCalendar.source
        }
        return store.sources.first { source in
            source.sourceType == .local || source.sourceType == .calDAV
        }
    }
}
