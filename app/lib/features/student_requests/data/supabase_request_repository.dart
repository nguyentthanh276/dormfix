import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/repair_status.dart';
import '../../student_confirmation/models/student_confirmation_submission.dart';
import '../models/edit_repair_request.dart';
import '../models/history_entry.dart';
import '../models/incident_category.dart';
import '../models/new_repair_request.dart';
import '../models/repair_request.dart';
import '../models/request_detail.dart';
import '../models/request_rules.dart';
import '../models/student_request_id.dart';
import '../models/student_request_mutation.dart';
import 'request_repository.dart';

/// Real student request adapter. Ownership and writes are authorized by RPCs;
/// private image bytes are downloaded with the current user's JWT.
class SupabaseRequestRepository extends RequestRepository {
  SupabaseRequestRepository(this._client);

  final SupabaseClient _client;
  final _preparedByRequest = Expando<_PreparedCreate>();
  final Map<String, WeakReference<_PreparedCreate>> _attempts = {};
  final Map<String, Future<RepairRequest>> _activeCreates = {};
  final _preparedByAction = Expando<_PreparedVersionedAction>();
  final Map<String, WeakReference<_PreparedVersionedAction>> _actionAttempts =
      {};
  final Map<String, Future<StudentConfirmationReceipt>> _activeActions = {};
  static const _bucket = 'repair-images';

  @override
  bool get supportsEditing => true;
  @override
  bool get supportsCancellation => true;
  @override
  bool get supportsConfirmationActions => true;
  @override
  bool get supportsVersionedMutations => true;
  @override
  bool get supportsReopening => true;
  @override
  bool get allowsDemoFallback => false;

  @override
  Stream<void> get accessChanges {
    final identity = _client.auth.currentSession?.user.id;
    return _client.auth.onAuthStateChange
        .where((event) => event.session?.user.id != identity)
        .map<void>((_) {});
  }

  @override
  Future<List<IncidentCategory>> fetchCategories() => _run((session) async {
    final rows = _array(await _client.rpc('student_list_categories'));
    session.check();
    return List.unmodifiable(
      rows.map((row) {
        final json = _object(row);
        return IncidentCategory(id: _id(json, 'id'), name: _text(json, 'name'));
      }),
    );
  }, 'Không thể tải loại sự cố. Vui lòng thử lại.');

  @override
  Future<List<RepairRequest>> fetchMyRequests() => _run((session) async {
    final rows = _array(await _client.rpc('student_list_requests'));
    session.check();
    return List.unmodifiable(
      rows.map((row) => _summary(_object(row), session.userId)),
    );
  }, 'Không thể tải yêu cầu. Vui lòng thử lại.');

  @override
  Future<RequestDetail> fetchRequestDetail(String requestId) => _run(
    (session) => _loadDetail(session, requestId),
    'Không thể tải chi tiết yêu cầu. Vui lòng thử lại.',
  );

