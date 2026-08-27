/// The wire time-of-day, extracted without a clock.
///
/// `TimeSlot.startTime/endTime` are date-times whose DATE is a meaningless
/// carrier (`2024-01-01T09:00:00.000Z`) — only the digits after the `T` are
/// data (openapi.yaml TimeSlot). Lives here, not under `lib/pro/`, because the
/// PUBLIC salon page and its JSON-LD read it too — a SEO page importing the
/// pro editor's module read oddly; `lib/pro/availability.ts` re-exports it so
/// the editor's call sites did not churn.
///
/// **Parsed with a regex, never with `new Date()`.** The instant is
/// meaningless but a `Date` is not: `new Date('…T09:00:00.000Z').getHours()`
/// is 10 in Abidjan-plus-one and 4 in New York, so a salon's opening hour
/// would move with the browser's — or the build server's — timezone.
export function timeOfDay(wire: string): string {
  const m = /T(\d{2}):(\d{2})/.exec(wire);
  if (m) return `${m[1]}:${m[2]}`;
  // Tolerated on READ only: a bare HH:mm is what the pro editor used to
  // write, so any salon that somehow has one stored still renders cleanly.
  return /^\d{2}:\d{2}$/.test(wire) ? wire : "";
}
