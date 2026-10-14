/// Model for an active room returned when listing rooms for student account creation.
class RoomSummary {
  const RoomSummary({
    required this.id,
    required this.code,
    required this.building,
  });

  factory RoomSummary.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final code = json['code'];
    final building = json['building'];
    if (id is! String || code is! String) {
      throw const FormatException('Dữ liệu phòng không hợp lệ.');
    }
    return RoomSummary(
      id: id,
      code: code,
      building: building is String ? building : null,
    );
  }

  final String id;
  final String code;
  final String? building;

  /// Display label, e.g. "DEMO-A101 (Tòa demo)".
  String get label => building != null ? '$code ($building)' : code;
}
