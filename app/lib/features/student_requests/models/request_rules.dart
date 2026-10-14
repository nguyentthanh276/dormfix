/// Quy tắc kiểm tra form tạo yêu cầu (DF-007), viết thành hàm thuần để unit test.
abstract final class RequestRules {
  static const maxImages = 5;
  static const maxImageMb = 5;
  static const maxImageBytes = maxImageMb * 1024 * 1024;
  static const allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  /// Trả về lỗi nếu sai, null nếu hợp lệ (đúng quy ước validator của Form).
  static String? validateTitle(String? value) {
    if (value == null || value.trim().isEmpty) return 'Vui lòng nhập tiêu đề';
    return null;
  }

  static String? validateDescription(String? value) {
    if (value == null || value.trim().isEmpty) return 'Vui lòng nhập mô tả';
    return null;
  }

  static String? validateCategory(String? categoryId) {
    if (categoryId == null) return 'Vui lòng chọn loại sự cố';
    return null;
  }

  /// Kiểm tra một ảnh sắp thêm. Trả về lý do từ chối, hoặc null nếu được thêm.
  static String? checkNewImage({
    required int currentCount,
    required int sizeBytes,
    required String fileName,
  }) {
    if (currentCount >= maxImages) {
      return 'Chỉ được đính kèm tối đa $maxImages ảnh';
    }
    final dot = fileName.lastIndexOf('.');
    final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    if (!allowedExtensions.contains(extension)) {
      return 'Chỉ nhận ảnh JPG, PNG hoặc WebP';
    }
    if (sizeBytes > maxImageBytes) {
      return 'Mỗi ảnh tối đa $maxImageMb MB';
    }
    return null;
  }
}
