import 'package:equatable/equatable.dart';

/// Channel a message is sent over. WhatsApp is the default; SMS is the
/// fallback when WhatsApp delivery isn't possible.
enum MessageChannel { whatsApp, sms, push }

enum DeliveryStatus { queued, sent, delivered, failed }

/// Whether a message is operational (always allowed) or marketing (requires
/// explicit opt-in — ARTCI / WhatsApp policy, PRD §16).
enum MessageCategory { transactional, promotional }

/// The notification events from FR-NOTIF-001. Each maps to an approved
/// WhatsApp Business template on the backend.
enum MessageTemplate {
  bookingConfirmed,
  depositReceived,
  reminder24h,
  reminder2h,
  bookingAccepted,
  bookingDeclined,
  rescheduled,
  cancelled,
  refund,
  rebookReminder, // promotional (FR-NOTIF-003)
}

extension MessageTemplateX on MessageTemplate {
  MessageCategory get category => this == MessageTemplate.rebookReminder
      ? MessageCategory.promotional
      : MessageCategory.transactional;
}

/// A message handed to the messaging provider. Shaped to the BSP DTO
/// (template name + params + delivery status from the status webhook).
class OutboundMessage extends Equatable {
  final String id;
  final String recipientPhone;
  final MessageChannel channel;
  final MessageTemplate template;
  final Map<String, String> params;
  final String body;
  final DeliveryStatus status;
  final DateTime createdAt;

  const OutboundMessage({
    required this.id,
    required this.recipientPhone,
    required this.channel,
    required this.template,
    required this.params,
    required this.body,
    required this.status,
    required this.createdAt,
  });

  OutboundMessage copyWith({MessageChannel? channel, DeliveryStatus? status}) {
    return OutboundMessage(
      id: id,
      recipientPhone: recipientPhone,
      channel: channel ?? this.channel,
      template: template,
      params: params,
      body: body,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props =>
      [id, recipientPhone, channel, template, params, body, status, createdAt];

  Map<String, dynamic> toJson() => {
        'id': id,
        'recipientPhone': recipientPhone,
        'channel': channel.name,
        'template': template.name,
        'params': params,
        'body': body,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory OutboundMessage.fromJson(Map<String, dynamic> json) =>
      OutboundMessage(
        id: json['id'] as String,
        recipientPhone: json['recipientPhone'] as String,
        channel: MessageChannel.values.firstWhere(
          (e) => e.name == json['channel'],
          orElse: () => MessageChannel.whatsApp,
        ),
        template: MessageTemplate.values.firstWhere(
          (e) => e.name == json['template'],
          orElse: () => MessageTemplate.bookingConfirmed,
        ),
        params: Map<String, String>.from(json['params'] as Map),
        body: json['body'] as String,
        status: DeliveryStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => DeliveryStatus.queued,
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
