# SnowPlowApp
# SnowPlowApp

A native iPhone app for a snow-plowing company. It notices when a driver arrives at a customer's property, checks the property off automatically after a set time, and copies completed jobs to the cloud so other phones can see them. It is built to keep working with poor or no cell service.

**Status (November 2026):** working prototype on one iPhone, built entirely without a Mac and without paying for anything. Not yet tested on a second phone or in a real storm with a crew.

## What it does

- **Customers and properties.** Add, edit, and delete customers. Each can have several properties with an address, map location, and arrival radius (50 to 500 m). Typing an address shows suggestions; picking one saves the exact map location.
- **Map.** Pins for every property with their arrival circles, a dot for your own location, and green checkmarks for properties finished in the current storm.
- **Storms.** Start and end a storm. The Storm tab shows a live storm clock, how many properties are done, and every property with a **Done** button. Swipe a finished property for **Again** (a second visit) or **Undo**.
- **Automatic check-off.** While a storm is active, the app watches GPS (including with the screen locked). If the phone stays inside a property's circle for the set time (default 3 minutes, changeable in Settings), the property is checked off with the time and driver name. A live timer shows while you are at a property.
- **Restart after close.** While a storm is active, the app also asks iOS to relaunch it if it gets closed (on large movement, or when entering one of the 20 closest unfinished properties).
- **Cloud sync (optional switch in Settings).** Copies customers, properties, storms, and completed jobs to Firebase and pulls changes from other phones. Works offline and catches up later. Driver locations are never sent.

## Tech

