import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/supabase_session_guard.dart';
import '../../../core/models/app_role.dart';
import '../../auth/models/password_rules.dart';
import '../../profile/models/phone_rules.dart';
import '../models/account_lifecycle_action.dart';
import '../models/managed_account.dart';
import '../models/managed_account_input.dart';
import 'admin_account_lifecycle_repository.dart';
import 'admin_account_management_repository.dart';

export 'admin_accounts_failure.dart';

abstract interface class AdminAccountsRepository {
  Future<List<ManagedAccount>> list({
    required String query,
    AppRole? role,
    AccountStatus? status,
    required int offset,
    required int limit,
  });
}

class SupabaseAdminAccountsRepository
    implements
        AdminAccountsRepository,
        AdminAccountManagementRepository,
        AdminAccountLifecycleRepository {
  const SupabaseAdminAccountsRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<ManagedAccount>> list({
    required String query,
    AppRole? role,
    AccountStatus? status,
    required int offset,
    required int limit,
  }) {
    final search = query.trim();
    return _run((token) async {
      final data = await _rpc('admin_list_accounts', token, {
        'p_query': search.isEmpty ? null : search,
        'p_role': role?.databaseValue,
        'p_status': status?.databaseValue,
        'p_offset': offset,
        'p_limit': limit,
      });
      return List<ManagedAccount>.unmodifiable(
        (data as List).map((row) => ManagedAccount.fromJson(_object(row))),
      );
    }, errorMessage: 'Không thể tải danh sách tài khoản. Vui lòng thử lại.');
  }

  @override
  Future<ManagedAccountDetails> fetchDetails(String identityCode) async {
    final code = identityCode.trim();
    if (code.isEmpty) throw _invalidInput;
    return _run((token) async {
      final details = _account(
        await _rpc('admin_get_account', token, {'p_identity_code': code}),
      );
      if (details.identityCode.toLowerCase() != code.toLowerCase()) {
        throw const FormatException('Mismatched account detail.');
      }
      return details;
    }, errorMessage: 'Không thể tải thông tin tài khoản. Vui lòng thử lại.');
  }

  @override
  Future<ManagedAccountDetails> createAccount(
    CreateManagedAccount input,
  ) async {
    final identityCode = input.identityCode.trim();
    final fullName = input.fullName.trim();
    final email = input.email.trim().toLowerCase();
    final phone = _validPhone(input.phone);
    final roomId = _validRoomId(input.roomId);
    if (identityCode.isEmpty ||
        fullName.isEmpty ||
        !_email.hasMatch(email) ||
        input.role == AppRole.admin) {
      throw _invalidInput;
    }
    if (input.role == AppRole.student && roomId == null) {
      throw _activeRoomRequired;
    }
    if (input.role == AppRole.technician && roomId != null) throw _invalidInput;
    _validateTemporaryPassword(input.temporaryPassword);

    return _run((token) async {
      final response = await _client.functions.invoke(
        'admin-create-account',
        headers: {'Authorization': 'Bearer $token'},
        body: {
          'identity_code': identityCode,
          'full_name': fullName,
          'email': email,
          'phone': phone,
          'role': input.role.databaseValue,
          'room_id': roomId,
          'temporary_password': input.temporaryPassword,
        },
      );
      final account = _account(_object(response.data)['account']);
      if (account.identityCode != identityCode ||
          account.fullName != fullName ||
          account.email != email ||
          account.phone != phone ||
          account.role != input.role ||
          account.roomId != roomId ||
          account.status != AccountStatus.active ||
          !account.mustChangePassword) {
        throw const FormatException('Mismatched creation receipt.');
      }
      return account;
    }, write: true);
  }

  @override
  Future<ManagedAccountDetails> updateAccount(
    UpdateManagedAccount input,
  ) async {
    final id = input.id.trim().toLowerCase();
    final fullName = input.fullName.trim();
    final phone = _validPhone(input.phone);
    final roomId = _validRoomId(input.roomId);
    if (!_uuid.hasMatch(id) || fullName.isEmpty) throw _invalidInput;
    return _run((token) async {
      final row = _object(
        await _rpc('admin_update_account', token, {
          'p_account_id': id,
          'p_full_name': fullName,
          'p_phone': phone,
          'p_room_id': roomId,
        }),
      );
      final account = _account(row);
      if (row['changed'] is! bool ||
          account.id != id ||
          account.fullName != fullName ||
          account.phone != phone ||
          account.roomId != roomId) {
        throw const FormatException('Mismatched update receipt.');
      }
      return account;
    }, write: true);
  }

  @override
  Future<ManagedAccountDetails> changeAccountStatus({
    required String accountId,
    required AccountStatus expectedStatus,
    required AccountLifecycleAction action,
    String? reason,
    String? roomId,
  }) async {
    final id = accountId.trim().toLowerCase();
    final note = reason?.trim();
    final destination = _validRoomId(roomId);
    if (!_uuid.hasMatch(id) ||
        (destination != null && action != AccountLifecycleAction.restore)) {
      throw _invalidInput;
    }
    if ((action == AccountLifecycleAction.lock ||
            action == AccountLifecycleAction.revoke) &&
        (note == null || note.isEmpty)) {
      throw _reasonRequired;
    }
    if (note != null && note.runes.length > 500) throw _reasonTooLong;
    return _run((token) async {
      final row = _object(
        await _rpc('admin_change_account_status', token, {
          'p_account_id': id,
          'p_expected_status': expectedStatus.databaseValue,
          'p_action': action.name,
          'p_reason': note,
          'p_room_id': destination,
        }),
      );
      final account = _account(row);
      if (row['changed'] is! bool ||
          account.id != id ||
          account.status != action.resultingStatus ||
          (action == AccountLifecycleAction.restore &&
              account.roomId != destination)) {
        throw const FormatException('Mismatched account status receipt.');
      }
      return account;
    }, write: true);
  }

  @override
  Future<ManagedAccountDetails> resetTemporaryPassword({
    required String accountId,
    required AccountStatus expectedStatus,
    required String temporaryPassword,
  }) async {
    final id = accountId.trim().toLowerCase();
    if (!_uuid.hasMatch(id)) throw _invalidInput;
    if (expectedStatus == AccountStatus.revoked) throw _statusChanged;
    _validateTemporaryPassword(temporaryPassword);

    return _run((token) async {
      final response = await _client.functions.invoke(
        'admin-reset-account-password',
        headers: {'Authorization': 'Bearer $token'},
        body: {
          'account_id': id,
          'expected_status': expectedStatus.databaseValue,
          'temporary_password': temporaryPassword,
        },
      );
      final account = _account(_object(response.data)['account']);
      if (account.id != id ||
          account.status != expectedStatus ||
          !account.mustChangePassword) {
        throw const FormatException('Mismatched password reset receipt.');
      }
      return account;
    }, write: true);
  }

  Future<dynamic> _rpc(
    String name,
    String token,
    Map<String, dynamic> params,
  ) => _client
      .rpc(name, params: params)
      .setHeader('Authorization', 'Bearer $token');

  Future<T> _run<T>(
    Future<T> Function(String token) operation, {
    String errorMessage = 'Không thể tải thông tin tài khoản.',
    bool write = false,
  }) => SupabaseSessionGuard(_client).run((token) async {
    try {
      return await operation(token);
    } on PostgrestException catch (error) {
      throw _rpcFailure(error) ?? _operationFailure(write, errorMessage);
    } on FunctionException catch (error) {
      throw _edgeFailure(error);
    } on AuthException {
      throw _accessDenied;
    } on AdminAccountsFailure {
      rethrow;
    } catch (_) {
      throw _operationFailure(write, errorMessage);
    }
  }, denied: _accessDenied);
}

