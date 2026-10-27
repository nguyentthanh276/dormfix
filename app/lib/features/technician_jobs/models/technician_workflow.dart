import 'dart:math';
import 'dart:typed_data';

import '../../../core/models/repair_status.dart';
import 'technician_job.dart';

class TechnicianWorkflowFailure implements Exception {
  const TechnicianWorkflowFailure(
    this.message, {
    this.accessDenied = false,
    this.conflict = false,
    this.uncertain = false,
  });

  final String message;
  final bool accessDenied;
  final bool conflict;
  final bool uncertain;

  @override
  String toString() => message;
}

/// Capabilities come from the server, never from status-only UI guesses.
class TechnicianWorkflowCapabilities {
  const TechnicianWorkflowCapabilities({
    this.canStart = false,
    this.canContinue = false,
    this.canConfirmTransfer = false,
    this.canSubmitResult = false,
    this.blockedReason,
  });

  factory TechnicianWorkflowCapabilities.fromJson(Map<String, dynamic> json) {
    final start = json['can_start'];
    final canContinue = json.containsKey('can_continue')
        ? json['can_continue']
        : false;
    final canConfirmTransfer = json.containsKey('can_confirm_transfer')
        ? json['can_confirm_transfer']
        : false;
    final submit = json['can_submit_result'];
    final reason = json['blocked_reason'];
    if (start is! bool ||
        canContinue is! bool ||
        canConfirmTransfer is! bool ||
        submit is! bool ||
        ([
              start,
              canContinue,
              canConfirmTransfer,
              submit,
            ].where((enabled) => enabled).length >
            1) ||
        !json.containsKey('blocked_reason') ||
        (reason != null && !_reasons.contains(reason))) {
      throw const FormatException('Invalid technician workflow capabilities.');
    }
    return TechnicianWorkflowCapabilities(
      canStart: start,
      canContinue: canContinue,
      canConfirmTransfer: canConfirmTransfer,
      canSubmitResult: submit,
      blockedReason: reason as String?,
    );
  }

  static const _reasons = {
    'READ_ONLY',
    'ASSIGNMENT_NOT_READY',
    'START_REQUIRED',
    'CONTINUE_REQUIRED',
    'TRANSFER_CONFIRMATION_REQUIRED',
  };

  final bool canStart;
  final bool canContinue;
  final bool canConfirmTransfer;
  final bool canSubmitResult;
  final String? blockedReason;
}

/// Owns an immutable copy, so an uncertain retry sends exactly the same bytes.
class TechnicianResultPhoto {
  TechnicianResultPhoto._({
    required this.id,
    required this.name,
    required Uint8List bytes,
    required this.mimeType,
    required this.extension,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  factory TechnicianResultPhoto.fromBytes({
    required String name,
    required Uint8List bytes,
  }) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const TechnicianWorkflowFailure(
        'Mỗi ảnh phải có dữ liệu và tối đa 5 MB.',
      );
    }
    final ({String mime, String extension}) type;
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      type = (mime: 'image/jpeg', extension: 'jpg');
    } else if (bytes.length >= 8 &&
        _prefix(bytes, [137, 80, 78, 71, 13, 10, 26, 10])) {
      type = (mime: 'image/png', extension: 'png');
    } else if (bytes.length >= 12 &&
        _prefix(bytes, [82, 73, 70, 70]) &&
        _prefix(bytes.sublist(8), [87, 69, 66, 80])) {
      type = (mime: 'image/webp', extension: 'webp');
    } else {
      throw const TechnicianWorkflowFailure(
        'Chỉ nhận ảnh JPG, PNG hoặc WebP hợp lệ.',
      );
    }
    return TechnicianResultPhoto._(
      id: newTechnicianWorkflowId(),
      name: name,
      bytes: bytes,
      mimeType: type.mime,
      extension: type.extension,
    );
  }

  static const maxBytes = 5 * 1024 * 1024;
  final String id;
  final String name;
  final Uint8List bytes;
  final String mimeType;
  final String extension;
  int get sizeBytes => bytes.length;
}

/// One immutable submission ID is retained across user-triggered retries.
class TechnicianResultSubmission {
  TechnicianResultSubmission._({
    required this.requestId,
    required this.expectedVersion,
    required this.resultId,
    required this.content,
    required List<TechnicianResultPhoto> photos,
  }) : photos = List.unmodifiable(photos);

  factory TechnicianResultSubmission.create({
    required TechnicianJob job,
    required String content,
    required List<TechnicianResultPhoto> photos,
  }) {
    if (!isTechnicianWorkflowId(job.id) || job.version <= 0) {
      throw const TechnicianWorkflowFailure(
        'Thông tin công việc không hợp lệ. Vui lòng tải lại.',
      );
    }
    if (content.trim().isEmpty) {
      throw const TechnicianWorkflowFailure('Vui lòng nhập kết quả sửa chữa.');
    }
    if (photos.length > maxPhotos ||
        photos.map((p) => p.id).toSet().length != photos.length) {
      throw const TechnicianWorkflowFailure(
        'Chỉ được đính kèm tối đa 5 ảnh khác nhau.',
      );
    }
    return TechnicianResultSubmission._(
      requestId: job.id,
      expectedVersion: job.version,
      resultId: newTechnicianWorkflowId(),
      content: content.trim(),
      photos: photos,
    );
  }

  static const maxPhotos = 5;
  final String requestId;
  final int expectedVersion;
  final String resultId;
  final String content;
  final List<TechnicianResultPhoto> photos;

  String storagePath(String userId, TechnicianResultPhoto photo) =>
      'technician-results/$userId/$requestId/$expectedVersion/$resultId/${photo.id}.${photo.extension}';
}

class TechnicianWriteReceipt {
  const TechnicianWriteReceipt({
    required this.requestId,
    required this.status,
    required this.version,
    this.resultId,
    this.replayed = false,
  });

  factory TechnicianWriteReceipt.fromJson(Map<String, dynamic> json) {
    final requestId = json['request_id'];
    final status = json['status'];
    final version = json['version'];
    final resultId = json['result_id'];
    final replayed = json['replayed'] ?? false;
    if (requestId is! String ||
        !isTechnicianWorkflowId(requestId) ||
        version is! int ||
        version <= 0 ||
        replayed is! bool ||
        (resultId != null &&
            (resultId is! String || !isTechnicianWorkflowId(resultId)))) {
      throw const FormatException('Invalid technician write receipt.');
    }
    final parsedStatus = switch (status) {
      'in_progress' => RepairStatus.inProgress,
      'awaiting_confirmation' => RepairStatus.awaitingConfirmation,
      _ => throw const FormatException('Invalid write receipt status.'),
    };
    return TechnicianWriteReceipt(
      requestId: requestId,
      status: parsedStatus,
      version: version,
      resultId: resultId as String?,
      replayed: replayed,
    );
  }

  final String requestId;
  final RepairStatus status;
  final int version;
  final String? resultId;
  final bool replayed;
}

bool isTechnicianWorkflowId(String value) => _uuid.hasMatch(value);
final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String newTechnicianWorkflowId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

bool _prefix(List<int> bytes, List<int> prefix) {
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}
