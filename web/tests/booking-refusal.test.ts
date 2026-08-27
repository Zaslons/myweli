import { describe, expect, it } from "vitest";
import { bookingErrorCta, conflictMessage } from "../lib/booking/window";

/// A salon that is not live — what each audience is told (§21 row 82).
///
/// **`conflictMessage` had no unit test at all before this file**, which is
/// part of how the gap survived: the two provider codes reached every one of
/// its six call sites and fell straight through `default` to whatever generic
/// sentence that surface injected — including two that say « Réessayez » for a
/// state retrying can never fix.
///
/// The distinction the tests below pin is the **tense**. « pas encore » is a
/// salon that has never published; « ne … plus » is one that was stopped. A
/// client hitting either through a stale link needs to know which, and a salon
/// owner needs a different sentence again for the same wire code — which is
/// what `audience` is for.
const client = {
  audience: "client" as const,
  taken: "TAKEN",
  fallback: "FALLBACK",
};
const salon = {
  audience: "salon" as const,
  taken: "TAKEN",
  fallback: "FALLBACK",
};

describe("a salon that is not live says which kind of not-live it is", () => {
  it("never published → « pas encore », to a client", () => {
    expect(conflictMessage("provider_not_published", client)).toBe(
      "Ce salon n’accepte pas encore de réservations en ligne.",
    );
  });

  it("stopped → « ne … plus », to a client", () => {
    expect(conflictMessage("provider_suspended", client)).toBe(
      "Ce salon ne prend plus de rendez-vous sur MyWeli.",
    );
  });

  it("the same wire code reads differently to the salon itself", () => {
    // The reason `audience` exists. A pro whose own salon was suspended is not
    // shopping for another one — they need to know their bookings survived and
    // who to talk to.
    expect(conflictMessage("provider_suspended", salon)).toBe(
      "Votre salon est suspendu. Contactez MyWeli pour le réactiver — vos rendez-vous sont intacts.",
    );
  });

  it("a client and a salon are told different things", () => {
    // Guards against a lazy implementation that ignores `audience` — without
    // this, one sentence for both would pass every test above but one.
    expect(conflictMessage("provider_suspended", client)).not.toBe(
      conflictMessage("provider_suspended", salon),
    );
  });
});

describe("the sentences that were already right stay right", () => {
  // The over-reach guard. `window.ts`'s own docstring records that a first
  // draft collapsed every surface into the consumer wording and an e2e pin
  // caught it; these keep the same mistake from being made a second time.
  it("slot_unavailable still returns the surface’s OWN sentence", () => {
    expect(conflictMessage("slot_unavailable", client)).toBe("TAKEN");
    expect(conflictMessage("slot_unavailable", salon)).toBe("TAKEN");
  });

  it("the two window codes are unchanged and audience-independent", () => {
    for (const ctx of [client, salon]) {
      expect(conflictMessage("beyond_horizon", ctx)).toBe(
        "Ce salon n’accepte pas encore les réservations à cette date.",
      );
      expect(conflictMessage("too_soon", ctx)).toBe(
        "Ce salon demande plus de délai avant un rendez-vous. Choisissez une date plus tardive.",
      );
    }
  });

  it("an unknown code, and no code at all, still fall back", () => {
    expect(conflictMessage("something_new", client)).toBe("FALLBACK");
    expect(conflictMessage(undefined, salon)).toBe("FALLBACK");
  });
});

describe("the way out is offered only where it leads somewhere", () => {
  // §12 requires an error to offer a way out. For these two codes the way out
  // is another salon — but ONLY for these two: a taken slot is fixed by
  // picking another time on the same salon, and sending that client away
  // would be wrong.
  it("both provider codes carry a link to discovery", () => {
    for (const code of ["provider_not_published", "provider_suspended"]) {
      expect(bookingErrorCta(code)).toEqual({
        label: "Découvrir des salons",
        href: "/",
      });
    }
  });

  it("nothing else does", () => {
    // The pair. Without it the CTA could be unconditional and every test
    // above would still pass.
    for (const code of [
      "slot_unavailable",
      "beyond_horizon",
      "too_soon",
      undefined,
    ]) {
      expect(bookingErrorCta(code)).toBeNull();
    }
  });
});

describe("invalid_phone names the field, for either audience", () => {
  // The manual-booking lesson: this code used to fall through `default` to
  // « Création impossible. Réessayez. » — a retry invitation for a failure
  // retrying can never fix. Same copy as « Ajouter un client », verbatim.
  it("maps to the international-format sentence", () => {
    const copy = "Numéro invalide (format international, ex. +2250700000000).";
    expect(conflictMessage("invalid_phone", salon)).toBe(copy);
    expect(conflictMessage("invalid_phone", client)).toBe(copy);
  });
});
