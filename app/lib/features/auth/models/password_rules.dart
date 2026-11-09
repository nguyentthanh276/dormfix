/// Quy tắc kiểm tra mật khẩu (DF-003, DF-004), viết thành hàm thuần để unit test.
abstract final class PasswordRules {
  static const minLength = 6;

  /// Kiểm tra xem mật khẩu có đạt độ dài tối thiểu hay không.
  static bool hasMinLength(String? value) =>
      value != null && value.length >= minLength;

  /// Kiểm tra xem mật khẩu có chứa chữ cái hay không.
  static bool hasLetter(String? value) =>
      value != null && RegExp(r'[a-zA-Z]').hasMatch(value);

  /// Kiểm tra xem mật khẩu có chứa chữ số hay không.
  static bool hasDigit(String? value) =>
      value != null && RegExp(r'[0-9]').hasMatch(value);

  /// Kiểm tra mật khẩu hiện tại: bắt buộc nhập.
  static String? validateCurrentPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập mật khẩu hiện tại.';
    }
    return null;
  }

  /// Kiểm tra mật khẩu mới: bắt buộc nhập, tối thiểu 6 ký tự.
  static String? validateNewPassword(String? value, {String? currentPassword}) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập mật khẩu mới.';
    }
    if (value.length < minLength) {
      return 'Mật khẩu mới phải có ít nhất $minLength ký tự.';
    }
    if (currentPassword != null &&
        currentPassword.isNotEmpty &&
        value == currentPassword) {
      return 'Mật khẩu mới không được trùng với mật khẩu hiện tại.';
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
