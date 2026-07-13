import Foundation

// MARK: - Persistence

struct EventMapping: Codable {
    let appleEventId: String
    var googleEventId: String
    var contentHash: String
}

struct AppSettings: Codable {
    var clientId: String = ""
    var clientSecret: String = ""
    var selectedGoogleCalendarId: String = ""
    var selectedGoogleCalendarName: String = ""
}

// MARK: - Google API

struct GoogleEventDateTime: Codable {
    var dateTime: String?
    var date: String?
    var timeZone: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(dateTime, forKey: .dateTime)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encodeIfPresent(timeZone, forKey: .timeZone)
    }

    init(dateTime: String? = nil, date: String? = nil, timeZone: String? = nil) {
        self.dateTime = dateTime
        self.date = date
        self.timeZone = timeZone
    }

    enum CodingKeys: String, CodingKey {
        case dateTime, date, timeZone
    }
}

struct GoogleEvent: Codable {
    var summary: String?
    var description: String?
    var location: String?
    var start: GoogleEventDateTime?
    var end: GoogleEventDateTime?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(start, forKey: .start)
        try c.encodeIfPresent(end, forKey: .end)
    }

    enum CodingKeys: String, CodingKey {
        case summary, description, location, start, end
    }
}

struct GoogleEventResponse: Codable {
    var id: String
}

struct GoogleCalendarItem: Codable, Identifiable {
    var id: String
    var summary: String
}

struct GoogleCalendarListResponse: Codable {
    var items: [GoogleCalendarItem]
    var nextPageToken: String?
}

struct TokenResponse: Codable {
    var accessToken: String?
    var refreshToken: String?
    var expiresIn: Int?
    var error: String?
    var errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case error
        case errorDescription = "error_description"
    }
}

// MARK: - App State

enum SyncStatus: Equatable {
    case idle
    case syncing
    case success(eventsProcessed: Int)
    case error(String)
    case notConfigured
    case notAuthenticated
}
