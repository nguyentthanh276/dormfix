/// Quy tắc kiểm tra số điện thoại (DF-006, DF-019), viết thành hàm thuần để unit test.
abstract final class PhoneRules {
  /// Kiểm tra số điện thoại: bắt buộc nhập, đúng định dạng số điện thoại (10 chữ số bắt đầu bằng 0 hoặc chuẩn +84).
  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Vui lòng nhập số điện thoại.';
    }
    final trimmed = value.trim();
    final phoneRegex = RegExp(r'^(0|\+84)[0-9]{9}$');
    if (!phoneRegex.hasMatch(trimmed)) {
      return 'Số điện thoại không hợp lệ.';
    }
    return null;
  }
}