final _uuid = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);
final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

Map<String, dynamic> _object(Object? value) =>
    Map<String, dynamic>.from(value as Map);

String _requiredText(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid account data.');
  }
  return value;
}

ManagedAccountDetails _account(Object? value) {
  final row = _object(value);
  final summary = ManagedAccount.fromJson(row);
  final id = _requiredText(row, 'id');
  final room = row['room_id'];
  final mustChangePassword = row['must_change_password'];
  if (!_uuid.hasMatch(id) ||
      !row.containsKey('room_id') ||
      (summary.role == AppRole.student
          ? room is! String || !_uuid.hasMatch(room)
          : room != null) ||
      mustChangePassword is! bool) {
    throw const FormatException('Invalid account detail.');
  }
  return ManagedAccountDetails(
    id: id,
    fullName: _requiredText(row, 'full_name'),
    identityCode: _requiredText(row, 'identity_code'),
    email: _requiredText(row, 'email'),
    phone: _requiredText(row, 'phone'),
    role: summary.role,
    status: summary.status,
    roomId: room as String?,
    mustChangePassword: mustChangePassword,
  );
}

String _validPhone(String phone) {
  final error = PhoneRules.validatePhone(phone);
  if (error != null) throw AdminAccountsFailure(error);
  return PhoneRules.normalize(phone);
}

String? _validRoomId(String? value) {
  if (value == null) return null;
  final id = value.trim().toLowerCase();
  if (!_uuid.hasMatch(id)) throw _invalidInput;
  return id;
}

void _validateTemporaryPassword(String value) {
  if (!PasswordRules.hasMinLength(value) ||
      value.trim().isEmpty ||
      utf8.encode(value).length > 72) {
    throw _invalidTemporaryPassword;
  }
}

