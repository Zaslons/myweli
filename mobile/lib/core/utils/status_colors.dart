import 'package:flutter/material.dart';

import '../../models/appointment.dart';
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
