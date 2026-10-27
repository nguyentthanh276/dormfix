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

    final repo = repository;
    final trimmedPhone = newPhone.trim();

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (repo == null) {
        // Fallback cập nhật profile cục bộ nếu repository chưa được inject
        final updated = currentProfile.copyWith(phone: trimmedPhone);
        authController.updateProfileLocally(updated);
        return true;
      }

      final updatedProfile = await repo.updatePhone(phone: trimmedPhone);
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
