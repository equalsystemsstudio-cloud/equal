class GiftModel {
  final String id;
  final String name;
  final String iconKey;
  final int costCoins;
  final bool isActive;

  GiftModel({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.costCoins,
    required this.isActive,
  });

  factory GiftModel.fromJson(Map<String, dynamic> json) {
    return GiftModel(
      id: json['id'] as String,
      name: json['name'] as String,
      iconKey: json['icon_key'] as String,
      costCoins: json['cost_coins'] as int,
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