  Future<RequestDetail> _loadDetail(
    _StudentSession session,
    String requestId,
  ) async {
    if (!isStudentRequestId(requestId)) throw _accessFailure;
    session.check();
    final json = _object(
      await _client.rpc(
        'student_get_request',
        params: {'p_request_id': requestId},
      ),
    );
    session.check();
    final requestJson = _object(json['request']);
    final request = _summary(requestJson, session.userId);
    if (request.id != requestId) throw _accessFailure;
    final technician = json['technician'] == null
        ? null
        : _object(json['technician']);
    final attachments = _array(json['attachments'])
        .map((value) {
          final attachment = _object(value);
          final path = _text(attachment, 'storage_path');
          final mime = _text(attachment, 'mime_type');
          final size = attachment['size_bytes'];
          final result = _nullableId(attachment, 'result_id');
          final feedback = _nullableId(attachment, 'feedback_id');
          if (path.startsWith('/') ||
              path.contains('://') ||
              path.split('/').contains('..') ||
              !_mimeTypes.contains(mime) ||
              size is! int ||
              size <= 0 ||
              size > RequestRules.maxImageBytes ||
              (result != null && feedback != null)) {
            throw const FormatException('Invalid attachment metadata.');
          }
          return RequestAttachment(
            id: _id(attachment, 'id'),
            storagePath: path,
            mimeType: mime,
            sizeBytes: size,
            resultId: result,
            feedbackId: feedback,
          );
        })
        .toList(growable: false);
    if (attachments.map((a) => a.id).toSet().length != attachments.length ||
        attachments.map((a) => a.storagePath).toSet().length !=
            attachments.length) {
      throw const FormatException('Duplicate attachments.');
    }
    final results = _array(json['results'])
        .map((value) {
          final result = _object(value);
          final id = _id(result, 'id');
          return RepairResultItem(
            id: id,
            technicianName: _text(result, 'technician_name'),
            content: _text(result, 'content'),
            submittedAt: _timestamp(result, 'submitted_at'),
            photos: List.unmodifiable(
              attachments
                  .where((a) => a.resultId == id)
                  .map((a) => a.storagePath),
            ),
          );
        })
        .toList(growable: false);
    final feedback = _array(json['feedback'])
        .map((value) {
          final row = _object(value);
          final id = _id(row, 'id');
          final kind = _text(row, 'kind');
          if (kind != 'rework' && kind != 'reopen') {
            throw const FormatException('Invalid feedback kind.');
          }
          return RequestFeedbackItem(
            id: id,
            kind: kind,
            reason: _text(row, 'reason'),
            createdAt: _timestamp(row, 'created_at'),
            authorName: _text(row, 'author_name'),
            photos: List.unmodifiable(
              attachments
                  .where((a) => a.feedbackId == id)
                  .map((a) => a.storagePath),
            ),
          );
        })
        .toList(growable: false);
    final resultIds = results.map((r) => r.id).toSet();
    final feedbackIds = feedback.map((f) => f.id).toSet();
    if (attachments.any(
      (a) =>
          (a.resultId != null && !resultIds.contains(a.resultId)) ||
          (a.feedbackId != null && !feedbackIds.contains(a.feedbackId)),
    )) {
      throw const FormatException('Unlinked attachments.');
    }
    final history = _array(json['history'])
        .map((value) {
          final row = _object(value);
          final note = row['note'];
          if (note != null && note is! String) {
            throw const FormatException('Invalid history note.');
          }
          return HistoryEntry(
            status: _status(
              row['new_status'] ??
                  row['old_status'] ??
                  request.status.databaseValue,
            ),
            note: note as String? ?? _actionLabel(_text(row, 'action')),
            createdAt: _timestamp(row, 'occurred_at'),
            actorId: _id(row, 'actor_id'),
            actorName: _text(row, 'actor_name'),
          );
        })
        .toList(growable: false);
    return RequestDetail(
      request: request,
      description: _text(requestJson, 'description'),
      technicianName: technician == null
          ? null
          : _text(technician, 'full_name'),
      technicianPhone: technician == null
          ? null
          : _nullableText(technician, 'phone'),
      studentPhotos: List.unmodifiable(
        attachments
            .where((a) => a.resultId == null && a.feedbackId == null)
            .map((a) => a.storagePath),
      ),
      results: List.unmodifiable(results),
      feedback: List.unmodifiable(feedback),
      attachments: List.unmodifiable(attachments),
      history: List.unmodifiable(history),
      categoryId: _nullableId(requestJson, 'category_id'),
      canEdit:
          request.status == RepairStatus.pending && json['can_edit'] == true,
      canCancel:
          (request.status == RepairStatus.pending ||
              request.status == RepairStatus.assigned) &&
          json['can_cancel'] == true,
      canReopen:
          request.status == RepairStatus.completed &&
          json['can_reopen'] == true,
    );
  }

  @override
  Future<Uint8List> fetchAttachment(
    String requestId,
    RequestAttachment attachment,
  ) => _run((session) async {
    final detail = await _loadDetail(session, requestId);
    if (!detail.attachments.any((a) => _sameAttachment(a, attachment))) {
      throw _accessFailure;
    }
    session.check();
    final bytes = await _client.storage
        .from(_bucket)
        .download(attachment.storagePath);
    session.check();
    if (bytes.length != attachment.sizeBytes ||
        _imageType(bytes)?.mime != attachment.mimeType) {
      throw const FormatException('Invalid private image.');
    }
    return Uint8List.fromList(bytes).asUnmodifiableView();
  }, 'Không thể tải ảnh. Vui lòng thử lại.');

  @override
  Future<RepairRequest> createRequest(NewRepairRequest request) async {
    final identity = _sessionUser(_client);
    final prepared = _prepare(request, identity);
    final active = _activeCreates[prepared.requestId];
    if (active != null) return active;
    final pending = _run(
      (session) => _create(session, prepared),
      'Không thể tạo yêu cầu. Vui lòng thử lại.',
    );
    _activeCreates[prepared.requestId] = pending;
    try {
      return await pending;
    } finally {
      if (identical(_activeCreates[prepared.requestId], pending)) {
        _activeCreates.remove(prepared.requestId);
      }
    }
  }

