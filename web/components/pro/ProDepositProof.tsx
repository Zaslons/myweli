"use client";

import { useEffect, useState } from "react";
import { proDepositScreenshotUrl } from "../../lib/api/pro";
import {
  type LoadFailure,
  loadFailure,
  loadFailureMessage,
} from "../../lib/pro/load-failure";
import { Button } from "../Button";
import { Lightbox } from "../Lightbox";
import { Skeleton } from "../Skeleton";

/// The salon's view of a client's deposit — the guidance and the screenshot,
/// under the « Acompte annoncé » line its host renders
/// (docs/design/web-pro-journal-panel-deposit.md §2.1). One component for the
/// « Journée » panel and the booking page: the app's `_DepositProof`
/// (`pro_appointment_detail_screen.dart:397-472`), which loads by itself and
/// enlarges on a tap.
///
/// There is no other « statut d'acompte »: MyWeli never holds the money — the
/// client pays the salon by Mobile Money and attaches a screenshot; the salon
/// confirms it received it by accepting the booking. The screenshot IS the
/// status.

const GUIDANCE =
  "Confirmez le rendez-vous une fois l’acompte reçu sur votre compte Mobile Money.";
const NO_PROOF = "Aucune capture jointe pour le moment.";
const UNAVAILABLE = "Capture indisponible. Réessayez.";
const PROOF_LABEL = "Justificatif d’acompte";

type State =
  | { kind: "loading" }
  | { kind: "ready"; url: string }
  | { kind: "failed"; failure: LoadFailure };

export function ProDepositProof({
  appointmentId,
  hasProof,
  pending,
  canView,
}: {
  appointmentId: string;
  /// The booking carries a screenshot key (`depositScreenshotUrl`).
  hasProof: boolean;
  /// The guidance tells when to press « Accepter » — said only while there is
  /// one to press (owner decision Q1; the app says it in every state).
  pending: boolean;
  /// `journal.view.all`. The server signs the screenshot for no one else
  /// (deposit_service.dart): a Collaborateur would get a guaranteed 403 — so
  /// no request, no guidance (they cannot accept), only the host's amount.
  canView: boolean;
}) {
  const [state, setState] = useState<State>({ kind: "loading" });
  const [attempt, setAttempt] = useState(0);
  const [enlarged, setEnlarged] = useState(false);

  // Every attempt asks for a NEW signed URL, not just the image again: the
  // URL lives 5 minutes (deposit_service.dart `_viewTtl`), and a panel left
  // open outlives it.
  useEffect(() => {
    if (!canView || !hasProof) return;
    let active = true;
    setState({ kind: "loading" });
    proDepositScreenshotUrl(appointmentId).then((r) => {
      if (!active) return;
      setState(
        r.status === 200 && r.url
          ? { kind: "ready", url: r.url }
          : { kind: "failed", failure: loadFailure(r.status) },
      );
    });
    return () => {
      active = false;
    };
  }, [appointmentId, hasProof, canView, attempt]);

  if (!canView) return null;

  return (
    <div className="space-y-s">
      {pending ? (
        <p className="text-bodySmall text-textTertiary">{GUIDANCE}</p>
      ) : null}
      {/* A polite region that exists before its text (WEB-SYSTEM §7): a
          failure that lands after the panel opened is announced. */}
      <div data-deposit-proof aria-live="polite">
        {!hasProof ? (
          <p className="text-bodySmall text-textTertiary">{NO_PROOF}</p>
        ) : state.kind === "loading" ? (
          // The shape is known — a thumbnail — so a skeleton, not a spinner
          // (§12). `aria-hidden` by the component.
          <Skeleton className="h-36 w-28" />
        ) : state.kind === "failed" ? (
          <div className="space-y-s">
            <p className="text-bodySmall text-textSecondary">
              {loadFailureMessage(state.failure, UNAVAILABLE)}
            </p>
            <Button variant="secondary" onClick={() => setAttempt((n) => n + 1)}>
              Réessayer
            </Button>
          </div>
        ) : (
          <button
            type="button"
            aria-label="Agrandir le justificatif d’acompte"
            onClick={() => setEnlarged(true)}
            className="block min-w-12 rounded-lg"
          >
            {/* A signed, short-lived URL on private storage: next/image would
                proxy and cache it, which is exactly what it must not be. */}
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={state.url}
              alt={PROOF_LABEL}
              // The URL expired, or the bytes are gone: say so, like a failed
              // read — « Réessayer » signs a fresh one.
              onError={() => setState({ kind: "failed", failure: "failed" })}
              className="block h-36 w-auto max-w-full rounded-lg border border-border object-cover"
            />
          </button>
        )}
      </div>
      {enlarged && state.kind === "ready" ? (
        <Lightbox
          url={state.url}
          label={PROOF_LABEL}
          onClose={() => setEnlarged(false)}
        />
      ) : null}
    </div>
  );
}
