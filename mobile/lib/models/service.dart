import 'package:equatable/equatable.dart';

class Service extends Equatable {
  final String id;
  final String name;
  final String description;
  final double price; // the "from" (minimum) price
  final double? priceMax; // optional upper bound for a price range
  final int durationMinutes;
  final String providerId;
  final List<String> artistIds; // Artists who can perform this service

  const Service({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.priceMax,
    required this.durationMinutes,
    required this.providerId,
    this.artistIds = const [], // Empty list means all artists can perform it
  });

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        price,
        priceMax,
        durationMinutes,
        providerId,
        artistIds,
      ];

  Service copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    double? priceMax,
    int? durationMinutes,
    String? providerId,
    List<String>? artistIds,
  }) {
    return Service(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      priceMax: priceMax ?? this.priceMax,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      providerId: providerId ?? this.providerId,
      artistIds: artistIds ?? this.artistIds,
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
      'providerId': providerId,
      'artistIds': artistIds,
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
      providerId: json['providerId'] as String,
      artistIds: json['artistIds'] != null
          ? List<String>.from(json['artistIds'] as List)
          : [],
    );
  }
}
