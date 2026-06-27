import 'package:equatable/equatable.dart';

/// A curated before/after pair of a salon's work (FR-DISC-006). Mirrors the
/// backend `BeforeAfterPair` (docs/api/openapi.yaml). `caption` is optional.
class BeforeAfterPair extends Equatable {
  final String before;
  final String after;
  final String? caption;

  const BeforeAfterPair({
    required this.before,
    required this.after,
    this.caption,
  });

  Map<String, dynamic> toJson() => {
        'before': before,
        'after': after,
        if (caption != null && caption!.isNotEmpty) 'caption': caption,
      };

  factory BeforeAfterPair.fromJson(Map<String, dynamic> json) {
    final caption = (json['caption'] as String?)?.trim();
    return BeforeAfterPair(
      before: json['before'] as String? ?? '',
      after: json['after'] as String? ?? '',
      caption: (caption == null || caption.isEmpty) ? null : caption,
    );
  }

  @override
  List<Object?> get props => [before, after, caption];
}
