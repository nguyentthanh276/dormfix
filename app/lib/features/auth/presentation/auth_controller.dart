import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/models/app_role.dart';
import '../data/auth_repository.dart';
import '../models/user_profile.dart';

enum AuthViewState {
  checking,
  signedOut,
  authenticated,
  changePasswordRequired,
  retryRequired,
  unavailable,
}

class AuthController extends ChangeNotifier {
  AuthController({required this._repository, String? configurationError})
    : _error = configurationError,
      _state = configurationError == null
          ? AuthViewState.checking
          : AuthViewState.unavailable {
    _sessionSubscription = _repository?.sessionChanges.listen((hasSession) {
      final isProtected =
          _state == AuthViewState.authenticated ||
          _state == AuthViewState.changePasswordRequired;
      if (!hasSession && (isProtected || _isLoading)) {
        _profile = null;
        if (!_isExplicitSignOut) {
          _error ??= 'Phiên đăng nhập đã kết thúc. Vui lòng đăng nhập lại.';
        }
        _setState(AuthViewState.signedOut);
      } else if (hasSession && isProtected && !_isLoading) {
        unawaited(restoreSession());
      }
    });
  }

  final AuthRepository? _repository;
  StreamSubscription<bool>? _sessionSubscription;
  bool _isExplicitSignOut = false;

  AuthViewState _state;
  AuthViewState get state => _state;

  UserProfile? _profile;
  UserProfile? get profile => _profile;

  String? _error;
  String? get error => _error;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> restoreSession() async {
    final repository = _repository;
    if (repository == null) {
      _setState(AuthViewState.unavailable);
      _error ??= 'Dịch vụ xác thực chưa được cấu hình.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _profile = null;
    _error = null;
    _setState(AuthViewState.checking);
    try {
      if (!repository.hasSession) {
        _profile = null;
        _setState(AuthViewState.signedOut);
      } else {
        final profile = await repository.loadProfile();
        if (!repository.hasSession) {
          _profile = null;
          _error = 'Phiên đăng nhập đã kết thúc. Vui lòng đăng nhập lại.';
          _setState(AuthViewState.signedOut);
        } else {
          _acceptProfile(profile);
        }
      }
    } on AuthFailure catch (failure) {
      await _handleFailure(failure, duringRestore: true);
    } catch (_) {
      _profile = null;
      if (!repository.hasSession) {
        _error = 'Phiên đăng nhập đã kết thúc. Vui lòng đăng nhập lại.';
        _setState(AuthViewState.signedOut);
      } else {
        _error = 'Không thể kiểm tra phiên đăng nhập do lỗi kết nối. Vui lòng thử lại.';
        _setState(AuthViewState.retryRequired);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    final repository = _repository;
    if (repository == null) {
      _error = 'Dịch vụ xác thực chưa được cấu hình.';
      _setState(AuthViewState.unavailable);
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final profile = await repository.signIn(
        email: email.trim(),
        password: password,
      );
      if (!repository.hasSession) {
        _profile = null;
        _error = 'Phiên đăng nhập đã kết thúc. Vui lòng đăng nhập lại.';
        _setState(AuthViewState.signedOut);
      } else {
        _acceptProfile(profile);
      }
    } on AuthFailure catch (failure) {
      await _handleFailure(failure);
    } catch (_) {
      _profile = null;
      _error = 'Không thể kết nối dịch vụ. Vui lòng kiểm tra mạng và thử lại.';
      _setState(AuthViewState.signedOut);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    final repository = _repository;
    if (repository == null) return;

    _isExplicitSignOut = true;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await repository.signOut();
      _profile = null;
      _error = null;
      _setState(AuthViewState.signedOut);
    } catch (_) {
      _error = 'Đăng xuất không thành công. Vui lòng thử lại.';
    } finally {
      _isLoading = false;
      _isExplicitSignOut = false;
      notifyListeners();
    }
  }

  Future<void> changeTemporaryPassword({required String newPassword}) async {
    final repository = _repository;
    if (repository == null) {
      _error = 'Dịch vụ xác thực chưa được cấu hình.';
      _setState(AuthViewState.unavailable);
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final updatedProfile = await repository.changePassword(
        newPassword: newPassword,
      );
      if (!repository.hasSession) {
        _profile = null;
        _error = 'Phiên đăng nhập đã kết thúc. Vui lòng đăng nhập lại.';
        _setState(AuthViewState.signedOut);
      } else {
        _acceptProfile(updatedProfile);
      }
    } on AuthFailure catch (failure) {
      await _handleFailure(failure, duringChangePassword: true);
    } catch (_) {
      _error = 'Không thể đổi mật khẩu do lỗi kết nối. Vui lòng thử lại.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final repository = _repository;
    if (repository == null) {
      _error = 'Dịch vụ xác thực chưa được cấu hình.';
      _setState(AuthViewState.unavailable);
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await repository.updatePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      _error = null;
      return true;
    } on AuthFailure catch (failure) {
      _error = failure.message;
      if (failure.signOutRequired) {
        _profile = null;
        try {
          await repository.signOut();
        } catch (_) {
          _error =
              '${failure.message} Không thể kết thúc phiên đăng nhập; '
              'vui lòng thử đăng xuất lại.';
        }
        _setState(AuthViewState.signedOut);
      }
      return false;
    } catch (_) {
      _error = 'Không thể đổi mật khẩu do lỗi kết nối. Vui lòng thử lại.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _acceptProfile(UserProfile profile) {
    if (profile.status == 'locked' || profile.status == 'revoked') {
      throw AuthFailure(
        profile.status == 'locked'
            ? 'Tài khoản đang bị khóa và không được phép truy cập.'
            : 'Quyền truy cập tài khoản đã bị thu hồi.',
        signOutRequired: true,
      );
    }
    if (profile.status != 'active') {
      throw const AuthFailure(
        'Trạng thái tài khoản không hợp lệ. Vui lòng liên hệ quản trị viên.',
        signOutRequired: true,
      );
    }
    if (profile.mustChangePassword) {
      _profile = profile;
      _setState(AuthViewState.changePasswordRequired);
      return;
    }
    if (profile.canAccess != true || !AppRole.values.contains(profile.role)) {
      throw const AuthFailure(
        'Tài khoản chưa được cấp quyền truy cập. Vui lòng liên hệ quản trị viên.',
        signOutRequired: true,
      );
    }

    _profile = profile;
    _setState(AuthViewState.authenticated);
  }

  Future<void> _handleFailure(
    AuthFailure failure, {
    bool duringRestore = false,
    bool duringChangePassword = false,
  }) async {
    _error = failure.message;
    if (failure.signOutRequired) {
      _profile = null;
      try {
        await _repository?.signOut();
      } catch (_) {
        _error =
            '${failure.message} Không thể kết thúc phiên đăng nhập; '
            'vui lòng thử đăng xuất lại.';
      }
      _setState(AuthViewState.signedOut);
      return;
    }

    if (duringChangePassword) {
      _setState(AuthViewState.changePasswordRequired);
      return;
    }

    _profile = null;
    _setState(
      duringRestore ? AuthViewState.retryRequired : AuthViewState.signedOut,
    );
  }

  void _setState(AuthViewState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sessionSubscription?.cancel());
    super.dispose();
  }
}