const _accessDenied = AdminAccountsFailure(
  'Chỉ Admin đang hoạt động mới được quản lý tài khoản. Vui lòng đăng nhập lại.',
  accessDenied: true,
);
const _invalidInput = AdminAccountsFailure('Thông tin tài khoản không hợp lệ.');
const _invalidPhone = AdminAccountsFailure('Số điện thoại không hợp lệ.');
const _invalidTemporaryPassword = AdminAccountsFailure(
  'Mật khẩu tạm không đáp ứng yêu cầu. Vui lòng kiểm tra lại.',
);
const _activeRoomRequired = AdminAccountsFailure(
  'Vui lòng chọn phòng đang sử dụng cho Sinh viên.',
  conflict: true,
);
const _reasonRequired = AdminAccountsFailure('Vui lòng nhập lý do.');
const _reasonTooLong = AdminAccountsFailure(
  'Lý do không được vượt quá 500 ký tự.',
);
const _accountNotFound = AdminAccountsFailure(
  'Không tìm thấy tài khoản. Vui lòng tải lại danh sách.',
  conflict: true,
);
const _statusChanged = AdminAccountsFailure(
  'Trạng thái tài khoản không còn phù hợp với thao tác này. Vui lòng tải lại danh sách.',
  conflict: true,
);
const _openJobs = AdminAccountsFailure(
  'Kỹ thuật viên còn công việc chưa hoàn tất. Hãy xử lý hoặc chuyển giao công việc trước.',
  conflict: true,
);
const _passwordResetInProgress = AdminAccountsFailure(
  'Tài khoản đang được đặt lại mật khẩu. Vui lòng thử lại sau.',
  conflict: true,
);
const _duplicateIdentity = AdminAccountsFailure('Mã định danh đã tồn tại.');
const _duplicateEmail = AdminAccountsFailure('Email đã tồn tại.');
const _unavailable = AdminAccountsFailure(
  'Chức năng quản lý tài khoản chưa sẵn sàng. Vui lòng thử lại sau.',
);
const _unknownWrite = AdminAccountsFailure(
  'Chưa xác định được thao tác đã lưu hay chưa. Vui lòng kiểm tra lại danh sách tài khoản.',
  uncertain: true,
);

AdminAccountsFailure _operationFailure(bool write, String message) =>
    write ? _unknownWrite : AdminAccountsFailure(message);

AdminAccountsFailure? _rpcFailure(PostgrestException error) =>
    switch ((error.code, error.message)) {
      (
        '28000' ||
            '42501' ||
            '401' ||
            '403' ||
            'PGRST301' ||
            'PGRST302' ||
            'PGRST303',
        _,
      ) =>
        _accessDenied,
      ('PGRST202' || '42883', _) => _unavailable,
      ('22023', 'INVALID_ACCOUNT_INPUT') => _invalidInput,
      ('22023', 'INVALID_ACCOUNT_PHONE') => _invalidPhone,
      ('22023', 'ACTIVE_STUDENT_ROOM_REQUIRED') => _activeRoomRequired,
      ('22023', 'ACCOUNT_REASON_REQUIRED') => _reasonRequired,
      ('22023', 'ACCOUNT_REASON_TOO_LONG') => _reasonTooLong,
      ('P0001', 'ACCOUNT_STATUS_CHANGED') => _statusChanged,
      ('P0001', 'ACCOUNT_HAS_OPEN_JOBS') => _openJobs,
      ('P0001', 'ACCOUNT_RESET_IN_PROGRESS') => _passwordResetInProgress,
      ('23505', 'ACCOUNT_IDENTITY_ALREADY_EXISTS') => _duplicateIdentity,
      ('23505', 'ACCOUNT_EMAIL_ALREADY_EXISTS') => _duplicateEmail,
      ('P0002', 'ACCOUNT_NOT_FOUND') => _accountNotFound,
      _ => null,
    };

AdminAccountsFailure _edgeFailure(FunctionException error) {
  final details = error.details;
  final code = details is Map ? details['error'] : null;
  return switch ((error.status, code)) {
    (401 || 403, _) => _accessDenied,
    (404, 'ACCOUNT_NOT_FOUND') => _accountNotFound,
    (404, _) => _unavailable,
    (400, 'INVALID_ACCOUNT_INPUT') => _invalidInput,
    (400, 'INVALID_ACCOUNT_PHONE') => _invalidPhone,
    (409, 'ACTIVE_ROOM_REQUIRED' || 'ACTIVE_STUDENT_ROOM_REQUIRED') =>
      _activeRoomRequired,
    (409, 'ACCOUNT_STATUS_CHANGED') => _statusChanged,
    (409, 'ACCOUNT_RESET_IN_PROGRESS') => _passwordResetInProgress,
    (409, 'ACCOUNT_IDENTITY_ALREADY_EXISTS') => _duplicateIdentity,
    (409, 'ACCOUNT_EMAIL_ALREADY_EXISTS') => _duplicateEmail,
    (422, 'INVALID_TEMPORARY_PASSWORD') => _invalidTemporaryPassword,
    (503, 'ACCOUNT_SERVICE_UNAVAILABLE') => _unavailable,
    _ => _unknownWrite,
  };
}