  _PreparedCreate _prepare(NewRepairRequest request, String userId) {
    var prepared = _preparedByRequest[request];
    final requestId =
        request.requestId ?? prepared?.requestId ?? createStudentRequestId();
    if (!isStudentRequestId(requestId)) {
      throw const RequestFailure('Thông tin yêu cầu không hợp lệ.');
    }
    _attempts.removeWhere((_, value) => value.target == null);
    prepared ??= _attempts[requestId]?.target;
    if (prepared != null) {
      if (prepared.userId != userId) throw _accessFailure;
      if (!prepared.matches(request)) {
        throw RequestFailure(
          'Nội dung gửi lại đã thay đổi. Vui lòng kiểm tra yêu cầu trong danh sách.',
          uncertain: prepared.uncertain,
        );
      }
      _preparedByRequest[request] = prepared;
      return prepared;
    }
    if (request.title.trim().isEmpty ||
        request.description.trim().isEmpty ||
        !isStudentRequestId(request.categoryId)) {
      throw const RequestFailure(
        'Vui lòng nhập tiêu đề, loại sự cố và mô tả hợp lệ.',
      );
    }
    if (request.attachments.length > RequestRules.maxImages) {
      throw const RequestFailure('Chỉ được đính kèm tối đa 5 ảnh.');
    }
    final photos = request.attachments
        .map((draft) {
          final type = _imageType(draft.bytes);
          if (draft.bytes.isEmpty ||
              draft.bytes.length > RequestRules.maxImageBytes ||
              type == null) {
            throw const RequestFailure(
              'Chỉ nhận ảnh JPG, PNG hoặc WebP hợp lệ, mỗi ảnh tối đa 5 MB.',
            );
          }
          return _PreparedPhoto(
            id: createStudentRequestId(),
            name: draft.name,
            bytes: Uint8List.fromList(draft.bytes).asUnmodifiableView(),
            mime: type.mime,
            extension: type.extension,
          );
        })
        .toList(growable: false);
    prepared = _PreparedCreate(
      requestId: requestId,
      userId: userId,
      title: request.title.trim(),
      categoryId: request.categoryId,
      description: request.description.trim(),
      photos: List.unmodifiable(photos),
    );
    _preparedByRequest[request] = prepared;
    _attempts[requestId] = WeakReference(prepared);
    return prepared;
  }

  Future<RepairRequest> _create(
    _StudentSession session,
    _PreparedCreate prepared,
  ) async {
    if (session.userId != prepared.userId) throw _accessFailure;
    final paths = prepared.photos
        .map((p) => prepared.path(p))
        .toList(growable: false);
    var finalizeSent = false;
    Future<RepairRequest> finalize() async {
      session.check();
      finalizeSent = true;
      final data = await _client.rpc(
        'student_create_request',
        params: {
          'p_request_id': prepared.requestId,
          'p_title': prepared.title,
          'p_category_id': prepared.categoryId,
          'p_description': prepared.description,
          'p_photos': prepared.photos
              .map(
                (p) => {
                  'id': p.id,
                  'storage_path': prepared.path(p),
                  'mime_type': p.mime,
                  'size_bytes': p.bytes.length,
                },
              )
              .toList(growable: false),
        },
      );
      session.check();
      final result = _summary(_object(data), session.userId);
      if (result.id != prepared.requestId) {
        throw const FormatException('Wrong creation receipt.');
      }
      prepared.uncertain = false;
      return result;
    }

    try {
      if (prepared.uncertain) {
        try {
          return await finalize();
        } on PostgrestException catch (error) {
          if (error.code != '22023' ||
              error.message != 'INVALID_REQUEST_PHOTOS') {
            rethrow;
          }
          // The atomic RPC found no committed request and missing staging data.
          // Keep identical IDs/bytes and restore staging before the same replay.
          session.check();
          prepared.uncertain = false;
          finalizeSent = false;
        }
      }
      for (final photo in prepared.photos) {
        await _stagePhoto(session, prepared.path(photo), photo);
        session.check();
      }
      return await finalize();
    } catch (error) {
      final uncertain =
          prepared.uncertain || (finalizeSent && !_definiteRejection(error));
      prepared.uncertain = uncertain;
      if (!session.isCurrent) throw _accessFailure;
      final failure = _safeFailure(
        error,
        'Không thể tạo yêu cầu. Vui lòng thử lại.',
        uncertain: uncertain,
      );
      // Only definitive failures can discard staging. Unknown RPC outcomes may
      // already have committed, so retry finalization before touching Storage.
      if (!uncertain && !failure.accessDenied && paths.isNotEmpty) {
        try {
          session.check();
          await _client.storage.from(_bucket).remove(paths);
          session.check();
        } catch (_) {
          // RLS additionally prevents deleting any finalized attachment.
        }
      }
      throw failure;
    }
  }

