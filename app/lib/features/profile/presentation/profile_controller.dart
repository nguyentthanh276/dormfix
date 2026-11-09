import 'package:flutter/foundation.dart';

import '../../auth/models/user_profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/profile_repository.dart';
import '../models/phone_rules.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({required this.authController, this.repository});

  final AuthController authController;
  final ProfileRepository? repository;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  UserProfile? get profile => authController.profile;

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  /// Tải thông tin hồ sơ mới nhất từ server (hỗ trợ Pull-to-Refresh DF-005, DF-018).
  Future<void> loadProfile({bool isRefresh = false}) async {
    if (_isLoading) return;
    final repo = repository;
    if (repo == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updatedProfile = await repo.getProfile();
      authController.updateProfileLocally(updatedProfile);
    } on ProfileFailure catch (failure) {
      _error = failure.message;
      if (failure.signOutRequired) {
        await authController.signOut();
      }
    } catch (_) {
      _error =
          'Không thể tải thông tin hồ sơ do lỗi kết nối. Vui lòng thử lại.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updatePhone(String newPhone) async {
    final validationError = PhoneRules.validatePhone(newPhone);
    if (validationError != null) {
      _error = validationError;
      notifyListeners();
      return false;
    }

    final currentProfile = profile;
    if (currentProfile == null) {
      _error = 'Không tìm thấy phiên đăng nhập hợp lệ.';
      notifyListeners();
      return false;
    }

    final normalizedPhone = PhoneRules.normalize(newPhone);
    final currentNormalized = PhoneRules.normalize(currentProfile.phone);

    // Dirty check: Nếu số điện thoại mới giống hệt số điện thoại hiện tại (sau khi chuẩn hóa),
    // không gọi RPC xuống Supabase
    if (normalizedPhone == currentNormalized) {
      return true;
    }

    final repo = repository;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (repo == null) {
        // Fallback cập nhật profile cục bộ nếu repository chưa được inject
        final updated = currentProfile.copyWith(phone: normalizedPhone);
        authController.updateProfileLocally(updated);
        return true;
      }

      final updatedProfile = await repo.updatePhone(phone: normalizedPhone);
      authController.updateProfileLocally(updatedProfile);
      return true;
    } on ProfileFailure catch (failure) {
      _error = failure.message;
      if (failure.signOutRequired) {
        await authController.signOut();
      }
      return false;
    } catch (_) {
      _error =
          'Không thể cập nhật số điện thoại do lỗi kết nối. Vui lòng thử lại.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
