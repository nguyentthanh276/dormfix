import '../../../core/models/repair_status.dart';

enum AdminRequestDateField {
  createdAt('created_at', 'Ngày tạo'),
  updatedAt('updated_at', 'Ngày cập nhật gần nhất');

  const AdminRequestDateField(this.databaseValue, this.label);
  final String databaseValue;
  final String label;
}

class AdminRequestFilters {
  const AdminRequestFilters({
    this.status,
    this.roomId,
    this.categoryId,
    this.technicianId,
    this.dateField,
    this.from,
    this.toExclusive,
  });

  /// Converts selected calendar days to an inclusive Vietnam-local range.
  /// Vietnam uses UTC+07:00; the exclusive upper bound is midnight after [toDate].
  factory AdminRequestFilters.forSaigonDateRange({
    RepairStatus? status,
    String? roomId,
    String? categoryId,
    String? technicianId,
    required AdminRequestDateField dateField,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final fromDay = DateTime.utc(fromDate.year, fromDate.month, fromDate.day);
    final toDay = DateTime.utc(toDate.year, toDate.month, toDate.day);
    if (fromDay.isAfter(toDay)) {
      throw ArgumentError('Ngày bắt đầu không được sau ngày kết thúc.');
    }
    const vietnamOffset = Duration(hours: 7);
    return AdminRequestFilters(
      status: status,
      roomId: roomId,
      categoryId: categoryId,
      technicianId: technicianId,
      dateField: dateField,
      from: fromDay.subtract(vietnamOffset),
      toExclusive: toDay.add(const Duration(days: 1)).subtract(vietnamOffset),
    );
  }

  final RepairStatus? status;
  final String? roomId;
  final String? categoryId;
  final String? technicianId;
  final AdminRequestDateField? dateField;
  final DateTime? from;
  final DateTime? toExclusive;

  bool get hasDateRange =>
      dateField != null && from != null && toExclusive != null;
}

class AdminRequestOption {
  const AdminRequestOption({
    required this.id,
    required this.label,
    this.subtitle,
  });

  factory AdminRequestOption.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final label = json['label'];
    if (id is! String || label is! String) {
      throw const FormatException('Dữ liệu bộ lọc không hợp lệ.');
    }
    return AdminRequestOption(
      id: id,
      label: label,
      subtitle: json['subtitle'] as String?,
    );
  }

  final String id;
  final String label;
  final String? subtitle;
}

class AdminRequestFilterOptions {
  const AdminRequestFilterOptions({
    required this.rooms,
    required this.categories,
    required this.technicians,
  });

  factory AdminRequestFilterOptions.fromJson(Map<String, dynamic> json) =>
      AdminRequestFilterOptions(
        rooms: _parseOptions(json['rooms']),
        categories: _parseOptions(json['categories']),
        technicians: _parseOptions(json['technicians']),
      );

  final List<AdminRequestOption> rooms;
  final List<AdminRequestOption> categories;
  final List<AdminRequestOption> technicians;
}

class AdminRequestSummary {
  const AdminRequestSummary({
    required this.id,
    required this.requestCode,
    required this.title,
    required this.roomCode,
    required this.categoryName,
    required this.studentName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.technicianName,
  });

  factory AdminRequestSummary.fromJson(Map<String, dynamic> json) {
    final statusValue = _requiredString(json, 'status');
    final statuses = RepairStatus.values.where(
      (status) => status.databaseValue == statusValue,
    );
    if (statuses.isEmpty) {
      throw const FormatException('Trạng thái yêu cầu không hợp lệ.');
    }
    return AdminRequestSummary(
      id: _requiredString(json, 'id'),
      requestCode: _requiredString(json, 'request_code'),
      title: _requiredString(json, 'title'),
      roomCode: _requiredString(json, 'room_code'),
      categoryName: _requiredString(json, 'category_name'),
      studentName: _requiredString(json, 'student_name'),
      technicianName: _nullableString(json, 'technician_name'),
      status: statuses.single,
      createdAt: _date(json, 'created_at'),
      updatedAt: _date(json, 'updated_at'),
    );
  }

  final String id;
  final String requestCode;
  final String title;
  final String roomCode;
  final String categoryName;
  final String studentName;
  final String? technicianName;
  final RepairStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class AdminRequestDetail {
  const AdminRequestDetail({
    required this.request,
    required this.description,
    required this.building,
    required this.studentStatus,
    required this.attachments,
    required this.results,
    required this.feedback,
    required this.history,
    required this.assignments,
  });

  factory AdminRequestDetail.fromJson(Map<String, dynamic> json) {
    final request = _object(json['request']);
    final student = _object(json['student']);
    return AdminRequestDetail(
      request: AdminRequestSummary.fromJson({
        ...request,
        'student_name': student['full_name'],
        'technician_name': _objectOrNull(json['technician'])?['full_name'],
      }),
      description: _requiredString(request, 'description'),
      building: _requiredString(request, 'building'),
      studentStatus: _requiredString(student, 'status'),
      attachments: _objects(json['attachments']),
      results: _objects(json['results']),
      feedback: _objects(json['feedback']),
      history: _objects(json['history']),
      assignments: _objects(json['assignments']),
    );
  }

  final AdminRequestSummary request;
  final String description;
  final String building;
  final String studentStatus;
  final List<Map<String, dynamic>> attachments;
  final List<Map<String, dynamic>> results;
  final List<Map<String, dynamic>> feedback;
  final List<Map<String, dynamic>> history;
  final List<Map<String, dynamic>> assignments;
}

List<AdminRequestOption> _parseOptions(Object? value) {
  if (value is! List) {
    throw const FormatException('Dữ liệu bộ lọc không hợp lệ.');
  }
  return List.unmodifiable(
    value.map((item) => AdminRequestOption.fromJson(_object(item))),
  );
}

List<Map<String, dynamic>> _objects(Object? value) {
  if (value is! List) {
    throw const FormatException('Dữ liệu chi tiết không hợp lệ.');
  }
  return List.unmodifiable(value.map(_object));
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Dữ liệu chi tiết không hợp lệ.');
  }
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic>? _objectOrNull(Object? value) =>
    value == null ? null : _object(value);

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Thiếu thông tin yêu cầu.');
  }
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value != null && value is! String) {
    throw const FormatException('Thông tin người xử lý không hợp lệ.');
  }
  return value as String?;
}

DateTime _date(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  final date = DateTime.tryParse(value);
  if (date == null) {
    throw const FormatException('Thời gian yêu cầu không hợp lệ.');
  }
  return date.toLocal();
}
