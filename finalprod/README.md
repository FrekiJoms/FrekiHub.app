# FrekiHub — Android Build (`v1.5.5`)

## Application Overview

- **App Name:** `FrekiHub`
- **Package ID:** `com.frekihub.freki_hub`
- **Version:** `1.5.5` (`versionCode: 2`)
- **Build Type:** Installable Debug APK (`FrekiHub-v1.5.5-debug.apk`), signed with Android's local debug key
- **Minimum Android Version:** Android 15 (API 35)
- **Description:** Personal offline-first Android time-tracking, multi-wallet finance, calendar, map, and on-device automation companion. All records stay in local SQLite storage with no account required.

## Features & Application Uses

- **Home & Sessions:** Start/stop timed sessions (OJT, Work, Study, Personal), edit notes/timestamps, view active timer notifications and HyperIsland live controls, and confirm clock-out via an optional cross-app overlay (`SessionConfirmationActivity`).
- **Finance & Multi-Wallet Management:** Track expenses, income, savings goals, and **wallet-to-wallet transfers** across separated wallets with native Android payment-app icons (`Cash` + installed apps), custom card artwork, per-wallet scoping across the Total Balance card and Monthly Net card, category analytics, and recurring planner rules.
- **Calendar:** Inspect daily sessions and financial movements by date, add entries directly to a day, or edit existing records and transfers.
- **Map:** View recorded session/transaction coordinates on an interactive map and manage saved automation places (location collection and logging remain opt-in).
- **On-Device Rule Automation:** Create custom `when ... then ...` rules triggered by geofences/places, schedule times, or payment app notifications / SMS imports, inspectable from Settings and the syntax builder workspace.
- **Settings & Backup:** Manage currency, payment methods, categories, notification sounds, JSON backup export/import, and activity logs.

## Android Permissions & Uses (from `AndroidManifest.xml`)

All sensitive permissions are opt-in and explained in-app before system prompts (`PermissionHints`):

| Permission / Component | Purpose in FrekiHub |
| --- | --- |
| `POST_NOTIFICATIONS` | Ongoing session timer notification, rule reminders, and post-commit transaction receipts. |
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` / `ACCESS_BACKGROUND_LOCATION` | Opt-in place picking, geofence checks for enabled location rules, and optional session/entry coordinate logging. |
| `BIND_NOTIFICATION_LISTENER_SERVICE` (`PurchaseListener`) | Opt-in local detection of payment alerts from user-selected finance apps. |
| `READ_SMS` | Opt-in local import of transaction SMS messages for enabled rules. |
| `SCHEDULE_EXACT_ALARM` | Precise timing for scheduled automation reminders when granted. |
| `SYSTEM_ALERT_WINDOW` | Optional cross-app Clock-out confirmation card while outside FrekiHub. |
| `REQUEST_INSTALL_PACKAGES` | Opt-in in-app APK update installation when checking for newer releases from Settings or launch. |
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_SPECIAL_USE` (`SessionService`) | Keeps an ongoing user-started session chronometer visible in notifications. |
| `RECEIVE_BOOT_COMPLETED` (`AutomationBootReceiver`) | Restores enabled schedules/geofences after device reboot or time changes. |
| `INTERNET` / `ACCESS_NETWORK_STATE` | Map tile fetching and connectivity checks for automation. |
| Launcher `<queries>` | Lists installed payment apps so wallets can be linked to native app icons and alert packages. |

## Installing on Android

1. Copy `FrekiHub-v1.5.5-debug.apk` to your Android 15+ phone.
2. Tap the `.apk` file in your file manager and allow **Install unknown apps** if prompted.
3. Because this APK is debug-signed for direct local installation, future upgrades require either another build from this same debug keystore or uninstalling before switching to a keystore-signed release build.
