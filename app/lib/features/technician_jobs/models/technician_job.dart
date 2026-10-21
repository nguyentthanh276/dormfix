import '../../../core/models/repair_status.dart';
import 'technician_workflow.dart';

class TechnicianJob {
  const TechnicianJob({
    required this.id,
    required this.requestCode,
    required this.title,
    required this.description,
    required this.roomCode,
    required this.building,
    required this.categoryName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
  });

  factory TechnicianJob.fromJson(Map<String, dynamic> json) {
    final statusValue = _string(json, 'status');
    final statuses = RepairStatus.values.where(
      (status) => status.databaseValue == statusValue,
    );
    if (statuses.isEmpty) throw const FormatException('Invalid job status.');

    return TechnicianJob(
      id: _string(json, 'id'),
      requestCode: _string(json, 'request_code'),
      title: _string(json, 'title'),
      description: _string(json, 'description'),
      roomCode: _string(json, 'room_code'),
      building: _string(json, 'building'),
      categoryName: _string(json, 'category_name'),
      status: statuses.single,
      createdAt: _date(json, 'created_at'),
      updatedAt: _date(json, 'updated_at'),
      version: _positiveInt(json, 'version'),
    );
  }

  final String id;
  final String requestCode;
  final String title;
  final String description;
  final String roomCode;
  final String building;
  final String categoryName;
  final RepairStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
}

class TechnicianJobDetail {
  const TechnicianJobDetail({
    required this.job,
    required this.studentName,
    required this.studentPhone,
    required this.attachments,
    required this.results,
    required this.feedback,
    required this.history,
    required this.assignments,
    this.workflow = const TechnicianWorkflowCapabilities(),
  });

  factory TechnicianJobDetail.fromJson(Map<String, dynamic> json) {
    final student = _map(json['student']);
    return TechnicianJobDetail(
      job: TechnicianJob.fromJson(_map(json['request'])),
      studentName: _string(student, 'full_name'),
      studentPhone: _string(student, 'phone'),
      attachments: _list(json, 'attachments', JobAttachment.fromJson),
      results: _list(json, 'results', JobResult.fromJson),
      feedback: _list(json, 'feedback', JobFeedback.fromJson),
      history: _list(json, 'history', JobHistoryEntry.fromJson),
      assignments: _list(json, 'assignments', JobAssignment.fromJson),
      workflow: json.containsKey('workflow')
          ? TechnicianWorkflowCapabilities.fromJson(_map(json['workflow']))
          : const TechnicianWorkflowCapabilities(),
    );
  }

  final TechnicianJob job;
  final String studentName;
  final String studentPhone;
  final List<JobAttachment> attachments;
  final List<JobResult> results;
  final List<JobFeedback> feedback;
  final List<JobHistoryEntry> history;
  final List<JobAssignment> assignments;
  final TechnicianWorkflowCapabilities workflow;
}

class JobAttachment {
  const JobAttachment({
    required this.id,
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.resultId,
    required this.feedbackId,
  });

  factory JobAttachment.fromJson(Map<String, dynamic> json) {
    final mimeType = _string(json, 'mime_type');
    final sizeBytes = _positiveInt(json, 'size_bytes');
    final resultId = _nullableString(json, 'result_id');
    final feedbackId = _nullableString(json, 'feedback_id');
    if (!const ['image/jpeg', 'image/png', 'image/webp'].contains(mimeType) ||
        sizeBytes > 5242880 ||
        (resultId != null && feedbackId != null)) {
      throw const FormatException('Invalid attachment metadata.');
    }
    return JobAttachment(
      id: _string(json, 'id'),
      storagePath: _string(json, 'storage_path'),
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      resultId: resultId,
      feedbackId: feedbackId,
    );
  }

  final String id;
  final String storagePath;
  final String mimeType;
  final int sizeBytes;
  final String? resultId;
  final String? feedbackId;
}

class JobResult {
  const JobResult({
    required this.id,
    required this.content,
    required this.submittedAt,
    required this.technicianName,
  });

  factory JobResult.fromJson(Map<String, dynamic> json) => JobResult(
    id: _string(json, 'id'),
    content: _string(json, 'content'),
    submittedAt: _date(json, 'submitted_at'),
    technicianName: _string(json, 'technician_name'),
  );

  final String id;
  final String content;
  final DateTime submittedAt;
  final String technicianName;
}

class JobFeedback {
  const JobFeedback({
    required this.id,
    required this.kind,
    required this.reason,
    required this.createdAt,
    required this.authorName,
  });

  factory JobFeedback.fromJson(Map<String, dynamic> json) {
    final kind = _string(json, 'kind');
    if (kind != 'rework' && kind != 'reopen') {
      throw const FormatException('Invalid feedback kind.');
    }
    return JobFeedback(
      id: _string(json, 'id'),
      kind: kind,
      reason: _string(json, 'reason'),
      createdAt: _date(json, 'created_at'),
      authorName: _string(json, 'author_name'),
    );
  }

  final String id;
  final String kind;
  final String reason;
  final DateTime createdAt;
  final String authorName;
}

class JobHistoryEntry {
  const JobHistoryEntry({
    required this.id,
    required this.action,
    required this.actorName,
    required this.oldStatus,
    required this.newStatus,
    required this.note,
    required this.occurredAt,
  });

  factory JobHistoryEntry.fromJson(Map<String, dynamic> json) =>
      JobHistoryEntry(
        id: _string(json, 'id'),
        action: _string(json, 'action'),
        actorName: _string(json, 'actor_name'),
        oldStatus: _nullableString(json, 'old_status'),
        newStatus: _nullableString(json, 'new_status'),
        note: _nullableString(json, 'note'),
        occurredAt: _date(json, 'occurred_at'),
      );

  final String id;
  final String action;
  final String actorName;
  final String? oldStatus;
  final String? newStatus;
  final String? note;
  final DateTime occurredAt;
}

class JobAssignment {
  const JobAssignment({
    required this.id,
    required this.technicianName,
    required this.assignedByName,
    required this.assignedAt,
    required this.endedAt,
    required this.transferReason,
    required this.endReason,
  });

  factory JobAssignment.fromJson(Map<String, dynamic> json) => JobAssignment(
    id: _string(json, 'id'),
    technicianName: _string(json, 'technician_name'),
    assignedByName: _string(json, 'assigned_by_name'),
    assignedAt: _date(json, 'assigned_at'),
    endedAt: _nullableDate(json, 'ended_at'),
    transferReason: _nullableString(json, 'transfer_reason'),
    endReason: _nullableString(json, 'end_reason'),
  );

  final String id;
  final String technicianName;
  final String assignedByName;
  final DateTime assignedAt;
  final DateTime? endedAt;
  final String? transferReason;
  final String? endReason;
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected a JSON object.');
  }
  return Map<String, dynamic>.from(value);
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Expected a non-empty string.');
  }
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw const FormatException('Missing nullable field.');
  }
  final value = json[key];
  if (value != null && value is! String) {
    throw const FormatException('Expected a nullable string.');
  }
  return value as String?;
}

int _positiveInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value <= 0) {
    throw const FormatException('Expected a positive integer.');
  }
  return value;
}

DateTime _date(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw const FormatException('Expected a timestamp with a time zone.');
  }
  return parsed.toUtc();
}

DateTime? _nullableDate(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw const FormatException('Missing nullable timestamp.');
  }
  return json[key] == null ? null : _date(json, key);
}

List<T> _list<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) parse,
) {
  final value = json[key];
  if (value is! List) throw const FormatException('Expected a JSON array.');
  return List<T>.unmodifiable(value.map((item) => parse(_map(item))));
}
