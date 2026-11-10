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
    List<String> studentNames = const [],
  }) : studentNames = List.unmodifiable(studentNames);

  factory AdminRoom.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final code = json['code'] as String;
    final building = json['building'] as String;
    final profiles = json['profiles'] as List;
    if (id.isEmpty ||
        code.trim().isEmpty ||
        building.trim().isEmpty ||
        json['student_count'] is! int ||
        json['student_count'] != profiles.length) {
      throw const FormatException('Invalid room fields.');
    }
    return AdminRoom(
      id: id,
      code: code,
      building: building,
      isActive: json['is_active'] as bool,
      studentNames: profiles
          .map((profile) {
            final name = (profile as Map)['full_name'] as String;
            if (name.trim().isEmpty) {
              throw const FormatException('Invalid student name.');
            }
            return name;
          })
          .toList(growable: false),
    );
  }
}
