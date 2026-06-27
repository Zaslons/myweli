# Add appointment to calendar (FR-APPT-006)

| | |
|---|---|
| **Requirement** | FR-APPT-006 — "Calendar add (.ics / native calendar) and directions (maps)". **Directions already shipped**; this slice adds the calendar-add half. |
| **Phase** | V1 small-gap sweep (ROADMAP §1.8). |
| **Surface** | Consumer app — `appointment_detail_screen.dart`. |
| **Status** | Draft → building. |

## 1. Goal & scope
One tap on an **upcoming** appointment to add it to the phone's native calendar.
Myweli never owns the calendar entry — the package opens the OS "new event"
sheet pre-filled and the user taps save in their own calendar app (consistent
with the no-custody / user-authorises-in-their-own-app posture).

**In scope:** a "Ajouter au calendrier" action on `appointment_detail_screen`
for upcoming, non-cancelled appointments; a small pure mapper
(`buildAppointmentCalendarEvent`) + a thin `add_2_calendar` shell.
**Out of scope:** directions (already shipped), custom reminders/alarms beyond
the calendar's default, recurring events, pro-side calendar add.

## 2. Dependency
`add_2_calendar` (MIT, small) — opens the native add-event UI on iOS & Android.
APK impact is negligible (well within the <30 MB budget). Added via `flutter pub add`.

**Platform config (required, else the sheet fails at runtime):**
- **iOS** (`ios/Runner/Info.plist`, done): `NSCalendarsUsageDescription` +
  `NSCalendarsWriteOnlyAccessUsageDescription` (iOS 17+) — both set, FR copy.
- **Android** ⚠️ **TODO when `android/` is scaffolded** (no Android platform
  folder in the repo yet — only ios/macos/web): add to
  `android/app/src/main/AndroidManifest.xml`:
  ```xml
  <queries>
    <intent>
      <action android:name="android.intent.action.INSERT" />
      <data android:mimeType="vnd.android.cursor.item/event" />
    </intent>
  </queries>
  ```
  Without it, Android 11+ blocks the calendar intent (silent failure → the
  handler's "Impossible d'ouvrir le calendrier" snackbar).

## 3. UX
- **Entry / placement:** a secondary `AppButton` (`Icons.event_available`,
  *« Ajouter au calendrier »*) in the action stack of
  `appointment_detail_screen`, shown only when the appointment is **upcoming**
  (`appointmentDate.isAfter(now)`) and **not** cancelled/completed — same gate as
  the existing "Reporter" button.
- **Flow:** tap → (load the provider if not already cached, reusing the existing
  `ProviderProvider.loadProviderById` pattern from the deposit/review actions) →
  build the event → `Add2Calendar.addEvent2Cal(...)` → OS sheet → user saves.
- **Event mapping:**

  | Calendar field | Source |
  |---|---|
  | Title | *« Rendez‑vous — {provider.name} »* |
  | Start | `appointment.appointmentDate` |
  | End | start + Σ duration of the booked services (`Service.durationMinutes`); floor 30 min if unknown |
  | Location | `provider.address` (falls back to `provider.name`) |
  | Description | service names, comma-joined; plus *« Acompte X · Solde Y »* when a deposit applies |

- **States:**
  - *success* → snackbar *« Rendez‑vous ajouté à votre calendrier »*.
  - *failure / no calendar app / user cancels* → snackbar *« Impossible d'ouvrir le calendrier »* (best-effort, never crashes).
  - provider still loading → the tap awaits the fetch (fast, cached after first load); button not shown for past/cancelled.
- **Copy (FR):** button *« Ajouter au calendrier »* · success/error as above.
- **Tokens:** reuse `AppButton` (secondary) + existing icon/colour tokens — no literals.

## 4. Implementation
- `lib/core/utils/calendar_event.dart`:
  - `CalendarEventData { title, description, location, start, end }` — plain holder, no package types (keeps it unit-testable).
  - `CalendarEventData buildAppointmentCalendarEvent({ required String providerName, String? providerAddress, required List<String> serviceNames, required DateTime start, required int totalDurationMinutes, double depositAmount = 0, double balanceDue = 0 })` — pure.
  - `Future<bool> addAppointmentToCalendar(CalendarEventData d)` — maps to `add_2_calendar`'s `Event` and calls `Add2Calendar.addEvent2Cal` (the only package touch-point).
- Screen wires the button → resolve provider → derive `serviceNames` + `totalDurationMinutes` by matching `appointment.serviceIds` against `provider.services` → `buildAppointmentCalendarEvent` → `addAppointmentToCalendar` → snackbar.

## 5. Security / privacy
Client-only; no new network call, no secrets. The event carries only what's
already visible on the detail screen (provider, time, services, amounts) — no new
PII surface. Server authority unaffected.

## 6. Performance
Trivial. Provider is fetched once and cached; the mapper is O(services). No lists,
no images.

## 7. Testing
- Unit (`buildAppointmentCalendarEvent`): title/location/description composition;
  end = start + duration; 30-min floor when duration is 0; deposit line present
  only when `depositAmount > 0`.
- The `Add2Calendar` shell is a thin pass-through (not unit-tested; it's the
  platform boundary).

## 8. Rollout
Purely additive; one dependency, no migration, no config, no flag. Mock/demo
unaffected.
