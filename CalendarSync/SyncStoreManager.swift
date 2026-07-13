import Foundation

class SyncStoreManager {
    private struct Store: Codable {
        var mappings: [EventMapping] = []
        var lastSyncDate: Date?
    }

    private let url: URL
    private var store: Store

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CalendarSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("sync-store.json")

        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Store.self, from: data) {
            store = decoded
        } else {
            store = Store()
        }
    }

    func findMapping(appleId: String) -> EventMapping? {
        store.mappings.first { $0.appleEventId == appleId }
    }

    func upsertMapping(_ mapping: EventMapping) {
        if let idx = store.mappings.firstIndex(where: { $0.appleEventId == mapping.appleEventId }) {
            store.mappings[idx] = mapping
        } else {
            store.mappings.append(mapping)
        }
        save()
    }

    func removeMapping(appleId: String) {
        store.mappings.removeAll { $0.appleEventId == appleId }
        save()
    }

    func allMappings() -> [EventMapping] {
        store.mappings
    }

    func setLastSyncDate(_ date: Date) {
        store.lastSyncDate = date
        save()
    }

    var lastSyncDate: Date? { store.lastSyncDate }

    private func save() {
        try? JSONEncoder().encode(store).write(to: url)
    }
}