  Future<void> _stagePhoto(
    _StudentSession session,
    String path,
    _PreparedPhoto photo,
  ) async {
    session.check();
    if (await _existingPhoto(session, path, photo)) return;
    session.check();
    try {
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            photo.bytes,
            fileOptions: FileOptions(
              contentType: photo.mime,
              cacheControl: '0',
              upsert: false,
            ),
            retryAttempts: 0,
          );
      session.check();
    } on StorageException catch (error) {
      session.check();
      if (!_duplicate(error) || !await _existingPhoto(session, path, photo)) {
        rethrow;
      }
    }
  }

  Future<bool> _existingPhoto(
    _StudentSession session,
    String path,
    _PreparedPhoto photo,
  ) async {
    try {
      final object = await _client.storage.from(_bucket).info(path);
      session.check();
      if (object.bucketId != _bucket ||
          object.name != path ||
          (object.size ?? object.metadata?['size']) != photo.bytes.length ||
          (object.contentType ?? object.metadata?['mimetype']) != photo.mime) {
        throw const RequestFailure(
          'Ảnh đã tải lên không khớp. Vui lòng kiểm tra lại.',
        );
      }
      return true;
    } on StorageException catch (error) {
      session.check();
      if (_missing(error)) return false;
      rethrow;
    }
  }

  @override
  Future<StudentConfirmationReceipt> submitConfirmation(
    StudentConfirmationSubmission submission,
  ) async {
    final rework = submission.action == StudentResultAction.requestRework;
    if (rework && submission.note == null) {
      throw const RequestFailure('Vui lòng nhập lý do yêu cầu xử lý lại.');
    }
    if (!rework && submission.attachments.isNotEmpty) {
      throw const RequestFailure(
        'Xác nhận đã sửa xong không nhận ảnh đính kèm.',
      );
    }
    return _runVersionedAction(
      draft: submission,
      requestId: submission.requestId,
      actionId: submission.actionId,
      expectedVersion: submission.expectedVersion,
      status: rework ? RepairStatus.awaitingRework : RepairStatus.completed,
      feedbackId: rework ? submission.actionId : null,
      rpc: rework ? 'student_request_rework' : 'student_confirm_result',
      fields: {rework ? 'p_reason' : 'p_note': submission.note},
      attachments: submission.attachments,
      photoFolder: rework ? 'student-feedback' : null,
      invalidPhotos: 'INVALID_FEEDBACK_PHOTOS',
    );
  }

  @override
  Future<StudentConfirmationReceipt> submitMutation(
    StudentRequestMutation mutation,
  ) async {
    final kind = mutation.kind;
    final edit = kind == StudentRequestMutationKind.edit;
    final reopen = kind == StudentRequestMutationKind.reopen;
    final keep = mutation.keepAttachmentIds;
    if (edit) {
      if (mutation.title!.isEmpty ||
          mutation.description!.isEmpty ||
          !isStudentRequestId(mutation.categoryId!)) {
        throw const RequestFailure(
          'Vui lòng nhập tiêu đề, loại sự cố và mô tả hợp lệ.',
        );
      }
      if (keep.toSet().length != keep.length ||
          !keep.every(isStudentRequestId)) {
        throw const RequestFailure('Danh sách ảnh giữ lại không hợp lệ.');
      }
    } else if (mutation.reason!.isEmpty) {
      throw const RequestFailure('Vui lòng nhập lý do.');
    }
    if (keep.length + mutation.attachments.length > RequestRules.maxImages) {
      throw const RequestFailure('Chỉ được đính kèm tối đa 5 ảnh.');
    }
    return _runVersionedAction(
      draft: mutation,
      requestId: mutation.requestId,
      actionId: mutation.actionId,
      expectedVersion: mutation.expectedVersion,
      status: kind == StudentRequestMutationKind.cancel
          ? RepairStatus.cancelled
          : RepairStatus.pending,
      feedbackId: reopen ? mutation.actionId : null,
      rpc: switch (kind) {
        StudentRequestMutationKind.edit => 'student_edit_request',
        StudentRequestMutationKind.cancel => 'student_cancel_request',
        StudentRequestMutationKind.reopen => 'student_reopen_request',
      },
      fields: edit
          ? {
              'p_title': mutation.title,
              'p_category_id': mutation.categoryId,
              'p_description': mutation.description,
              'p_keep_attachment_ids': keep,
            }
          : {'p_reason': mutation.reason},
      attachments: mutation.attachments,
      photoFolder: edit
          ? 'student-request-edits'
          : (reopen ? 'student-feedback' : null),
      invalidPhotos: edit
          ? 'INVALID_REQUEST_PHOTOS'
          : 'INVALID_FEEDBACK_PHOTOS',
    );
  }

  Future<StudentConfirmationReceipt> _runVersionedAction({
    required Object draft,
    required String requestId,
    required String actionId,
    required int expectedVersion,
    required RepairStatus status,
    required String? feedbackId,
    required String rpc,
    required Map<String, Object?> fields,
    required List<AttachmentDraft> attachments,
    required String? photoFolder,
    required String invalidPhotos,
  }) async {
    final userId = _sessionUser(_client);
    if (!isStudentRequestId(actionId) ||
        !isStudentRequestId(requestId) ||
        expectedVersion < 1 ||
        expectedVersion >= 2147483647) {
      throw const RequestFailure('Thông tin yêu cầu không hợp lệ.');
    }
    if (attachments.length > RequestRules.maxImages) {
      throw const RequestFailure('Chỉ được đính kèm tối đa 5 ảnh.');
    }
    final params = {
      'p_request_id': requestId,
      'p_expected_version': expectedVersion,
      'p_action_id': actionId,
      ...fields,
    };
    _actionAttempts.removeWhere((_, value) => value.target == null);
    var prepared =
        _preparedByAction[draft] ?? _actionAttempts[actionId]?.target;
    if (prepared != null) {
      if (prepared.userId != userId) throw _accessFailure;
      if (!prepared.matches(rpc, params, attachments)) {
        throw RequestFailure(
          'Nội dung gửi lại đã thay đổi. Vui lòng tải lại chi tiết yêu cầu.',
          uncertain: prepared.uncertain,
          conflict: true,
        );
      }
    } else {
      final photos = attachments
          .map((photo) {
            final type = _imageType(photo.bytes);
            if (photo.bytes.isEmpty ||
                photo.bytes.length > RequestRules.maxImageBytes ||
                type == null) {
              throw const RequestFailure(
                'Chỉ nhận ảnh JPG, PNG hoặc WebP hợp lệ, mỗi ảnh tối đa 5 MB.',
              );
            }
            return _PreparedPhoto(
              id: createStudentRequestId(),
              name: photo.name,
              bytes: photo.bytes,
              mime: type.mime,
              extension: type.extension,
            );
          })
          .toList(growable: false);
      prepared = _PreparedVersionedAction(
        userId: userId,
        rpc: rpc,
        params: params,
        status: status,
        feedbackId: feedbackId,
        photos: photos,
        photoPrefix: photoFolder == null
            ? null
            : '$photoFolder/$userId/$requestId/$expectedVersion/$actionId',
        invalidPhotos: invalidPhotos,
      );
      _actionAttempts[actionId] = WeakReference(prepared);
    }
    _preparedByAction[draft] = prepared;
    final active = _activeActions[actionId];
    if (active != null) return active;
    final attempt = prepared;
    final pending = _run(
      (session) => _sendVersionedAction(session, attempt),
      'Không thể gửi thao tác. Vui lòng thử lại.',
    );
    _activeActions[actionId] = pending;
    try {
      return await pending;
    } finally {
      if (identical(_activeActions[actionId], pending)) {
        _activeActions.remove(actionId);
      }
    }
  }

  Future<StudentConfirmationReceipt> _sendVersionedAction(
    _StudentSession session,
    _PreparedVersionedAction prepared,
  ) async {
    if (session.userId != prepared.userId) throw _accessFailure;
    final paths = prepared.photos.map(prepared.path).toList(growable: false);
    var finalizeSent = false;
    Future<StudentConfirmationReceipt> finalize() async {
      session.check();
      finalizeSent = true;
      final data = await _client.rpc(
        prepared.rpc,
        params: {
          ...prepared.params,
          if (prepared.photoPrefix != null)
            'p_photos': prepared.photos
                .map(
                  (photo) => {
                    'id': photo.id,
                    'storage_path': prepared.path(photo),
                    'mime_type': photo.mime,
                    'size_bytes': photo.bytes.length,
                  },
                )
                .toList(growable: false),
        },
      );
      session.check();
      final receipt = _versionedReceipt(_object(data), prepared);
      prepared.uncertain = false;
      prepared.committed = true;
      return receipt;
    }

    try {
      if (prepared.uncertain || prepared.committed) {
        try {
          return await finalize();
        } on PostgrestException catch (error) {
          if (prepared.committed ||
              paths.isEmpty ||
              error.code != '22023' ||
              error.message != prepared.invalidPhotos) {
            rethrow;
          }
          // Server ruled out a committed action before checking staging.
          session.check();
          prepared.uncertain = false;
          finalizeSent = false;
        }
      }
      for (final photo in prepared.photos) {
        await _stagePhoto(session, prepared.path(photo), photo);
        session.check();
      }
      return await finalize();
    } catch (error) {
      final uncertain =
          prepared.uncertain || (finalizeSent && !_definiteRejection(error));
      prepared.uncertain = uncertain;
      if (!session.isCurrent) throw _accessFailure;
      final failure = _safeFailure(
        error,
        'Không thể gửi thao tác. Vui lòng thử lại.',
        uncertain: uncertain,
      );
      if (!uncertain &&
          !prepared.committed &&
          !failure.accessDenied &&
          paths.isNotEmpty) {
        try {
          session.check();
          await _client.storage.from(_bucket).remove(paths);
          session.check();
        } catch (_) {
          // Server policies reject deletion once the action has committed.
        }
      }
      throw failure;
    }
  }

  @override
  Future<void> updateRequest(EditRepairRequest request) async =>
      throw const RequestFailure(
        'Vui lòng mở lại yêu cầu trước khi chỉnh sửa.',
      );

  @override
  Future<void> cancelRequest({
    required String requestId,
    required String reason,
  }) async =>
      throw const RequestFailure('Vui lòng mở lại yêu cầu trước khi hủy.');

  Future<T> _run<T>(
    Future<T> Function(_StudentSession session) operation,
    String message,
  ) async {
    _StudentSession? session;
    try {
      session = _StudentSession(_client);
      final result = await operation(session);
      session.check();
      return result;
    } catch (error) {
      if (session != null && !session.isCurrent) throw _accessFailure;
      throw _safeFailure(error, message);
    } finally {
      await session?.dispose();
    }
  }
}

