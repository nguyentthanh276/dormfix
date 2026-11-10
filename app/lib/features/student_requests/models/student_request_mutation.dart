import 'dart:typed_data';

import 'new_repair_request.dart';

enum StudentRequestMutationKind { edit, cancel, reopen }

/// One versioned write. Retain this draft and its UUID for uncertain retries.
final class StudentRequestMutation {
  factory StudentRequestMutation.edit({
    required String actionId,
    required String requestId,
    required int expectedVersion,
    required String title,
    required String categoryId,
    required String description,
    List<String> keepAttachmentIds = const [],
    List<AttachmentDraft> attachments = const [],
  }) => StudentRequestMutation._(
    actionId: actionId,
    requestId: requestId,
    expectedVersion: expectedVersion,
    kind: StudentRequestMutationKind.edit,
    title: title.trim(),
    categoryId: categoryId,
    description: description.trim(),
    keepAttachmentIds: List.unmodifiable(keepAttachmentIds.toList()..sort()),
    attachments: _freezePhotos(attachments),
  );

  factory StudentRequestMutation.cancel({
    required String actionId,
    required String requestId,
    required int expectedVersion,
    required String reason,
  }) => StudentRequestMutation._(
    actionId: actionId,
    requestId: requestId,
    expectedVersion: expectedVersion,
    kind: StudentRequestMutationKind.cancel,
    reason: reason.trim(),
  );

  factory StudentRequestMutation.reopen({
    required String actionId,
    required String requestId,
    required int expectedVersion,
    required String reason,
    List<AttachmentDraft> attachments = const [],
  }) => StudentRequestMutation._(
    actionId: actionId,
    requestId: requestId,
    expectedVersion: expectedVersion,
    kind: StudentRequestMutationKind.reopen,
    reason: reason.trim(),
    attachments: _freezePhotos(attachments),
  );

  const StudentRequestMutation._({
    required this.actionId,
    required this.requestId,
    required this.expectedVersion,
    required this.kind,
    this.title,
    this.categoryId,
    this.description,
    this.reason,
    this.keepAttachmentIds = const [],
    this.attachments = const [],
  });

  final String actionId;
  final String requestId;
  final int expectedVersion;
  final StudentRequestMutationKind kind;
  final String? title;
  final String? categoryId;
  final String? description;
  final String? reason;
  final List<String> keepAttachmentIds;
  final List<AttachmentDraft> attachments;

  static List<AttachmentDraft> _freezePhotos(List<AttachmentDraft> photos) =>
      List.unmodifiable(
        photos.map(
          (photo) => AttachmentDraft(
            name: photo.name,
            bytes: Uint8List.fromList(photo.bytes).asUnmodifiableView(),
          ),
        ),
      );
}
