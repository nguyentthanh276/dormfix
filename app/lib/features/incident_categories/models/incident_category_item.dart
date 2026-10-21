class IncidentCategoryItem {
  final String id;
  final String name;
  final bool isActive;
  final DateTime createdAt;

  IncidentCategoryItem({
    required this.id,
    required this.name,
    required this.isActive,
    required this.createdAt,
  });

  factory IncidentCategoryItem.fromJson(Map<String, dynamic> json) {
    return IncidentCategoryItem(
      id: json['id'] as String,
      name: json['name'] as String,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}