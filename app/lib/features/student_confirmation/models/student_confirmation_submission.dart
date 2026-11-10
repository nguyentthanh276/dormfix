import 'dart:typed_data';

import '../../../core/models/repair_status.dart';
import '../../student_requests/models/new_repair_request.dart';

enum StudentResultAction { confirmFixed, requestRework }

/// One frozen, in-memory action. Retain this object and its UUID for retries.
class StudentConfirmationSubmission {
  factory StudentConfirmationSubmission({
    required String actionId,
    required String requestId,
    required int expectedVersion,
    required StudentResultAction action,
    String? note,
    List<AttachmentDraft> attachments = const [],
  }) {
    final normalizedNote = note?.trim();
    return StudentConfirmationSubmission._(
      actionId: actionId,
      requestId: requestId,
      expectedVersion: expectedVersion,
      action: action,
      note: normalizedNote == null || normalizedNote.isEmpty
          ? null
          : normalizedNote,
      attachments: List.unmodifiable(
        attachments.map(
          (photo) => AttachmentDraft(
            name: photo.name,
            bytes: Uint8List.fromList(photo.bytes).asUnmodifiableView(),
          ),
        ),
      ),
    );
  }

  const StudentConfirmationSubmission._({
    required this.actionId,
    required this.requestId,
    required this.expectedVersion,
    required this.action,
    required this.note,
    required this.attachments,
  });

  final String actionId;
  final String requestId;
  final int expectedVersion;
  final StudentResultAction action;
  final String? note;
  final List<AttachmentDraft> attachments;
}

/// A validated receipt for this action, including idempotent server replays.
class StudentConfirmationReceipt {
  const StudentConfirmationReceipt({
    required this.requestId,
    required this.actionId,
    required this.status,
    required this.version,
    required this.replayed,
    this.feedbackId,
  });

  final String requestId;
  final String actionId;
  final RepairStatus status;
  final int version;
  final String? feedbackId;
  final bool replayed;
}
