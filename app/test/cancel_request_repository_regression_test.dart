import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/models/edit_repair_request.dart';
import 'package:dormfix/features/student_requests/models/history_entry.dart';
import 'package:dormfix/features/student_requests/models/new_repair_request.dart';
import 'package:flutter_test/flutter_test.dart';

List<Object?> _event(HistoryEntry entry) => [
  entry.status,
  entry.note,
  entry.createdAt,
  entry.actorId,
  entry.actorName,
];

void main() {
  for (final reason in ['', ' \n\t ']) {
    test(
      'repository rejects blank reason without changing request or history ($reason)',
      () async {
        final repo = MockRequestRepository.withSamplePending();
        final before = await repo.fetchRequestDetail('mock-3');

        await expectLater(
          repo.cancelRequest(requestId: 'mock-3', reason: reason),
          throwsA(isA<Exception>()),
        );

        final after = await repo.fetchRequestDetail('mock-3');
        expect(after.request.status, RepairStatus.pending);
        expect(after.history.map(_event), before.history.map(_event));
      },
    );
  }

  test('cancelling pending preserves lack of assignment and records trimmed reason and actor', () async {
    final repo = MockRequestRepository.withSamplePending(
      studentId: 'student-a',
      studentName: 'Nguyễn Văn A',
    );
    final before = await repo.fetchRequestDetail('mock-3');
    final sentAt = DateTime.now();

    await repo.cancelRequest(
      requestId: 'mock-3',
      reason: '  Không cần sửa nữa  ',
    );

    final after = await repo.fetchRequestDetail('mock-3');
    expect(after.request.status, RepairStatus.cancelled);
    expect(after.technicianName, isNull);
    expect(after.technicianPhone, isNull);
    expect(
      after.history.take(before.history.length).map(_event),
      before.history.map(_event),
    );
    expect(after.history.last.note, 'Sinh viên hủy yêu cầu: Không cần sửa nữa');
    expect(after.history.last.actorId, 'student-a');
    expect(after.history.last.actorName, 'Nguyễn Văn A');
    expect(after.history.last.createdAt.isBefore(sentAt), isFalse);
  });

  test(
    'cancelling assigned retains existing assignment history and contact',
    () async {
      final repo = MockRequestRepository(delay: Duration.zero);
      final before = await repo.fetchRequestDetail('mock-2');
      expect(
        before.history.any((entry) => entry.status == RepairStatus.assigned),
        isTrue,
      );

      await repo.cancelRequest(
        requestId: 'mock-2',
        reason: 'Không còn nhu cầu',
      );

      final after = await repo.fetchRequestDetail('mock-2');
      expect(after.history.length, before.history.length + 1);
      expect(
        after.history.take(before.history.length).map(_event),
        before.history.map(_event),
      );
      expect(after.history.last.status, RepairStatus.cancelled);
      expect(after.technicianName, before.technicianName);
      expect(after.technicianPhone, before.technicianPhone);
    },
  );

  test('concurrent cancellations append only one cancellation event', () async {
    final repo = MockRequestRepository.withSamplePending(
      delay: const Duration(milliseconds: 10),
    );
    final first = repo.cancelRequest(requestId: 'mock-3', reason: 'Lần đầu');
    final duplicate = expectLater(
      repo.cancelRequest(requestId: 'mock-3', reason: 'Lần lặp'),
      throwsA(isA<Exception>()),
    );
    await first;
    await duplicate;

    final after = await repo.fetchRequestDetail('mock-3');
    expect(
      after.history.where((entry) => entry.status == RepairStatus.cancelled),
      hasLength(1),
    );
    expect(after.history.last.note, contains('Lần đầu'));
  });

  test(
    'an edit waiting behind cancellation cannot restore the cancelled request',
    () async {
      final repo = MockRequestRepository.withSamplePending(
        delay: const Duration(milliseconds: 10),
      );
      final cancellation = repo.cancelRequest(
        requestId: 'mock-3',
        reason: 'Không cần nữa',
      );
      final edit = expectLater(
        repo.updateRequest(
          const EditRepairRequest(
            requestId: 'mock-3',
            title: 'Nội dung cũ đang lưu',
            categoryId: 'cat-noithat',
            description: 'Không được ghi đè sau hủy',
          ),
        ),
        throwsA(isA<Exception>()),
      );
      await cancellation;
      await edit;
      final after = await repo.fetchRequestDetail('mock-3');
      expect(after.request.status, RepairStatus.cancelled);
      expect(after.request.title, 'Cửa sổ bị kẹt chốt');
    },
  );

  test('completed request stays unchanged and a new request has a distinct identity', () async {
    final repo = MockRequestRepository.withSamplePending();
    final completed = await repo.fetchRequestDetail('mock-1');
    await expectLater(
      repo.cancelRequest(requestId: 'mock-1', reason: 'Không hợp lệ'),
      throwsA(isA<Exception>()),
    );
    expect(
      (await repo.fetchRequestDetail('mock-1')).history.map(_event),
      completed.history.map(_event),
    );
    await repo.cancelRequest(requestId: 'mock-3', reason: 'Tạo yêu cầu khác');
    final created = await repo.createRequest(
      const NewRepairRequest(
        title: 'Sự cố mới',
        categoryId: 'cat-dien',
        description: 'Một yêu cầu độc lập',
      ),
    );
    expect(created.id, isNot('mock-3'));
    expect(created.status, RepairStatus.pending);
    expect(
      (await repo.fetchRequestDetail('mock-3')).request.status,
      RepairStatus.cancelled,
    );
  });
}