class _StudentSession {
  _StudentSession(this.client) : userId = _sessionUser(client) {
    subscription = client.auth.onAuthStateChange.listen((state) {
      if (state.session?.user.id != userId) changed = true;
    }, onError: (Object _) => changed = true);
  }
  final SupabaseClient client;
  final String userId;
  bool changed = false;
  late final StreamSubscription<AuthState> subscription;
  void check() {
    if (changed || _sessionUser(client) != userId) throw _accessFailure;
  }

  bool get isCurrent {
    try {
      check();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() => subscription.cancel();
}

class _PreparedCreate {
  _PreparedCreate({
    required this.requestId,
    required this.userId,
    required this.title,
    required this.categoryId,
    required this.description,
    required this.photos,
  });
  final String requestId, userId, title, categoryId, description;
  final List<_PreparedPhoto> photos;
  bool uncertain = false;
  String path(_PreparedPhoto photo) =>
      'student-requests/$userId/$requestId/${photo.id}.${photo.extension}';
  bool matches(NewRepairRequest request) {
    if (request.title.trim() != title ||
        request.categoryId != categoryId ||
        request.description.trim() != description ||
        request.attachments.length != photos.length) {
      return false;
    }
    for (var i = 0; i < photos.length; i++) {
      if (request.attachments[i].name != photos[i].name ||
          !_sameBytes(request.attachments[i].bytes, photos[i].bytes)) {
        return false;
      }
    }
    return true;
  }
}

class _PreparedPhoto {
  const _PreparedPhoto({
    required this.id,
    required this.name,
    required this.bytes,
    required this.mime,
    required this.extension,
  });
  final String id, name, mime, extension;
  final Uint8List bytes;
}

class _PreparedVersionedAction {
  _PreparedVersionedAction({
    required this.userId,
    required this.rpc,
    required this.params,
    required this.status,
    required this.feedbackId,
    required this.photos,
    required this.photoPrefix,
    required this.invalidPhotos,
  }) : payload = jsonEncode(params);

  final String userId;
  final String rpc;
  final Map<String, Object?> params;
  final String payload;
  final RepairStatus status;
  final String? feedbackId;
  final List<_PreparedPhoto> photos;
  final String? photoPrefix;
  final String invalidPhotos;
  bool uncertain = false;
  bool committed = false;

  String path(_PreparedPhoto photo) =>
      '$photoPrefix/${photo.id}.${photo.extension}';

  bool matches(
    String candidateRpc,
    Map<String, Object?> candidateParams,
    List<AttachmentDraft> attachments,
  ) {
    if (candidateRpc != rpc ||
        jsonEncode(candidateParams) != payload ||
        attachments.length != photos.length) {
      return false;
    }
    for (var i = 0; i < photos.length; i++) {
      if (attachments[i].name != photos[i].name ||
          !_sameBytes(attachments[i].bytes, photos[i].bytes)) {
        return false;
      }
    }
    return true;
  }
}

StudentConfirmationReceipt _versionedReceipt(
  Map<String, dynamic> json,
  _PreparedVersionedAction action,
) {
  final requestId = _id(json, 'request_id');
  final actionId = _id(json, 'action_id');
  final feedbackId = _nullableId(json, 'feedback_id');
  final version = json['version'];
  final replayed = json['replayed'];
  if (requestId != action.params['p_request_id'] ||
      actionId != action.params['p_action_id'] ||
      json['status'] != action.status.databaseValue ||
      version is! int ||
      version != (action.params['p_expected_version'] as int) + 1 ||
      !json.containsKey('feedback_id') ||
      feedbackId != action.feedbackId ||
      replayed is! bool) {
    throw const FormatException('Invalid request action receipt.');
  }
  return StudentConfirmationReceipt(
    requestId: requestId,
    actionId: actionId,
    status: action.status,
    version: version,
    feedbackId: feedbackId,
    replayed: replayed,
  );
}

const _accessFailure = RequestFailure(
  'Bạn không còn quyền truy cập yêu cầu này. Vui lòng đăng nhập lại.',
  accessDenied: true,
);
const _accessCodes = {
  '28000',
  '42501',
  'P0002',
  'PGRST301',
  'PGRST302',
  'PGRST303',
  '401',
  '403',
  'invalid_jwt',
  'session_not_found',
  'session_expired',
};
const _mimeTypes = {'image/jpeg', 'image/png', 'image/webp'};

String _sessionUser(SupabaseClient client) {
  final session = client.auth.currentSession;
  if (session == null ||
      session.accessToken.isEmpty ||
      session.isExpired ||
      !isStudentRequestId(session.user.id)) {
    throw _accessFailure;
  }
  return session.user.id;
}

RequestFailure _safeFailure(
  Object error,
  String message, {
  bool uncertain = false,
}) {
  if (error is RequestFailure) {
    return RequestFailure(
      error.message,
      accessDenied: error.accessDenied,
      uncertain: uncertain || error.uncertain,
      conflict: error.conflict,
    );
  }
  if ((error is PostgrestException && _accessCodes.contains(error.code)) ||
      (error is StorageException && _accessCodes.contains(error.statusCode)) ||
      error is AuthException) {
    return _accessFailure;
  }
  if (error is PostgrestException) {
    if (error.code == 'P0001' &&
        const {
          'REQUEST_STATE_CONFLICT',
          'CONFIRMATION_NOT_READY',
          'ACTION_REPLAY_MISMATCH',
          'REQUEST_ASSIGNMENT_CONFLICT',
          'REOPEN_ROOM_MISMATCH',
        }.contains(error.message)) {
      return RequestFailure(
        error.message == 'REOPEN_ROOM_MISMATCH'
            ? 'Chỉ có thể mở lại yêu cầu của phòng hiện tại còn hoạt động.'
            : 'Yêu cầu đã thay đổi hoặc chưa đủ điều kiện. Vui lòng tải lại chi tiết.',
        uncertain: uncertain,
        conflict: true,
      );
    }
    if (error.code == '22023') {
      return RequestFailure(switch (error.message) {
        'ACTIVE_STUDENT_ROOM_REQUIRED' =>
          'Phòng hiện tại không còn hoạt động. Vui lòng liên hệ Admin.',
        'ACTIVE_CATEGORY_REQUIRED' =>
          'Loại sự cố không còn sử dụng. Vui lòng chọn loại khác.',
        'REWORK_REASON_REQUIRED' => 'Vui lòng nhập lý do yêu cầu xử lý lại.',
        'CANCELLATION_REASON_REQUIRED' => 'Vui lòng nhập lý do hủy yêu cầu.',
        'REOPEN_REASON_REQUIRED' => 'Vui lòng nhập lý do mở lại yêu cầu.',
        _ => 'Thông tin hoặc ảnh yêu cầu không hợp lệ. Vui lòng kiểm tra lại.',
      }, uncertain: uncertain);
    }
    if (error.code == 'P0001' || error.code == '23505') {
      return RequestFailure(
        'Nội dung gửi lại không khớp. Vui lòng kiểm tra yêu cầu trong danh sách.',
        uncertain: uncertain,
      );
    }
    if (error.code == 'PGRST202') {
      return RequestFailure(
        'Chức năng yêu cầu sửa chữa chưa sẵn sàng. Vui lòng liên hệ Admin.',
        uncertain: uncertain,
      );
    }
  }
  return RequestFailure(
    uncertain
        ? 'Chưa xác định được kết quả gửi. Hãy kiểm tra lại hoặc thử lại cùng yêu cầu.'
        : message,
    uncertain: uncertain,
  );
}

bool _definiteRejection(Object error) =>
    error is PostgrestException &&
    ({
      '22023',
      'P0001',
      '23505',
      'PGRST202',
      ..._accessCodes,
    }.contains(error.code));
bool _missing(StorageException error) =>
    error.statusCode == '404' ||
    (error.statusCode == '400' &&
        (error.error == 'not_found' || error.message == 'Object not found'));
bool _duplicate(StorageException error) =>
    error.statusCode == '409' ||
    (error.statusCode == '400' && error.error == 'Duplicate');
bool _sameAttachment(RequestAttachment a, RequestAttachment b) =>
    a.id == b.id &&
    a.storagePath == b.storagePath &&
    a.mimeType == b.mimeType &&
    a.sizeBytes == b.sizeBytes &&
    a.resultId == b.resultId &&
    a.feedbackId == b.feedbackId;
bool _sameBytes(List<int> a, List<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

({String mime, String extension})? _imageType(List<int> bytes) {
  bool starts(List<int> pattern, [int offset = 0]) =>
      bytes.length >= pattern.length + offset &&
      List.generate(
        pattern.length,
        (i) => bytes[i + offset] == pattern[i],
      ).every((same) => same);
  if (starts([255, 216, 255])) return (mime: 'image/jpeg', extension: 'jpg');
  if (starts([137, 80, 78, 71, 13, 10, 26, 10])) {
    return (mime: 'image/png', extension: 'png');
  }
  if (starts([82, 73, 70, 70]) && starts([87, 69, 66, 80], 8)) {
    return (mime: 'image/webp', extension: 'webp');
  }
  return null;
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected object.');
  }
  return Map<String, dynamic>.from(value);
}

List<dynamic> _array(Object? value) {
  if (value is! List) throw const FormatException('Expected list.');
  return value;
}

String _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Expected text.');
  }
  return value;
}

