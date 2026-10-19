/// Quy tắc kiểm tra mật khẩu (DF-003, DF-004), viết thành hàm thuần để unit test.
abstract final class PasswordRules {
  static const minLength = 6;

  /// Kiểm tra mật khẩu mới: bắt buộc nhập, tối thiểu 6 ký tự.
  static String? validateNewPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập mật khẩu mới.';
    }
    if (value.length < minLength) {
      return 'Mật khẩu mới phải có ít nhất $minLength ký tự.';
    }
    return null;
  }

  /// Kiểm tra xác nhận mật khẩu: bắt buộc nhập, phải khớp với mật khẩu mới.
  static String? validateConfirmPassword(String? confirm, String? newPassword) {
    if (confirm == null || confirm.isEmpty) {
      return 'Vui lòng xác nhận mật khẩu mới.';
    }
    if (confirm != newPassword) {
      return 'Mật khẩu xác nhận không khớp.';
    }
    return null;
  }
}
