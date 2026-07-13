import Foundation

class GoogleCalendarService {
    private let base = "https://www.googleapis.com/calendar/v3"
    private let oauth: OAuthService
    private let clientId: String
    private let clientSecret: String

    init(oauth: OAuthService, clientId: String, clientSecret: String) {
        self.oauth = oauth
        self.clientId = clientId
        self.clientSecret = clientSecret
    }

    func listCalendars() async throws -> [GoogleCalendarItem] {
        let req = try await authorized("GET", "/users/me/calendarList?maxResults=250")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(resp, data)
        return try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data).items
    }

    func createEvent(_ event: GoogleEvent, calendarId: String) async throws -> String {
        let body = try JSONEncoder().encode(event)
        let req = try await authorized("POST", "/calendars/\(encoded(calendarId))/events", body: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(resp, data)
        return try JSONDecoder().decode(GoogleEventResponse.self, from: data).id
    }

    func updateEvent(_ event: GoogleEvent, eventId: String, calendarId: String) async throws {
        let body = try JSONEncoder().encode(event)
        let req = try await authorized("PUT", "/calendars/\(encoded(calendarId))/events/\(encoded(eventId))", body: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(resp, data)
    }

    func deleteEvent(eventId: String, calendarId: String) async throws {
        let req = try await authorized("DELETE", "/calendars/\(encoded(calendarId))/events/\(encoded(eventId))")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 404 { return }
        try validate(resp, data)
    }

    private func authorized(_ method: String, _ path: String, body: Data? = nil) async throws -> URLRequest {
        let token = try await oauth.getValidAccessToken(clientId: clientId, clientSecret: clientSecret)
        var req = URLRequest(url: URL(string: "\(base)\(path)")!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private func validate(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GoogleAPIError.http(http.statusCode, msg)
        }
    }

    private func encoded(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }
}

enum GoogleAPIError: Error, LocalizedError {
    case http(Int, String)

    var errorDescription: String? {
        if case .http(let code, let msg) = self {
            return "Google API \(code): \(msg)"
        }
        return nil
    }
}
