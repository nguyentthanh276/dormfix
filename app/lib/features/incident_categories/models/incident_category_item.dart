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
    final id = json['id'] as String;
    final name = json['name'] as String;
    final createdAt = json['created_at'] as String;
    if (id.isEmpty ||
        name.trim().isEmpty ||
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(createdAt)) {
      throw const FormatException('Invalid category fields.');
    }
    return IncidentCategoryItem(
      id: id,
      name: name,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(createdAt).toUtc(),
    );
  }
}
