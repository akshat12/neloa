import AppKit
import Combine
import Foundation
import UserNotifications

struct AutomationReminderDraft: Equatable, Sendable {
    var identifier: String
    var hour: Int
    var minute: Int
    var weekday: Int?
}

enum AutomationScheduleSupport {
    static let identifierPrefix = "ai.neloa.schedule."

    nonisolated static func normalized(_ schedule: AutomationSchedule) -> AutomationSchedule {
        AutomationSchedule(
            repeatMode: schedule.repeatMode,
            hour: min(23, max(0, schedule.hour)),
            minute: min(59, max(0, schedule.minute)),
            weekday: schedule.repeatMode == .weekly ? min(7, max(1, schedule.weekday ?? 2)) : nil,
            isEnabled: schedule.isEnabled
        )
    }

    nonisolated static func reminderDrafts(
        workflowID: UUID,
        schedule: AutomationSchedule
    ) -> [AutomationReminderDraft] {
        let schedule = normalized(schedule)
        guard schedule.isEnabled else { return [] }
        let base = "\(identifierPrefix)\(workflowID.uuidString)"
        switch schedule.repeatMode {
        case .daily:
            return [AutomationReminderDraft(
                identifier: "\(base).daily",
                hour: schedule.hour,
                minute: schedule.minute,
                weekday: nil
            )]
        case .weekdays:
            return (2...6).map { (weekday: Int) -> AutomationReminderDraft in
                AutomationReminderDraft(
                    identifier: "\(base).weekday.\(weekday)",
                    hour: schedule.hour,
                    minute: schedule.minute,
                    weekday: weekday
                )
            }
        case .weekly:
            let weekday = schedule.weekday ?? 2
            return [AutomationReminderDraft(
                identifier: "\(base).weekly.\(weekday)",
                hour: schedule.hour,
                minute: schedule.minute,
                weekday: weekday
            )]
        }
    }

    nonisolated static func allIdentifiers(for workflowID: UUID) -> [String] {
        let base = "\(identifierPrefix)\(workflowID.uuidString)"
        return ["\(base).daily"]
            + (1...7).map { "\(base).weekday.\($0)" }
            + (1...7).map { "\(base).weekly.\($0)" }
    }

    nonisolated static func summary(
        _ schedule: AutomationSchedule,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let schedule = normalized(schedule)
        var components = DateComponents()
        components.hour = schedule.hour
        components.minute = schedule.minute
        let date = calendar.date(from: components) ?? Date()
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        switch schedule.repeatMode {
        case .daily:
            return "Every day at \(time)"
        case .weekdays:
            return "Weekdays at \(time)"
        case .weekly:
            let symbols = calendar.weekdaySymbols
            let index = min(7, max(1, schedule.weekday ?? 2)) - 1
            return "Every \(symbols[index]) at \(time)"
        }
    }
}

@MainActor
final class AutomationScheduleCenter: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastError: String?

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    var canDeliverReminders: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    func refreshAuthorization() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    /// Requests reminder permission only after the user explicitly saves an
    /// enabled schedule. Returning false keeps the schedule visible in Neloa
    /// with a clear permission warning, but no notification is registered.
    func apply(schedule: AutomationSchedule?, to workflow: Workflow) async -> Bool {
        lastError = nil
        center.removePendingNotificationRequests(
            withIdentifiers: AutomationScheduleSupport.allIdentifiers(for: workflow.id)
        )
        guard let schedule, schedule.isEnabled else {
            await refreshAuthorization()
            return true
        }

        do {
            await refreshAuthorization()
            if authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                await refreshAuthorization()
            }
            guard canDeliverReminders else { return false }
            for draft in AutomationScheduleSupport.reminderDrafts(workflowID: workflow.id, schedule: schedule) {
                var date = DateComponents()
                date.hour = draft.hour
                date.minute = draft.minute
                date.weekday = draft.weekday

                let content = UNMutableNotificationContent()
                content.title = "A Neloa automation is ready"
                content.body = "Open Neloa to review what will happen. Nothing starts on its own."
                content.sound = .default
                content.userInfo = ["workflowID": workflow.id.uuidString]

                try await center.add(UNNotificationRequest(
                    identifier: draft.identifier,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
                ))
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func remove(workflowID: UUID) {
        center.removePendingNotificationRequests(
            withIdentifiers: AutomationScheduleSupport.allIdentifiers(for: workflowID)
        )
    }

    /// Rebuilds only Neloa-owned reminders from persisted workflows. This also
    /// cleans up reminders belonging to workflows that were deleted while the
    /// app was not running.
    func reconcile(workflows: [Workflow]) async {
        await refreshAuthorization()
        guard canDeliverReminders else { return }
        let pending = await center.pendingNotificationRequests()
        let neloaIdentifiers = pending.map(\.identifier).filter {
            $0.hasPrefix(AutomationScheduleSupport.identifierPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: neloaIdentifiers)
        for workflow in workflows where workflow.schedule?.isEnabled == true {
            _ = await apply(schedule: workflow.schedule, to: workflow)
        }
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
