import 'package:dormfix/features/student_requests/models/request_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validate bắt buộc', () {
    test('tiêu đề rỗng hoặc chỉ có khoảng trắng bị từ chối', () {
      expect(RequestRules.validateTitle(null), isNotNull);
      expect(RequestRules.validateTitle(''), isNotNull);
      expect(RequestRules.validateTitle('   '), isNotNull);
      expect(RequestRules.validateTitle('Hỏng đèn'), isNull);
    });

    test('mô tả rỗng bị từ chối', () {
      expect(RequestRules.validateDescription('  '), isNotNull);
      expect(RequestRules.validateDescription('Đèn không sáng'), isNull);
    });

    test('chưa chọn loại sự cố bị từ chối', () {
      expect(RequestRules.validateCategory(null), isNotNull);
      expect(RequestRules.validateCategory('cat-dien'), isNull);
    });
  });

  group('checkNewImage', () {
    String? check({int count = 0, int size = 1000, String name = 'a.jpg'}) =>
        RequestRules.checkNewImage(
          currentCount: count,
          sizeBytes: size,
          fileName: name,
        );

    test('ảnh hợp lệ được thêm', () {
      expect(check(), isNull);
    });

    test('ảnh thứ 6 bị chặn, ảnh thứ 5 vẫn được', () {
      expect(check(count: 4), isNull);
      expect(check(count: 5), isNotNull);
    });

    test('đúng 5 MB được, vượt 5 MB 1 byte bị chặn (ca biên)', () {
      expect(check(size: RequestRules.maxImageBytes), isNull);
      expect(check(size: RequestRules.maxImageBytes + 1), isNotNull);
    });

    test('định dạng không cho phép bị chặn, không phân biệt hoa thường', () {
      expect(check(name: 'a.gif'), isNotNull);
      expect(check(name: 'khongduoi'), isNotNull);
      expect(check(name: 'A.PNG'), isNull);
      expect(check(name: 'b.webp'), isNull);
    });
  });
}
