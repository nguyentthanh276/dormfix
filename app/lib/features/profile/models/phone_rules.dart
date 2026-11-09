/// Quy tắc kiểm tra và chuẩn hóa số điện thoại (DF-006, DF-019), viết thành hàm thuần để unit test.
abstract final class PhoneRules {
  /// Chuẩn hóa số điện thoại: loại bỏ khoảng trắng thừa đầu/cuối, loại bỏ dấu gạch ngang (-),
  /// dấu chấm (.) hoặc khoảng trắng giữa các cụm số (hỗ trợ dán từ danh bạ điện thoại).
  static String normalize(String? value) {
    if (value == null) return '';
    return value.trim().replaceAll(RegExp(r'[\s\.\-]+'), '');
  }

  /// Kiểm tra số điện thoại: bắt buộc nhập, đúng định dạng số điện thoại (10 chữ số bắt đầu bằng 0 hoặc chuẩn +84).
  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Vui lòng nhập số điện thoại.';
    }
    final normalized = normalize(value);
    final phoneRegex = RegExp(r'^(0|\+84)[0-9]{9}$');
    if (!phoneRegex.hasMatch(normalized)) {
      return 'Số điện thoại không hợp lệ.';
    }
    return null;
  }
}
