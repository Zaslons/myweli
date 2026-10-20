"use client";

import { useEffect, useRef, useState } from "react";
import { NO_SHOW_CONFIRM, noShowConfirmLines } from "../../lib/pro/lifecycle";
import { Button } from "../Button";

/// « Non présenté » / « Marquer comme absent », always confirmed — the app's
/// dialog in words, the web's inline box in shape (the detail page's idiom;
/// the panel is already a non-modal dialog, so no modal on top of it).
/// docs/design/web-pro-journal-panel-deposit.md §2.2.
///
/// The caller decides WHETHER to offer it (`actionsFor` — only once the start
/// is past); this decides HOW: nothing is sent before « Marquer absent ».
///
/// Focus (SYSTEM §15): the box opens on « Annuler », the safe default; backing
/// out returns to the button that opened it, so a keyboard user is never
/// dropped on <body> by a box that replaced the control they were on.
export function NoShowAction({
  label,
  depositAmount,
  busy,
  onConfirm,
}: {
  label: string;
  depositAmount?: number;
  busy: boolean;
  onConfirm: () => void;
}) {
  const [asking, setAsking] = useState(false);
  const cancelRef = useRef<HTMLButtonElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  // Set when the box closes by « Annuler » — not when it closes because the
  // act went through (the control is gone then).
  const restore = useRef(false);

  useEffect(() => {
    if (asking) cancelRef.current?.focus();
    else if (restore.current) {
      restore.current = false;
      triggerRef.current?.focus();
    }
  }, [asking]);

  if (!asking) {
    return (
      <Button
        ref={triggerRef}
        variant="secondary"
        disabled={busy}
        onClick={() => setAsking(true)}
      >
        {label}
      </Button>
    );
  }

  return (
    <div className="w-full rounded-lg bg-surface p-m">
      <p className="text-bodyMedium font-medium text-textPrimary">
        {NO_SHOW_CONFIRM.title}
      </p>
      {noShowConfirmLines(depositAmount).map((line) => (
        <p key={line} className="mt-xs text-bodyMedium text-textSecondary">
          {line}
        </p>
      ))}
      <div className="mt-s flex flex-wrap gap-s">
        <Button
          ref={cancelRef}
          variant="secondary"
          onClick={() => {
            restore.current = true;
            setAsking(false);
          }}
        >
          Annuler
        </Button>
        <Button disabled={busy} onClick={onConfirm}>
          {NO_SHOW_CONFIRM.confirm}
        </Button>
      </div>
    </div>
  );
}
