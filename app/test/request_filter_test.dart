import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/student_requests/models/repair_request.dart';
import 'package:dormfix/features/student_requests/models/request_filter.dart';
import 'package:flutter_test/flutter_test.dart';

// Tạo nhanh một yêu cầu mẫu chỉ khác nhau ở id và trạng thái.
RepairRequest _r(String id, RepairStatus status) => RepairRequest(
  id: id,
  requestCode: id,
  title: 'Yêu cầu $id',
  categoryName: 'Điện',
  roomCode: 'A101',
  status: status,
  createdAt: DateTime(2026, 10, 20),
);

void main() {
  final all = [
    _r('1', RepairStatus.pending),
    _r('2', RepairStatus.completed),
    _r('3', RepairStatus.pending),
  ];

  group('byStatus', () {
    test('lọc theo một trạng thái thì chỉ còn yêu cầu đúng trạng thái đó', () {
      final result = RequestFilter.byStatus(all, RepairStatus.pending);
      expect(result.map((r) => r.id), ['1', '3']);
    });

    test('null (Tất cả) thì giữ nguyên toàn bộ', () {
      expect(RequestFilter.byStatus(all, null).length, 3);
    });

    // Ca biên: trạng thái không có yêu cầu nào.
    test('trạng thái không có yêu cầu nào thì trả danh sách rỗng', () {
      expect(RequestFilter.byStatus(all, RepairStatus.cancelled), isEmpty);
    });

    test('danh sách rỗng thì lọc cũng rỗng, không lỗi', () {
      expect(RequestFilter.byStatus([], RepairStatus.pending), isEmpty);
    });
  });

  group('availableStatuses và count', () {
    test('chỉ trả trạng thái đang có, theo thứ tự enum', () {
      expect(RequestFilter.availableStatuses(all), [
        RepairStatus.pending,
        RepairStatus.completed,
      ]);
    });

    test('count đếm đúng số yêu cầu của từng trạng thái', () {
      expect(RequestFilter.count(all, RepairStatus.pending), 2);
      expect(RequestFilter.count(all, RepairStatus.cancelled), 0);
    });
  });

  // Ca của lỗi "kẹt bộ lọc": trạng thái đang chọn biến mất sau khi tải lại.
  group('validSelection', () {
    test('trạng thái đang chọn vẫn còn thì giữ nguyên', () {
      expect(
        RequestFilter.validSelection(all, RepairStatus.completed),
        RepairStatus.completed,
      );
    });

    test('trạng thái đang chọn không còn yêu cầu nào thì về Tất cả (null)', () {
      expect(RequestFilter.validSelection(all, RepairStatus.cancelled), isNull);
    });

    test('đang chọn Tất cả (null) thì vẫn là null', () {
      expect(RequestFilter.validSelection(all, null), isNull);
    });
  });
}
