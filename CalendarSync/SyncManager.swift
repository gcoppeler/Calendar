import Foundation
import SwiftUI
import Combine
import EventKit

@MainActor
class SyncManager: ObservableObject {
    @Published var status: SyncStatus = .notConfigured
    @Published var lastSyncDate: Date?
    @Published var googleCalendars: [GoogleCalendarItem] = []
    @Published var settings: AppSettings = AppSettings() {
        didSet {
            saveSettings()
            rebuildGoogleService()
            refreshStatus()
        }
    }

    let oauth = OAuthService()
    private let ekService = EventKitService()
    private let syncStore = SyncStoreManager()
    private var googleService: GoogleCalendarService?
    private let settingsURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CalendarSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settingsURL = dir.appendingPathComponent("settings.json")

        loadSettings()
        rebuildGoogleService()
        lastSyncDate = syncStore.lastSyncDate
        refreshStatus()
    }

    // MARK: - Auth

    func authenticate() async {
        guard !settings.clientId.isEmpty, !settings.clientSecret.isEmpty else {
            status = .notConfigured
            return
        }
        status = .syncing
        do {
            try await oauth.authenticate(clientId: settings.clientId, clientSecret: settings.clientSecret)
            await loadGoogleCalendars()
            refreshStatus()
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func loadGoogleCalendars() async {
        guard let svc = googleService else { return }
        do {
            googleCalendars = try await svc.listCalendars()
        } catch {
            status = .error("Could not load calendars: \(error.localizedDescription)")
        }
    }

    func signOut() {
        oauth.signOut()
        googleCalendars = []
        refreshStatus()
    }

    // MARK: - Sync

    func sync() async {
        guard let svc = googleService else { status = .notConfigured; return }
        guard !settings.selectedGoogleCalendarId.isEmpty else {
            status = .error("No Google calendar selected — open ⚙ Settings")
            return
        }

        status = .syncing

        do {
            try await ekService.requestAccess()
            let appleCalendar = try ekService.findCalendar()
            let appleEvents = ekService.fetchEvents(in: appleCalendar)

            let calId = settings.selectedGoogleCalendarId
            let currentIds = Set(appleEvents.compactMap { $0.eventIdentifier })
            var changes = 0

            print("Sync starting: \(appleEvents.count) Apple events found in '\(ekService.calendarName)'")

            for (index, event) in appleEvents.enumerated() {
                print("Processing \(index + 1)/\(appleEvents.count): \(event.title ?? "untitled")")
                guard let appleId = event.eventIdentifier else { continue }
                let hash = ekService.contentHash(for: event)
                let googleEvent = ekService.toGoogleEvent(event)

                if let mapping = syncStore.findMapping(appleId: appleId) {
                    guard mapping.contentHash != hash else { continue }
                    do {
                        try await svc.updateEvent(googleEvent, eventId: mapping.googleEventId, calendarId: calId)
                    } catch GoogleAPIError.http(404, _) {
                        // Google event was manually deleted — recreate it
                        let newId = try await svc.createEvent(googleEvent, calendarId: calId)
                        syncStore.upsertMapping(EventMapping(appleEventId: appleId, googleEventId: newId, contentHash: hash))
                        changes += 1
                        continue
                    }
                    syncStore.upsertMapping(EventMapping(appleEventId: appleId, googleEventId: mapping.googleEventId, contentHash: hash))
                } else {
                    let googleId = try await svc.createEvent(googleEvent, calendarId: calId)
                    syncStore.upsertMapping(EventMapping(appleEventId: appleId, googleEventId: googleId, contentHash: hash))
                }
                changes += 1
            }

            for mapping in syncStore.allMappings() where !currentIds.contains(mapping.appleEventId) {
                try await svc.deleteEvent(eventId: mapping.googleEventId, calendarId: calId)
                syncStore.removeMapping(appleId: mapping.appleEventId)
                changes += 1
            }

            let now = Date()
            syncStore.setLastSyncDate(now)
            lastSyncDate = now
            status = .success(eventsProcessed: changes)

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self, case .success = self.status else { return }
                self.status = .idle
            }

        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func refreshStatus() {
        guard case .syncing = status else {
            if settings.clientId.isEmpty || settings.clientSecret.isEmpty {
                status = .notConfigured
            } else if !oauth.isAuthenticated {
                status = .notAuthenticated
            } else if settings.selectedGoogleCalendarId.isEmpty {
                status = .error("Select a Google calendar in ⚙ Settings")
            } else {
                status = .idle
            }
            return
        }
    }

    private func rebuildGoogleService() {
        guard !settings.clientId.isEmpty, !settings.clientSecret.isEmpty else { return }
        googleService = GoogleCalendarService(oauth: oauth, clientId: settings.clientId, clientSecret: settings.clientSecret)
    }

    private func loadSettings() {
        guard let data = try? Data(contentsOf: settingsURL),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
        settings = decoded
    }

    private func saveSettings() {
        try? JSONEncoder().encode(settings).write(to: settingsURL)
    }
}