String? _nullableText(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _text(json, key);
String _id(Map<String, dynamic> json, String key) {
  final value = _text(json, key);
  if (!isStudentRequestId(value)) throw const FormatException('Expected UUID.');
  return value;
}

String? _nullableId(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _id(json, key);
DateTime _timestamp(Map<String, dynamic> json, String key) {
  final value = _text(json, key);
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const FormatException('Expected zoned timestamp.');
  }
  return DateTime.parse(value).toUtc();
}

RepairStatus _status(Object? value) => RepairStatus.values.firstWhere(
  (status) => status.databaseValue == value,
  orElse: () => throw const FormatException('Unexpected request status.'),
);
RepairRequest _summary(Map<String, dynamic> json, String userId) {
  if (json['student_id'] != userId) throw _accessFailure;
  final version = json['version'];
  if (version is! int || version < 1) {
    throw const FormatException('Invalid request version.');
  }
  return RepairRequest(
    id: _id(json, 'id'),
    studentId: userId,
    requestCode: _text(json, 'request_code'),
    title: _text(json, 'title'),
    categoryName: _text(json, 'category_name'),
    roomCode: _text(json, 'room_code'),
    status: _status(json['status']),
    createdAt: _timestamp(json, 'created_at'),
    version: version,
  );
}

String _actionLabel(String action) => switch (action) {
  'created' => 'Đã tạo yêu cầu',
  'assigned' => 'Đã phân công kỹ thuật viên',
  'started' => 'Kỹ thuật viên bắt đầu xử lý',
  'result_submitted' => 'Kỹ thuật viên đã gửi kết quả',
  'completed' => 'Đã xác nhận hoàn tất',
  'student_confirmed' => 'Sinh viên xác nhận đã sửa xong',
  'student_rework_requested' => 'Sinh viên yêu cầu xử lý lại',
  'student_edited' => 'Sinh viên chỉnh sửa yêu cầu',
  'student_cancelled' => 'Sinh viên hủy yêu cầu',
  'student_reopened' => 'Sinh viên mở lại yêu cầu',
  'rejected' => 'Đã từ chối yêu cầu',
  'cancelled' => 'Đã hủy yêu cầu',
  'transferred' => 'Đã chuyển kỹ thuật viên',
  _ => 'Cập nhật yêu cầu',
};
