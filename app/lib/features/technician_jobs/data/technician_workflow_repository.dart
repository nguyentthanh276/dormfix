import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/repair_status.dart';
import '../models/technician_workflow.dart';

abstract interface class TechnicianWorkflowRepository {
  Future<TechnicianWriteReceipt> startJob({
    required String requestId,
    required int expectedVersion,
  });

  Future<TechnicianWriteReceipt> continueJob({
    required String requestId,
    required int expectedVersion,
  });

  Future<TechnicianWriteReceipt> submitResult(
    TechnicianResultSubmission submission,
  );
}

/// Writes are authorized and version checked by the server on every call.
class SupabaseTechnicianWorkflowRepository
    implements TechnicianWorkflowRepository {
  SupabaseTechnicianWorkflowRepository(this._client);

  final SupabaseClient _client;
  final Map<String, String> _submissionOwners = {};
  final Set<String> _uncertainResults = {};

  static const _bucket = 'repair-images';
  static const _accessFailure = TechnicianWorkflowFailure(
    'Bạn không còn quyền cập nhật công việc này. Vui lòng tải lại hoặc đăng nhập lại.',
    accessDenied: true,
  );

  @override
  Future<TechnicianWriteReceipt> startJob({
    required String requestId,
    required int expectedVersion,
  }) => _transitionToInProgress(
    rpcName: 'technician_start_job',
    requestId: requestId,
    expectedVersion: expectedVersion,
  );

  @override
  Future<TechnicianWriteReceipt> continueJob({
    required String requestId,
    required int expectedVersion,
  }) => _transitionToInProgress(
    rpcName: 'technician_continue_job',
    requestId: requestId,
    expectedVersion: expectedVersion,
    exactReceipt: true,
  );

  Future<TechnicianWriteReceipt> _transitionToInProgress({
    required String rpcName,
    required String requestId,
    required int expectedVersion,
    bool exactReceipt = false,
  }) async {
    var sent = false;
    String? userId;
    try {
      if (!isTechnicianWorkflowId(requestId) || expectedVersion <= 0) {
        throw const TechnicianWorkflowFailure(
          'Thông tin công việc không hợp lệ. Vui lòng tải lại.',
        );
      }
      userId = _requireSession();
      sent = true;
      final result = await _client.rpc(
        rpcName,
        params: {
          'p_request_id': requestId,
          'p_expected_version': expectedVersion,
        },
      );
      _requireSession(userId);
      final json = _jsonObject(result);
      if (exactReceipt &&
          (json.length != 3 ||
              !json.keys.every({'request_id', 'status', 'version'}.contains))) {
        throw const FormatException('Unexpected continue receipt fields.');
      }
      final receipt = TechnicianWriteReceipt.fromJson(json);
      if (receipt.requestId != requestId ||
          receipt.version != expectedVersion + 1 ||
          receipt.status != RepairStatus.inProgress ||
          receipt.resultId != null ||
          receipt.replayed) {
        throw const FormatException('Unexpected transition receipt.');
      }
      return receipt;
    } catch (error) {
      if (userId != null && !_sameSession(userId)) throw _accessFailure;
      throw _failure(error, uncertain: sent);
    }
  }

  @override
  Future<TechnicianWriteReceipt> submitResult(
    TechnicianResultSubmission submission,
  ) async {
    String? userId;
    var finalizationSent = false;
    final paths = <String>[];
    try {
      userId = _requireSession();
      final owner = _submissionOwners[submission.resultId];
      if (owner != null && owner != userId) throw _accessFailure;
      _submissionOwners[submission.resultId] = userId;
      paths.addAll(
        submission.photos.map((p) => submission.storagePath(userId!, p)),
      );
      final manifest = [
        for (var i = 0; i < submission.photos.length; i++)
          {
            'id': submission.photos[i].id,
            'storage_path': paths[i],
            'mime_type': submission.photos[i].mimeType,
            'size_bytes': submission.photos[i].sizeBytes,
          },
      ];

      Future<TechnicianWriteReceipt> finalize() async {
        _requireSession(userId);
        finalizationSent = true;
        final result = await _client.rpc(
          'technician_submit_result',
          params: {
            'p_request_id': submission.requestId,
            'p_expected_version': submission.expectedVersion,
            'p_result_id': submission.resultId,
            'p_content': submission.content,
            'p_photos': manifest,
          },
        );
        _requireSession(userId);
        final receipt = TechnicianWriteReceipt.fromJson(_jsonObject(result));
        if (receipt.requestId != submission.requestId ||
            receipt.resultId != submission.resultId ||
            receipt.version != submission.expectedVersion + 1 ||
            receipt.status != RepairStatus.awaitingConfirmation) {
          throw const FormatException('Unexpected result receipt.');
        }
        _uncertainResults.remove(submission.resultId);
        return receipt;
      }

      // A lost response may already have committed. Replay before touching
      // Storage: finalized objects cannot be inserted or deleted again.
      if (_uncertainResults.contains(submission.resultId)) {
        try {
          return await finalize();
        } on PostgrestException catch (error) {
          if (error.code != '22023' ||
              error.message != 'INVALID_RESULT_PHOTOS') {
            rethrow;
          }
          // The original transaction did not commit and staging was cleaned.
          _requireSession(userId);
          _uncertainResults.remove(submission.resultId);
          finalizationSent = false;
        }
      }

      for (var i = 0; i < submission.photos.length; i++) {
        await _stagePhoto(userId, paths[i], submission.photos[i]);
        _requireSession(userId);
      }
      return await finalize();
    } catch (error) {
      if (userId != null && !_sameSession(userId)) throw _accessFailure;
      final failure = _failure(error, uncertain: finalizationSent);
      if (failure.uncertain) _uncertainResults.add(submission.resultId);
      // DELETE policies allow only this user's uncommitted staging objects.
      // A committed result is protected even when its response was lost.
      if (userId != null && paths.isNotEmpty && _sameSession(userId)) {
        try {
          await _client.storage.from(_bucket).remove(paths);
        } catch (_) {
          // Best effort only; preserve the original, sanitized write failure.
        }
      }
      throw failure;
    }
  }

  Future<void> _stagePhoto(
    String userId,
    String path,
    TechnicianResultPhoto photo,
  ) async {
    _requireSession(userId);
    if (await _existingPhoto(userId, path, photo)) return;
    _requireSession(userId);
    try {
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            photo.bytes,
            fileOptions: FileOptions(
              contentType: photo.mimeType,
              cacheControl: '0',
              upsert: false,
            ),
            retryAttempts: 0,
          );
      _requireSession(userId);
    } on StorageException catch (error) {
      _requireSession(userId);
      if (!_isDuplicate(error) || !await _existingPhoto(userId, path, photo)) {
        rethrow;
      }
    }
  }

  Future<bool> _existingPhoto(
    String userId,
    String path,
    TechnicianResultPhoto photo,
  ) async {
    try {
      final object = await _client.storage.from(_bucket).info(path);
      _requireSession(userId);
      // Canonical UID paths and Storage SELECT policies establish ownership;
      // the final RPC independently checks owner_id, size and MIME metadata.
      final size = object.size ?? object.metadata?['size'];
      final mime = object.contentType ?? object.metadata?['mimetype'];
      if (object.bucketId != _bucket ||
          object.name != path ||
          size != photo.sizeBytes ||
          mime != photo.mimeType) {
        throw const TechnicianWorkflowFailure(
          'Ảnh đã tải lên không khớp. Vui lòng chọn lại ảnh.',
        );
      }
      return true;
    } on StorageException catch (error) {
      _requireSession(userId);
      if (_isMissing(error)) return false;
      rethrow;
    }
  }

  String _requireSession([String? expectedUser]) {
    final session = _client.auth.currentSession;
    if (session == null ||
        session.accessToken.isEmpty ||
        session.isExpired ||
        !isTechnicianWorkflowId(session.user.id) ||
        (expectedUser != null && session.user.id != expectedUser)) {
      throw _accessFailure;
    }
    return session.user.id;
  }

  bool _sameSession(String userId) {
    try {
      _requireSession(userId);
      return true;
    } catch (_) {
      return false;
    }
  }
}

