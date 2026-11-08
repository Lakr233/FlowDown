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
            named: environment.calendar.title,
            eventStore: environment.eventStore,
        )
        #expect(calendar.calendarIdentifier == environment.calendar.calendarIdentifier)
    }

    @Test
    func `resolveCalendarRequiringName matches case-insensitively`() throws {
        let calendar = try ReminderToolsShared.resolveCalendarRequiringName(
            named: environment.calendar.title.uppercased(),
            eventStore: environment.eventStore,
        )
        #expect(calendar.calendarIdentifier == environment.calendar.calendarIdentifier)
    }

    @Test
    func `resolveCalendarRequiringName throws on a typo'd list name`() {
        // A non-empty unknown name must surface as a domain error, not silently land on the default list.
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

        let predicate = store.predicateForReminders(in: [calendar])
        let fetched = try await fetchReminders(store: store, predicate: predicate)
        #expect(fetched.contains { $0.calendarItemIdentifier == id })
        let formatted = ReminderToolsShared.formatReminders(fetched)
        #expect(formatted.contains("Integration target"))
        #expect(formatted.contains("[id: \(id)]"))

        let changes = MTUpdateReminderTool.ParsedChanges(
            newTitle: "Integration renamed",
            clearNotes: true,
            clearDueDate: true,
            clearPriority: true,
        )
        try applyChanges(changes, to: reminder, eventStore: store)

        let reloaded = try #require(ReminderToolsShared.fetchReminder(id: id, eventStore: store))
        #expect(reloaded.title == "Integration renamed")
        #expect(reloaded.notes == nil || reloaded.notes?.isEmpty == true)
        #expect(reloaded.dueDateComponents == nil)
        #expect(reloaded.priority == 0)

        reloaded.isCompleted = true
        try store.save(reloaded, commit: true)
        let completedPredicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: nil,
            ending: nil,
            calendars: [calendar],
        )
        let completed = try await fetchReminders(store: store, predicate: completedPredicate)
        #expect(completed.contains { $0.calendarItemIdentifier == id })

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
            clearNotes: false,
            clearDueDate: false,
            clearPriority: false,
            newListName: "FlowDown-NonExistent-\(UUID().uuidString)",
        )
        #expect(throws: NSError.self) {
            try applyChanges(badChanges, to: reminder, eventStore: store)
        }
    }

    // MARK: - Helpers

    /// Applies `changes` the way `MTUpdateReminderTool` does, then saves,
    /// without going through the tool's access request.
    private func applyChanges(
        _ changes: MTUpdateReminderTool.ParsedChanges,
        to reminder: EKReminder,
        eventStore: EKEventStore,
    ) throws {
        try MTUpdateReminderTool.apply(changes, to: reminder, eventStore: eventStore)
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
    private var trackedIds: Set<String> = []

    private init(eventStore: EKEventStore, calendar: EKCalendar) {
        self.eventStore = eventStore
        self.calendar = calendar
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
        calendar.title = title
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return ReminderTestEnvironment(eventStore: store, calendar: calendar)
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
            let handler: @Sendable (Bool, Error?) -> Void = { granted, error in
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
            store.requestFullAccessToReminders(completion: handler)
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
