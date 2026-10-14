import 'package:flutter/foundation.dart';

import '../data/admin_accounts_repository.dart';
import '../models/create_student_result.dart';
import '../models/room_summary.dart';

enum CreateStudentState {
  /// Fetching the list of active rooms.
  loadingRooms,

  /// Ready to fill in the form.
  idle,

  /// Submitting the create-student request.
  submitting,

  /// Account created successfully.
  success,

  /// Fatal error loading rooms (no rooms available, server error, etc.).
  roomLoadError,
}

/// ViewModel for the Create Student Account form (DF-031).
///
/// Lifecycle:
/// 1. Construct, then call [loadRooms].
/// 2. Bind form fields to [identityCode], [fullName], [email], [phone],
///    [selectedRoom], [tempPassword].
/// 3. Call [submit] to create the account.
/// 4. Observe [state] for [CreateStudentState.success] or read [error].
class CreateStudentController extends ChangeNotifier {
  CreateStudentController({required AdminAccountsRepository repository})
    : _repository = repository;

  final AdminAccountsRepository _repository;

  CreateStudentState _state = CreateStudentState.loadingRooms;
  CreateStudentState get state => _state;

  List<RoomSummary> _rooms = const [];
  List<RoomSummary> get rooms => List.unmodifiable(_rooms);

  RoomSummary? _selectedRoom;
  RoomSummary? get selectedRoom => _selectedRoom;

  String? _error;
  String? get error => _error;

  CreateStudentResult? _result;
  CreateStudentResult? get result => _result;

  bool get isLoading =>
      _state == CreateStudentState.loadingRooms ||
      _state == CreateStudentState.submitting;

  // ── Mutable form fields ───────────────────────────────────────────────────

  String identityCode = '';
  String fullName = '';
  String email = '';
  String phone = '';
  String tempPassword = '';

  // ── Public actions ────────────────────────────────────────────────────────

  Future<void> loadRooms() async {
    _setState(CreateStudentState.loadingRooms);
    _error = null;
    try {
      _rooms = await _repository.fetchActiveRooms();
      if (_rooms.isEmpty) {
        _error =
            'Không có phòng nào đang hoạt động. '
            'Vui lòng tạo phòng trước khi thêm Sinh viên.';
        _setState(CreateStudentState.roomLoadError);
      } else {
        _setState(CreateStudentState.idle);
      }
    } on AdminAccountsFailure catch (f) {
      _error = f.message;
      _setState(CreateStudentState.roomLoadError);
    } catch (_) {
      _error = 'Không thể tải danh sách phòng. Vui lòng thử lại.';
      _setState(CreateStudentState.roomLoadError);
    }
  }

  void selectRoom(RoomSummary? room) {
    _selectedRoom = room;
    notifyListeners();
  }

  /// Validates and submits the form.
  ///
  /// Returns `true` when the account was created successfully.
  Future<bool> submit() async {
    if (_state == CreateStudentState.submitting) return false;

    final validationError = _validateAll();
    if (validationError != null) {
      _error = validationError;
      notifyListeners();
      return false;
    }

    _error = null;
    _setState(CreateStudentState.submitting);

    try {
      _result = await _repository.createStudent(
        identityCode: identityCode,
        fullName: fullName,
        email: email,
        phone: phone,
        roomId: _selectedRoom!.id,
        tempPassword: tempPassword,
      );
      _setState(CreateStudentState.success);
      return true;
    } on AdminAccountsFailure catch (f) {
      _error = f.message;
      _setState(CreateStudentState.idle);
      return false;
    } catch (_) {
      _error = 'Không thể tạo tài khoản. Vui lòng thử lại.';
      _setState(CreateStudentState.idle);
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ── Validation (mirrors server-side rules for fast client feedback) ────────

  String? validateIdentityCode(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Vui lòng nhập mã Sinh viên.';
    return null;
  }

  String? validateFullName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Vui lòng nhập họ tên.';
    return null;
  }

  String? validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Vui lòng nhập email.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
      return 'Email không hợp lệ.';
    }
    return null;
  }

  String? validatePhone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Vui lòng nhập số điện thoại.';
    return null;
  }

  String? validateRoom(RoomSummary? value) {
    if (value == null) return 'Vui lòng chọn phòng.';
    return null;
  }

  String? validateTempPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Vui lòng nhập mật khẩu tạm.';
    if (v.length < 8) return 'Mật khẩu tạm phải có ít nhất 8 ký tự.';
    return null;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  String? _validateAll() =>
      validateIdentityCode(identityCode) ??
      validateFullName(fullName) ??
      validateEmail(email) ??
      validatePhone(phone) ??
      validateRoom(_selectedRoom) ??
      validateTempPassword(tempPassword);

  void _setState(CreateStudentState state) {
    _state = state;
    notifyListeners();
  }
}