TechnicianWorkflowFailure _failure(Object error, {required bool uncertain}) {
  if (error is TechnicianWorkflowFailure) return error;
  if (error is PostgrestException) {
    if (_accessCodes.contains(error.code)) {
      return SupabaseTechnicianWorkflowRepository._accessFailure;
    }
    if (error.code == 'P0001') {
      return const TechnicianWorkflowFailure(
        'Công việc đã thay đổi hoặc cần hoàn tất bước trước. Vui lòng tải lại.',
        conflict: true,
      );
    }
    if (error.code == '22023') {
      return TechnicianWorkflowFailure(switch (error.message) {
        'RESULT_CONTENT_REQUIRED' => 'Vui lòng nhập kết quả sửa chữa.',
        'INVALID_RESULT_PHOTOS' =>
          'Ảnh kết quả không hợp lệ. Vui lòng kiểm tra và thử lại.',
        'RESULT_REPLAY_MISMATCH' =>
          'Nội dung gửi lại không khớp. Vui lòng tải lại công việc.',
        _ => 'Dữ liệu cập nhật không hợp lệ. Vui lòng kiểm tra lại.',
      });
    }
    if (error.code == 'PGRST202') {
      return const TechnicianWorkflowFailure(
        'Database chưa được cập nhật chức năng này. Vui lòng liên hệ Admin.',
      );
    }
  }
  if (error is AuthException ||
      (error is StorageException && _accessCodes.contains(error.statusCode))) {
    return SupabaseTechnicianWorkflowRepository._accessFailure;
  }
  return TechnicianWorkflowFailure(
    uncertain
        ? 'Chưa xác định được kết quả cập nhật. Vui lòng tải lại hoặc thử gửi lại cùng nội dung.'
        : 'Không thể cập nhật công việc. Vui lòng thử lại.',
    uncertain: uncertain,
  );
}

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

bool _isMissing(StorageException error) =>
    error.statusCode == '404' ||
    (error.statusCode == '400' &&
        (error.error == 'not_found' || error.message == 'Object not found'));

bool _isDuplicate(StorageException error) =>
    error.statusCode == '409' ||
    (error.statusCode == '400' && error.error == 'Duplicate');

Map<String, dynamic> _jsonObject(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected a JSON object.');
  }
  return Map<String, dynamic>.from(value);
}
