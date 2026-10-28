class AdminRoom {
  final String id;
  final String code;
  final String building;
  final bool isActive;
  final List<String> studentNames;

  AdminRoom({
    required this.id,
    required this.code,
    required this.building,
    required this.isActive,
    this.studentNames = const [],
  });

  factory AdminRoom.fromJson(Map<String, dynamic> json) {
    List<String> students = [];
    if (json['profiles'] != null && json['profiles'] is List) {
      students = (json['profiles'] as List)
          .map((p) => (p['full_name'] ?? '') as String)
          .where((name) => name.isNotEmpty)
          .toList();
    }

    return AdminRoom(
      id: json['id'] as String,
      code: json['code'] as String,
      building: json['building'] as String,
      isActive: json['is_active'] as bool,
      studentNames: students,
    );
  }
}
