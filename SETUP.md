# CalendarSync — Setup Guide

One-way sync from Apple Calendar ("Home - GC") → Google Calendar. Manual trigger via menu bar. This is just for testing purposes. Updates will be made on a weekly basis.

---

## Step 1 — Google Cloud Setup (~10 min)

### 1a. Create a project
1. Go to https://console.cloud.google.com
2. Click the project dropdown → **New Project**
3. Name it "CalendarSync" → **Create**

### 1b. Enable the Calendar API
1. In your new project, go to **APIs & Services → Library**
2. Search for "Google Calendar API" → click it → **Enable**

### 1c. Configure the OAuth consent screen
1. Go to **APIs & Services → OAuth consent screen**
2. Choose **External** → **Create**
3. Fill in:
   - App name: `CalendarSync`
   - User support email: your Gmail
   - Developer contact: your Gmail
4. Click **Save and Continue** through the Scopes and Test Users steps
5. On the **Test users** page, click **+ Add users** and add `gcoppeler@gmail.com`
6. Click **Save and Continue** → **Back to Dashboard**

### 1d. Create OAuth credentials
1. Go to **APIs & Services → Credentials**
2. Click **+ Create Credentials → OAuth client ID**
3. Application type: **Desktop app**
4. Name: `CalendarSync`
5. Under **Authorized redirect URIs**, click **+ Add URI** and enter:
   ```
   http://127.0.0.1:8765/callback
   ```
6. Click **Create**
7. Copy your **Client ID** and **Client Secret** — you'll paste these into the app

---

## Step 2 — Create the Xcode Project

1. Open **Xcode → File → New → Project**
2. Choose **macOS → App** → Next
3. Fill in:
   - Product Name: `CalendarSync`
   - Bundle Identifier: `com.gc.CalendarSync`
   - Interface: **SwiftUI**
   - Language: **Swift**
4. Save it to this directory (`Calendar App/`)

### 2a. Replace/add source files
In Finder, drag all `.swift` files from the `CalendarSync/` folder into the Xcode project navigator.
When prompted, choose **Copy items if needed** and add to the `CalendarSync` target.

Delete the placeholder `ContentView.swift` Xcode generated (you won't need it).

### 2b. Set the entitlements file
1. In the project navigator, select the `CalendarSync` target → **Signing & Capabilities**
2. Next to "Hardened Runtime", remove the default entitlements if present
3. In **Build Settings**, search for `CODE_SIGN_ENTITLEMENTS`
4. Set it to `CalendarSync/CalendarSync.entitlements`

### 2c. Edit Info.plist
Add these keys to `Info.plist` (right-click → Open As → Source Code):

```xml
<!-- Hide dock icon — menu bar only -->
<key>LSUIElement</key>
<true/>

<!-- Calendar privacy description (macOS 13) -->
<key>NSCalendarsUsageDescription</key>
<string>CalendarSync reads your Home - GC calendar to sync events to Google Calendar.</string>

<!-- Calendar privacy description (macOS 14+) -->
<key>NSCalendarsFullAccessUsageDescription</key>
<string>CalendarSync reads your Home - GC calendar to sync events to Google Calendar.</string>
```

### 2d. Set minimum deployment target
In **Build Settings → macOS Deployment Target**, set to **13.0**.

### 2e. Build & run
Press **⌘R**. The app will appear in your menu bar (calendar icon).

---

## Step 3 — First launch

1. Click the calendar icon in the menu bar
2. Click **Configure…** → paste your **Client ID** and **Client Secret** → **Save**
3. Back on the main screen, click **Sign in with Google**
4. A browser window opens — sign in with `gcoppeler@gmail.com` and allow access
5. The browser shows "✓ Signed in successfully" and the app loads your Google calendars
6. Click ⚙ Settings → select your target Google calendar → **Save**
7. Click **Sync Now**

The first sync will take a minute or two depending on how many events are in the 465-day window.
Subsequent syncs only process changes and are much faster.

---

## How sync works

| Scenario | What happens |
|---|---|
| New event in Apple Calendar | Created in Google Calendar |
| Event updated in Apple Calendar | Updated in Google Calendar |
| Event deleted from Apple Calendar | Deleted from Google Calendar |
| Event manually deleted from Google | Recreated on next sync |
| Google event manually edited | Overwritten on next sync (Apple is source of truth) |

Recurring events: each occurrence within the sync window is treated as an independent Google event.

---

## Troubleshooting

**"Calendar 'Home - GC' not found"** — The calendar name must match exactly. Check Apple Calendar for the exact name.

**"Calendar access denied"** — Go to System Settings → Privacy & Security → Calendars → enable CalendarSync.

**Port 8765 in use** — Change `redirectPort` in `OAuthService.swift` to another port (e.g. 8766) and update the redirect URI in Google Cloud Console to match.

**"Token error: invalid_client"** — Your client ID or secret is wrong. Double-check them in Google Cloud Console.
