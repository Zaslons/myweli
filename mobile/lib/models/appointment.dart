import 'package:equatable/equatable.dart';

enum AppointmentStatus {
  pending,
  confirmed,
  cancelled,
  completed,
  noShow,
}

class Appointment extends Equatable {
  final String id;
  final String userId;
  final String providerId;
  final List<String> serviceIds;
  final String? artistId; // The artist assigned to this appointment
  final DateTime appointmentDate;
  final AppointmentStatus status;
  final double totalPrice;
  final double depositAmount;
  final double balanceDue;

  /// Snapshot of the provider's cancellation window (hours) at booking time, so
  /// the policy that governs this appointment can't change underneath the user.
  final int cancellationWindowHours;

  /// Walk-in client details for a manually-entered booking (no app account).
  /// Null for bookings made by an app user.
  final String? clientName;
  final String? clientPhone;
  final String? notes;

  /// Proof-of-deposit screenshot the client optionally attached (the deposit is
  /// paid directly to the salon; Myweli doesn't process it).
  final String? depositScreenshotUrl;
  final DateTime createdAt;

  const Appointment({
    required this.id,
    required this.userId,
    required this.providerId,
    required this.serviceIds,
    this.artistId,
    required this.appointmentDate,
    required this.status,
    required this.totalPrice,
    this.depositAmount = 0,
    this.balanceDue = 0,
    this.cancellationWindowHours = 24,
    this.clientName,
    this.clientPhone,
    this.notes,
    this.depositScreenshotUrl,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        userId,
        providerId,
        serviceIds,
        artistId,
        appointmentDate,
        status,
        totalPrice,
        depositAmount,
        balanceDue,
        cancellationWindowHours,
        clientName,
        clientPhone,
        notes,
        depositScreenshotUrl,
        createdAt,
      ];

  Appointment copyWith({
    String? id,
    String? userId,
    String? providerId,
    List<String>? serviceIds,
    String? artistId,
    DateTime? appointmentDate,
    AppointmentStatus? status,
    double? totalPrice,
    double? depositAmount,
    double? balanceDue,
    int? cancellationWindowHours,
    String? clientName,
    String? clientPhone,
    String? notes,
    String? depositScreenshotUrl,
    DateTime? createdAt,
  }) {
    return Appointment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      providerId: providerId ?? this.providerId,
      serviceIds: serviceIds ?? this.serviceIds,
      artistId: artistId ?? this.artistId,
      appointmentDate: appointmentDate ?? this.appointmentDate,
      status: status ?? this.status,
      totalPrice: totalPrice ?? this.totalPrice,
      depositAmount: depositAmount ?? this.depositAmount,
      balanceDue: balanceDue ?? this.balanceDue,
      cancellationWindowHours:
          cancellationWindowHours ?? this.cancellationWindowHours,
      clientName: clientName ?? this.clientName,
      clientPhone: clientPhone ?? this.clientPhone,
      notes: notes ?? this.notes,
      depositScreenshotUrl: depositScreenshotUrl ?? this.depositScreenshotUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'providerId': providerId,
      'serviceIds': serviceIds,
      'artistId': artistId,
      'appointmentDate': appointmentDate.toIso8601String(),
      'status': status.name,
      'totalPrice': totalPrice,
      'depositAmount': depositAmount,
      'balanceDue': balanceDue,
      'cancellationWindowHours': cancellationWindowHours,
      'clientName': clientName,
      'clientPhone': clientPhone,
      'notes': notes,
      'depositScreenshotUrl': depositScreenshotUrl,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: json['id'] as String,
      userId: json['userId'] as String,
      providerId: json['providerId'] as String,
      serviceIds: List<String>.from(json['serviceIds'] as List),
      artistId: json['artistId'] as String?,
      appointmentDate: DateTime.parse(json['appointmentDate'] as String),
      status: AppointmentStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => AppointmentStatus.pending,
      ),
      totalPrice: (json['totalPrice'] as num).toDouble(),
      depositAmount: (json['depositAmount'] as num?)?.toDouble() ?? 0,
      balanceDue: (json['balanceDue'] as num?)?.toDouble() ?? 0,
      cancellationWindowHours: json['cancellationWindowHours'] as int? ?? 24,
      clientName: json['clientName'] as String?,
      clientPhone: json['clientPhone'] as String?,
      notes: json['notes'] as String?,
      depositScreenshotUrl: json['depositScreenshotUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
