import 'package:equatable/equatable.dart';

/// Optional duration (in minutes) by hair length/type. A service that takes
/// longer for longer hair declares these; an empty set means the service uses
/// its single [Service.durationMinutes]. Shaped as `{court, moyen, long}`.
class DurationVariants extends Equatable {
  final int? court;
  final int? moyen;
  final int? long;

  const DurationVariants({this.court, this.moyen, this.long});

  bool get isEmpty => court == null && moyen == null && long == null;
  bool get isNotEmpty => !isEmpty;

  @override
  List<Object?> get props => [court, moyen, long];

  Map<String, dynamic> toJson() => {
        if (court != null) 'court': court,
        if (moyen != null) 'moyen': moyen,
        if (long != null) 'long': long,
      };

  factory DurationVariants.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DurationVariants();
    return DurationVariants(
      court: (json['court'] as num?)?.toInt(),
      moyen: (json['moyen'] as num?)?.toInt(),
      long: (json['long'] as num?)?.toInt(),
    );
  }
}

class Service extends Equatable {
  final String id;
  final String name;
  final String description;
  final double price; // the "from" (minimum) price
  final double? priceMax; // optional upper bound for a price range
  final int durationMinutes; // default duration
  final DurationVariants durationVariants; // optional per-length durations
  final String providerId;
  final List<String> artistIds; // Artists who can perform this service
  final bool active; // false = hidden from booking (server enforces)

  const Service({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.priceMax,
    required this.durationMinutes,
    this.durationVariants = const DurationVariants(),
    required this.providerId,
    this.artistIds = const [], // Empty list means all artists can perform it
    this.active = true,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        price,
        priceMax,
        durationMinutes,
        durationVariants,
        providerId,
        artistIds,
        active,
      ];

  Service copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    double? priceMax,
    int? durationMinutes,
    DurationVariants? durationVariants,
    String? providerId,
    List<String>? artistIds,
    bool? active,
  }) {
    return Service(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      priceMax: priceMax ?? this.priceMax,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      durationVariants: durationVariants ?? this.durationVariants,
      providerId: providerId ?? this.providerId,
      artistIds: artistIds ?? this.artistIds,
      active: active ?? this.active,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'priceMax': priceMax,
      'durationMinutes': durationMinutes,
      'durationVariants': durationVariants.toJson(),
      'providerId': providerId,
      'artistIds': artistIds,
      'active': active,
    };
  }

  factory Service.fromJson(Map<String, dynamic> json) {
    return Service(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      priceMax: (json['priceMax'] as num?)?.toDouble(),
      durationMinutes: json['durationMinutes'] as int,
      durationVariants: DurationVariants.fromJson(
        json['durationVariants'] as Map<String, dynamic>?,
      ),
      providerId: json['providerId'] as String,
      artistIds: json['artistIds'] != null
          ? List<String>.from(json['artistIds'] as List)
          : [],
      active: json['active'] as bool? ?? true,
    );
  }
}
