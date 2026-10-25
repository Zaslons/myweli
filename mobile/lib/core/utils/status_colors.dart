import 'package:flutter/material.dart';

import '../../models/appointment.dart';
import '../theme/chip_tone.dart';
import '../theme/colors.dart';

/// The canonical appointment-status → color mapping (design tokens, not
/// literals). Use this everywhere a status is colored, so the pro calendar,
/// list, and detail stay consistent. Design: docs/design/DESIGN-STANDARDS.md.
Color appointmentStatusColor(AppointmentStatus status) => switch (status) {
  AppointmentStatus.pending => AppColors.warning,
  AppointmentStatus.confirmed => AppColors.info,
  AppointmentStatus.completed => AppColors.success,
  AppointmentStatus.cancelled => AppColors.error,
  AppointmentStatus.noShow => AppColors.warning,
};

/// The same mapping as a chip's tone (`AppChip.status`, B9.8 F3) — one
/// status, one look, in the client's cards and the Pro's lists alike.
AppChipTone appointmentStatusTone(AppointmentStatus status) => switch (status) {
  AppointmentStatus.pending => AppChipTone.warning,
  AppointmentStatus.confirmed => AppChipTone.info,
  AppointmentStatus.completed => AppChipTone.success,
  AppointmentStatus.cancelled => AppChipTone.error,
  AppointmentStatus.noShow => AppChipTone.warning,
};
