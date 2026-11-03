import '../../../core/models/repair_status.dart';

/// One assignment, including a frozen summary after it leaves the technician.
class TechnicianWorkHistoryEntry {
  const TechnicianWorkHistoryEntry({
    required this.assignmentId,
    required this.requestId,
    required this.requestCode,
    required this.title,
    required this.roomCode,
    required this.assignedAt,
    required this.endedAt,
    required this.status,
    required this.canOpenDetail,
  });

  factory TechnicianWorkHistoryEntry.fromJson(Map<String, dynamic> json) {
    final canOpenDetail = _boolean(json, 'can_open_detail');
    final requestId = _nullableString(json, 'request_id');
    final statusValue = _nullableString(json, 'status');
    final assignedAt = trackingTimestamp(json, 'assigned_at');
    final endedAt = _nullableTimestamp(json, 'ended_at');
    final statuses = RepairStatus.values.where(
      (status) => status.databaseValue == statusValue,
    );
    if (canOpenDetail != (requestId != null) ||
        (canOpenDetail && (statuses.length != 1 || endedAt != null)) ||
        (!canOpenDetail && statusValue != null) ||
        (endedAt != null && endedAt.isBefore(assignedAt))) {
      throw const FormatException('Invalid history access contract.');
    }
    return TechnicianWorkHistoryEntry(
      assignmentId: _string(json, 'assignment_id'),
      requestId: requestId,
      requestCode: _string(json, 'request_code'),
      title: _string(json, 'title'),
      roomCode: _string(json, 'room_code'),
      assignedAt: assignedAt,
      endedAt: endedAt,
      status: canOpenDetail ? statuses.single : null,
      canOpenDetail: canOpenDetail,
    );
  }

  final String assignmentId;
  final String? requestId;
  final String requestCode;
  final String title;
  final String roomCode;
  final DateTime assignedAt;
  final DateTime? endedAt;
  final RepairStatus? status;
  final bool canOpenDetail;
}

class TechnicianNotification {
  const TechnicianNotification({
    required this.id,
    required this.eventType,
    required this.message,
    required this.createdAt,
    required this.readAt,
    required this.requestId,
    required this.canOpenDetail,
  });

  factory TechnicianNotification.fromJson(Map<String, dynamic> json) {
    final canOpenDetail = _boolean(json, 'can_open_detail');
    final requestId = _nullableString(json, 'request_id');
    final eventType = _string(json, 'event_type');
    if (canOpenDetail != (requestId != null) ||
        !const {
          'assigned',
          'transferred_in',
          'transferred_out',
          'cancelled',
          'rejected',
          'repair_reported',
          'rework_requested',
          'completed',
        }.contains(eventType)) {
      throw const FormatException('Invalid notification access contract.');
    }
    return TechnicianNotification(
      id: _string(json, 'id'),
      eventType: eventType,
      message: _string(json, 'message'),
      createdAt: trackingTimestamp(json, 'created_at'),
      readAt: _nullableTimestamp(json, 'read_at'),
      requestId: requestId,
      canOpenDetail: canOpenDetail,
    );
  }

  final String id;
  final String eventType;
  final String message;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? requestId;
  final bool canOpenDetail;

  TechnicianNotification copyWithReadAt(DateTime value) =>
      TechnicianNotification(
        id: id,
        eventType: eventType,
        message: message,
        createdAt: createdAt,
        readAt: value,
        requestId: requestId,
        canOpenDetail: canOpenDetail,
      );
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Expected a nonempty string.');
  }
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw const FormatException('Expected a nullable field.');
  }
  return json[key] == null ? null : _string(json, key);
}

bool _boolean(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw const FormatException('Expected a boolean.');
  return value;
}

DateTime trackingTimestamp(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const FormatException('Expected a timestamp with a time zone.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('Invalid timestamp.');
  return parsed.toUtc();
}

DateTime? _nullableTimestamp(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw const FormatException('Expected a nullable timestamp.');
  }
  return json[key] == null ? null : trackingTimestamp(json, key);
}
