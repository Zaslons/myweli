import 'package:flutter/material.dart';

import '../../models/appointment.dart';
import '../theme/chip_tone.dart';
import '../theme/colors.dart';

/// The canonical appointment-status → colour mapping, by **kind** — the owner's
/// B7 decision, « kind-tinted StatusChip everywhere » (web-b7-desktop.md;
/// SYSTEM §11.2: kind, not colour, is the API): confirmed is ok, pending is
/// pending, cancelled and a no-show are danger, completed is neutral — as the
/// admin's `AdminChipKind` and the web's `statusChipKind` say it.
///
/// It said confirmed = info, completed = success and a no-show = warning
/// until B9.8 F3, while the client's booking card said confirmed = success
/// and the home tile a third thing: one status, three colours. The JOURNAL
/// keeps its own day-view language — an arrival is the green one, confirmed
/// is info — in the app and on the web alike (`_TimelineCard`,
/// `web/lib/pro/journal.ts` `STATUS_STYLE`).
Color appointmentStatusColor(AppointmentStatus status) => switch (status) {
  AppointmentStatus.pending => AppColors.warning,
  AppointmentStatus.confirmed => AppColors.success,
  AppointmentStatus.completed => AppColors.textSecondary,
  AppointmentStatus.cancelled => AppColors.error,
  AppointmentStatus.noShow => AppColors.error,
};

/// The same mapping as a chip's tone (`AppChip.status`, B9.8 F3) — one
/// status, one look, in the client's cards and the Pro's lists alike.
AppChipTone appointmentStatusTone(AppointmentStatus status) => switch (status) {
  AppointmentStatus.pending => AppChipTone.warning,
  AppointmentStatus.confirmed => AppChipTone.success,
  AppointmentStatus.completed => AppChipTone.neutral,
  AppointmentStatus.cancelled => AppChipTone.error,
  AppointmentStatus.noShow => AppChipTone.error,
};
