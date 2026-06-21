import 'package:equatable/equatable.dart';

enum AppointmentStatus {
  pending,
  confirmed,
  cancelled,
  completed,
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
  final String? notes;
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
    this.notes,
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
        notes,
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
    String? notes,
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
      notes: notes ?? this.notes,
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
      'notes': notes,
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
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