- Swift and SwiftUI, iOS 17 or newer
- SwiftData for storage on the phone (the phone's copy is what the app uses first)
- MapKit (maps, address suggestions) and CoreLocation (GPS, region monitoring)
- Firebase Authentication (anonymous sign-in) and Cloud Firestore for sync. Firebase iOS SDK 12.19.3, pinned in `project.yml`
- XcodeGen builds the Xcode project from `project.yml`
- GitHub Actions builds the app on a free GitHub Mac

## How it is built and installed (no Mac needed)

1. Edit code in this repository (on the GitHub website).
2. Every commit starts the **Build iOS app** workflow (Actions tab). It runs XcodeGen, builds an unsigned app, and saves `SnowPlowApp-ipa` as a downloadable artifact.
3. Download the artifact, extract the zip, and install `SnowPlowApp.ipa` with **Sideloadly** on Windows and a free Apple ID.
4. In Sideloadly's Advanced Options, **uncheck "Use automatic bundle ID"** and type `com.snowplowapp.app`. Firebase is registered to that ID.
5. On the iPhone: turn on **Developer Mode** (Settings, Privacy & Security), and trust the Apple ID under Settings, General, VPN & Device Management.
6. Set Location to **Always** with **Precise Location** on (Settings, SnowPlow, Location). Without Always, iOS will not restart the app on its own.

**Free Apple ID limit:** the installed app stops opening after about 7 days. Reinstall with Sideloadly. A paid Apple Developer account ($99/year) removes this and allows TestFlight for the crew.

## Files

Top level: `project.yml` (project settings, Firebase package, permissions), `.github/workflows/build.yml` (the build), this README.

Inside `SnowPlowApp/`:

| File | Purpose |
|---|---|
| `SnowPlowMain.swift` | App start. Opens the database, then starts GPS and sync so they also work when iOS restarts the app in the background |
| `ContentView.swift` | The four tabs: Storm, Customers, Map, Settings |
| `Customer.swift`, `Property.swift`, `Storm.swift`, `ServiceRecord.swift` | The data. A ServiceRecord is one completed visit |
| `DataMaintenance.swift` | Gives older records the unique IDs sync needs |
| `StormView.swift` | Storm tab: clock, GPS status, property checklist |
| `CustomerListView.swift`, `NewCustomerView.swift`, `CustomerEditView.swift` | Customer screens |
| `AddressField.swift` | Address box with suggestions and map location |
| `PropertyMapView.swift` | Map tab |
| `SettingsView.swift` | Driver name, time at property, cloud sync switch |
| `LocationService.swift` | GPS watching, the arrival timer, and restart watching |
| `SyncService.swift` | Cloud sync |
| `GoogleService-Info.plist` | Firebase settings file for this project |

## How the GPS check-off works

- Only runs while a storm is active.
- GPS readings worse than 50 m accuracy are ignored.
- The phone must stay inside the property's circle for the full set time. Once inside, the circle counts as 25% bigger so GPS drift at the edge does not reset the timer.
- If circles overlap, the closest property is used.
- A property is auto-checked **once per storm**. Repeat visits are recorded with the manual **Again** swipe.
- iOS only lets an app watch 20 places for restarts at once, so the app watches the 20 closest unfinished properties and swaps them as the phone moves.

## How sync works

- Data is stored in Firestore under `companies/main/` in four collections: `customers`, `properties`, `storms`, `records`.
- Every item has a unique ID created on the phone, so two phones cannot create duplicates of each other's records.
- The app checks for changes every 15 seconds and when it goes to the background. It only sends items that actually changed.
- Deletes on one phone are deleted in the cloud and on other phones.
- Firebase queues changes while offline and sends them when service returns.

## Firebase setup (already done for this project)

1. Firebase project `SnowPlowApp` on the free Spark plan.
2. Firestore database (Standard edition, production mode) with rules that require a signed-in user:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

3. Anonymous sign-in turned on (Authentication, Sign-in method).
4. iOS app registered with bundle ID `com.snowplowapp.app`. Its `GoogleService-Info.plist` is uploaded to `SnowPlowApp/`.

## Known limits and not yet tested

- **Two phones syncing with each other is untested.** Only one phone has been used so far.
- **Restart-after-close is untested in real storms.** iOS decides when to wake an app, can be late, and may not restart an app that was swiped away by hand. Keep using the manual **Done** button as a backup.
- An edit made in the last 15 seconds before closing the app can be lost.
- Deleting the very last customer may not delete it in the cloud (a safety rule so an empty phone never wipes the cloud).
- GPS uses more battery during a storm.
- Address suggestions need internet.
- The code has been written without a local compiler. Build errors on GitHub are the main way problems show up.

## Before real customers go in

Right now the database only checks that a phone has signed in anonymously, and the Firebase settings file is in a public repository. That is fine for test data only. Before real customer names and addresses are stored:

- make the repository private (or move the settings file out of the code),
- add real accounts and tighter database rules,
- add a privacy policy, since the app uses location.

## Ideas for later

- Second phone and crew testing, using a paid Apple Developer account and TestFlight
- A backup/export button for customer data
- A home dashboard and larger buttons for use while driving
- Per-driver accounts and roles (owner and driver)
- Priority or "must be done by" flags for schools and similar properties

## Troubleshooting

- **Build goes red:** open the failed build, open the step with the red X, and search the log for `error:`. Replacing a file by pasting over it can leave extra lines at the bottom. Select all, delete, then paste again, and check the last line is a single `}`.
- **Sideloadly cannot see the iPhone:** install iTunes from Apple's website, unlock the phone, tap Trust, and restart if needed.
- **App crashes right after an update:** delete it and reinstall. With sync on, your data returns from the cloud.
- **App will not open after about a week:** the free Apple ID limit. Reinstall.

## Working rules for this project

1. Build in small pieces and test each one before moving on.
2. Explain significant decisions before making them.
3. Never claim something works until it has been tested on a real phone.
4. Keep it simple and reliable. This is used while driving and working.
5. Keep this README up to date.

## Starting a new chat with Claude

Paste this whole README into the new chat and say what you want to do next. The README does not contain the code itself, so for changes to a file, paste that file's current contents from GitHub.
