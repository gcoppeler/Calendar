import EventKit
import CryptoKit
import Foundation

class EventKitService {
    private let store = EKEventStore()
    let calendarName = "Home - GC"

    func requestAccess() async throws {
        if #available(macOS 14.0, *) {
            let granted = try await store.requestFullAccessToEvents()
            if !granted { throw EventKitError.accessDenied }
        } else {
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            if !granted { throw EventKitError.accessDenied }
        }
    }

    func findCalendar() throws -> EKCalendar {
        guard let calendar = store.calendars(for: .event).first(where: { $0.title == calendarName }) else {
            throw EventKitError.calendarNotFound(calendarName)
        }
        return calendar
    }

    func fetchEvents(in calendar: EKCalendar) -> [EKEvent] {
        let start = Calendar.current.date(byAdding: .day, value: -100, to: Date())!
        let end = Calendar.current.date(byAdding: .year, value: 1, to: Date())!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        return store.events(matching: predicate)
    }

    func contentHash(for event: EKEvent) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let parts = [
            event.title ?? "",
            event.location ?? "",
            event.notes ?? "",
            event.startDate.map { dateFormatter.string(from: $0) } ?? "",
            event.endDate.map { dateFormatter.string(from: $0) } ?? "",
            event.isAllDay ? "1" : "0",
            event.timeZone?.identifier ?? "",
        ]
        let data = Data(parts.joined(separator: "|").utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func toGoogleEvent(_ event: EKEvent) -> GoogleEvent {
        var g = GoogleEvent()
        g.summary = event.title?.isEmpty == false ? event.title : "(No title)"
        g.description = event.notes?.isEmpty == false ? event.notes : nil
        g.location = event.location?.isEmpty == false ? event.location : nil

        if event.isAllDay {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            g.start = GoogleEventDateTime(date: fmt.string(from: event.startDate))
            g.end = GoogleEventDateTime(date: fmt.string(from: event.endDate))
        } else {
            let fmt = ISO8601DateFormatter()
            let tz = (event.timeZone ?? TimeZone.current).identifier
            g.start = GoogleEventDateTime(dateTime: fmt.string(from: event.startDate), timeZone: tz)
            g.end = GoogleEventDateTime(dateTime: fmt.string(from: event.endDate), timeZone: tz)
        }

        return g
    }
}

enum EventKitError: Error, LocalizedError {
    case accessDenied
    case calendarNotFound(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access denied. Grant access in System Settings → Privacy & Security → Calendars."
        case .calendarNotFound(let name):
            return "Calendar '\(name)' not found in Apple Calendar."
        }
    }
}
