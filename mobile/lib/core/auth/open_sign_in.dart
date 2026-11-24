import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// Why the sign-in opened. Its line is written on the screen, under
/// « Bienvenue », instead of a snackbar fired on the way in: a snackbar raised
/// before the push lands on the sign-in itself and is gone in three seconds;
/// a line stays and is read in order (consumer-signin-push.md §2.2).
enum SignInReason {
  none('Connectez-vous pour réserver en quelques secondes.'),
  heart('Connectez-vous pour ajouter ce salon à vos favoris.'),
  booking('Connectez-vous pour confirmer votre réservation.'),
  bookings('Connectez-vous pour retrouver vos rendez-vous.'),
  actu(
    'Connectez-vous pour suivre vos rendez-vous et les réponses des salons.',
  ),
  profile('Connectez-vous pour modifier votre profil.'),
  // `kSessionEndedMessage` (session_ended_notice.dart) — the same words.
  sessionEnded('Votre session a expiré. Reconnectez-vous.');

  const SignInReason(this.line);

  /// What the sign-in screen says under « Bienvenue ».
  final String line;

  /// The route's `reason` value. An unknown or missing one reads as [none].
  static SignInReason fromKey(String? key) => SignInReason.values.firstWhere(
    (r) => r.name == key,
    orElse: () => SignInReason.none,
  );
}

/// Where a sign-in with NOTHING beneath it goes on success
/// (consumer-signin-push.md §2.1, §6): an in-app path only — it starts with
/// « / » and not « // » — otherwise Accueil. No current path opens the
/// sign-in with nothing beneath; the check holds if one ever does.
String safeReturnTo(String? returnTo) {
  final r = returnTo?.trim() ?? '';
  if (r.startsWith('/') && !r.startsWith('//')) return r;
  return '/home';
}

/// The one open sign-in, and the answer its opener waits for
/// (consumer-signin-push.md §2.1).
///
/// - **One at a time.** [openSignIn] ignores a call while one is open.
/// - **It always answers.** `go_router` completes a pushed route's future
///   only when that route is popped; a later `go` that removes it would leave
///   an `await` on `push` hanging for good. So the sign-in screen answers
///   here itself — when it closes, and in its `dispose`, whatever removed it.
/// - **[isOpen] is a listenable**, so a notification tap waiting for the
///   sign-in is replayed only once it has closed, on top of where the person
///   lands — never on top of the sign-in, whose success closes the route on
///   top (§2.2).
class SignInGate {
  SignInGate._();

  static final ValueNotifier<bool> isOpen = ValueNotifier<bool>(false);
  static Completer<bool>? _answer;

  /// The sign-in screen's answer: `true` when the person leaves it signed in.
  /// Only the first call counts; later ones (the screen's `dispose`) do
  /// nothing.
  static void answer(bool signedIn) {
    final c = _answer;
    if (c == null || c.isCompleted) return;
    c.complete(signedIn);
  }

  /// Completes once no sign-in is open (at once when none is).
  static Future<void> whenClosed() {
    if (!isOpen.value) return Future<void>.value();
    final done = Completer<void>();
    void listener() {
      if (isOpen.value) return;
      isOpen.removeListener(listener);
      if (!done.isCompleted) done.complete();
    }

    isOpen.addListener(listener);
    return done.future;
  }

  @visibleForTesting
  static void reset() {
    answer(false);
    _answer = null;
    isOpen.value = false;
  }
}

/// Opens the sign-in **over** the screen the person is on, and answers
/// whether they came back signed in (consumer-signin-push.md §2.1). The caller
/// decides what comes next — carry on, or nothing; « Fermer » returns them
/// exactly where they were.
///
/// It takes the [router] itself: the session-ended notice lives above the
/// Router, where `GoRouter.of(context)` finds nothing.
///
/// A second call while one is open is ignored and answers `false`.
Future<bool> openSignIn(
  GoRouter router, {
  SignInReason reason = SignInReason.none,
}) async {
  if (SignInGate.isOpen.value) return false;
  final answer = Completer<bool>();
  SignInGate._answer = answer;
  SignInGate.isOpen.value = true;
  try {
    // Not awaited: the answer comes from the screen (see [SignInGate]).
    unawaited(
      router
          .push<Object?>(
            Uri(
              path: '/login',
              queryParameters: {
                if (reason != SignInReason.none) 'reason': reason.name,
              },
            ).toString(),
          )
          .catchError((Object _) {
            SignInGate.answer(false);
            return null;
          }),
    );
    return await answer.future;
  } finally {
    if (identical(SignInGate._answer, answer)) SignInGate._answer = null;
    SignInGate.isOpen.value = false;
  }
}
