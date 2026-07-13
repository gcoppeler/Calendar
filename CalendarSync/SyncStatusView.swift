import SwiftUI

struct SyncStatusView: View {
    @ObservedObject var mgr: SyncManager
    @State private var showSettings = false
    @State private var draft = AppSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if showSettings {
                settingsPanel
            } else {
                mainPanel
            }
        }
        .frame(width: 300)
        .onAppear {
            if mgr.oauth.isAuthenticated && mgr.googleCalendars.isEmpty {
                Task { await mgr.loadGoogleCalendars() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundColor(.accentColor)
            Text("CalendarSync")
                .font(.headline)
            Spacer()
            Button {
                if showSettings {
                    draft = mgr.settings
                    showSettings = false
                } else {
                    draft = mgr.settings
                    if mgr.oauth.isAuthenticated {
                        Task { await mgr.loadGoogleCalendars() }
                    }
                    showSettings = true
                }
            } label: {
                Image(systemName: showSettings ? "chevron.left" : "gear")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(showSettings ? "Back" : "Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Main panel

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow

            if let date = mgr.lastSyncDate {
                Label {
                    Text("Last sync: \(date, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "clock").foregroundColor(.secondary)
                }
            }

            if !mgr.settings.selectedGoogleCalendarName.isEmpty {
                Label {
                    Text("→ \(mgr.settings.selectedGoogleCalendarName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "arrow.right.circle").foregroundColor(.secondary)
                }
            }

            Divider()

            actionButton

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch mgr.status {
        case .notConfigured:
            Button("Configure…") { draft = mgr.settings; showSettings = true }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

        case .notAuthenticated:
            Button {
                Task { await mgr.authenticate() }
            } label: {
                Label("Sign in with Google", systemImage: "person.badge.key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

        default:
            Button {
                Task { await mgr.sync() }
            } label: {
                HStack {
                    if mgr.status == .syncing {
                        ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(syncLabel)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(mgr.status == .syncing)
        }
    }

    private var syncLabel: String {
        switch mgr.status {
        case .syncing: return "Syncing…"
        case .success(let n): return n == 0 ? "Up to date" : "Synced \(n) change\(n == 1 ? "" : "s")"
        default: return "Sync Now"
        }
    }

    // MARK: - Status indicator

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.subheadline)
        }
    }

    private var statusColor: Color {
        switch mgr.status {
        case .idle, .success: return .green
        case .syncing: return .orange
        case .error: return .red
        case .notConfigured, .notAuthenticated: return .gray
        }
    }

    private var statusLabel: String {
        switch mgr.status {
        case .idle: return "Ready"
        case .syncing: return "Syncing…"
        case .success(let n): return n == 0 ? "Up to date" : "\(n) change\(n == 1 ? "" : "s") synced"
        case .error(let msg): return msg
        case .notConfigured: return "Not configured"
        case .notAuthenticated: return "Not signed in"
        }
    }

    // MARK: - Settings panel

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                credentialsSection
                Divider()
                if mgr.oauth.isAuthenticated {
                    calendarPickerSection
                    Divider()
                }
                settingsActions
            }
            .padding(12)
        }
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Google OAuth Credentials")
                .font(.subheadline).fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 3) {
                Text("Client ID").font(.caption).foregroundColor(.secondary)
                TextField("Paste Client ID", text: $draft.clientId)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Client Secret").font(.caption).foregroundColor(.secondary)
                SecureField("Paste Client Secret", text: $draft.clientSecret)
                    .textFieldStyle(.roundedBorder)
            }

            if !mgr.oauth.isAuthenticated && !draft.clientId.isEmpty && !draft.clientSecret.isEmpty {
                Text("Save credentials, then click Sign in with Google on the main screen.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var calendarPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Google Calendar")
                .font(.subheadline).fontWeight(.semibold)

            if mgr.googleCalendars.isEmpty {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading calendars…").font(.caption).foregroundColor(.secondary)
                }
            } else {
                Picker("Calendar", selection: Binding(
                    get: { draft.selectedGoogleCalendarId },
                    set: { newId in
                        draft.selectedGoogleCalendarId = newId
                        draft.selectedGoogleCalendarName = mgr.googleCalendars.first { $0.id == newId }?.summary ?? ""
                    }
                )) {
                    Text("Select a calendar…").tag("")
                    ForEach(mgr.googleCalendars) { cal in
                        Text(cal.summary).tag(cal.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var settingsActions: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Cancel") {
                    draft = mgr.settings
                    showSettings = false
                }
                Spacer()
                Button("Save") {
                    mgr.settings = draft
                    showSettings = false
                }
                .buttonStyle(.borderedProminent)
            }

            if mgr.oauth.isAuthenticated {
                Button("Sign Out of Google") {
                    mgr.signOut()
                    showSettings = false
                }
                .foregroundColor(.red)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
