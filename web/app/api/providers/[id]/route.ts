import { type NextRequest, NextResponse } from 'next/server';
import { apiBase } from '../../../../lib/server-api';

/// BFF: public provider lookup by id (same-origin proxy of GET /providers/{id}).
///
/// Added by A14d for the account reschedule screen, which holds an
/// `Appointment` and therefore knows the salon's **id** but not its bookable
/// window — and without the window it cannot tell a client « ce salon accepte
/// les réservations jusqu'au … » rather than the false « aucun créneau ».
///
/// The consumer funnel needs no such call: its page already server-renders the
/// provider. This is the reschedule surface's equivalent of mobile's
/// `showRescheduleScreen`, which takes a required `models.Provider` for the
/// same reason and whose caller fetches it.
///
/// Public and unauthenticated, exactly like the upstream route — the provider
/// document is already the public payload every salon page renders.
export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const r = await fetch(`${apiBase}/providers/${encodeURIComponent(id)}`);
  const body = await r.json().catch(() => ({}));
  return NextResponse.json(body, { status: r.status });
}
