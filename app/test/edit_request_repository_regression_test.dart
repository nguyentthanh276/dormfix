import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/models/edit_repair_request.dart';
import 'package:dormfix/features/student_requests/models/new_repair_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'creating after the pending fixture keeps IDs and details separate',
    () async {
      final repo = MockRequestRepository.withSamplePending();
      final original = await repo.fetchRequestDetail('mock-3');

      final first = await repo.createRequest(
        const NewRepairRequest(
          title: 'Đèn bàn bị hỏng',
          categoryId: 'cat-dien',
          description: 'Đèn mới không sáng',
        ),
      );
      final second = await repo.createRequest(
        const NewRepairRequest(
          title: 'Vòi nước bị rò',
          categoryId: 'cat-nuoc',
          description: 'Nước nhỏ giọt liên tục',
        ),
      );

      final requests = await repo.fetchMyRequests();
      expect(requests, hasLength(5));
      expect(requests.map((request) => request.id).toSet(), hasLength(5));
      expect(
        requests.map((request) => request.requestCode).toSet(),
        hasLength(5),
      );
      expect(first.id, isNot('mock-3'));
      expect(second.id, isNot(first.id));
      final fixture = await repo.fetchRequestDetail('mock-3');
      expect(fixture.request.title, original.request.title);
      expect(fixture.description, original.description);
      expect(
        (await repo.fetchRequestDetail(first.id)).description,
        'Đèn mới không sáng',
      );
      expect(
        (await repo.fetchRequestDetail(second.id)).description,
        'Nước nhỏ giọt liên tục',
      );
    },
  );

  test(
    'repeated edits retain actor, operation, timestamps and earlier history',
    () async {
      final repo = MockRequestRepository.withSamplePending(
        studentId: 'student-an',
        studentName: 'Nguyễn An',
      );
      final original = await repo.fetchRequestDetail('mock-3');
      final before = DateTime.now();
      await repo.updateRequest(_edit(title: 'Cửa sổ đã thay chốt'));
      final after = DateTime.now();
      final first = await repo.fetchRequestDetail('mock-3');
      final firstEdit = first.history.last;

      expect(first.history, hasLength(2));
      expect(first.history.first.createdAt, original.history.first.createdAt);
      expect(first.history.first.note, 'Sinh viên gửi yêu cầu');
      expect(first.history.first.actorId, 'student-an');
      expect(first.history.first.actorName, 'Nguyễn An');
      expect(firstEdit.actorId, 'student-an');
      expect(firstEdit.actorName, 'Nguyễn An');
      expect(firstEdit.note, 'Sinh viên chỉnh sửa thông tin yêu cầu');
      expect(firstEdit.status, RepairStatus.pending);
      expect(firstEdit.createdAt.isBefore(before), isFalse);
      expect(firstEdit.createdAt.isAfter(after), isFalse);

      await repo.updateRequest(_edit(title: 'Cửa sổ đã thay chốt và bản lề'));
      final second = await repo.fetchRequestDetail('mock-3');
      expect(second.request.title, 'Cửa sổ đã thay chốt và bản lề');
      expect(second.history, hasLength(3));
      expect(
        first.history,
        hasLength(2),
        reason: 'An older detail remains a snapshot.',
      );
      expect(second.history[0].createdAt, original.history.first.createdAt);
      expect(second.history[1].createdAt, firstEdit.createdAt);
      expect(second.history[1].actorId, firstEdit.actorId);
      expect(second.history[1].actorName, firstEdit.actorName);
      expect(second.history[1].note, firstEdit.note);
      expect(second.history.last.actorId, 'student-an');
      expect(second.history.last.actorName, 'Nguyễn An');
      expect(
        second.history.last.createdAt.isBefore(firstEdit.createdAt),
        isFalse,
      );
    },
  );

  test('constructor identity and legacy defaults both reach create and edit audits', () async {
    for (final owner in [
      (id: 'student-binh', name: 'Trần Bình'),
      (id: 'mock-student', name: 'Sinh viên demo'),
    ]) {
      final repo = owner.id == 'mock-student'
          ? MockRequestRepository(delay: Duration.zero)
          : MockRequestRepository(
              studentId: owner.id,
              studentName: owner.name,
              delay: Duration.zero,
            );
      final request = await repo.createRequest(
        const NewRepairRequest(
          title: 'Ổ điện hỏng',
          categoryId: 'cat-dien',
          description: 'Ổ điện không cấp điện',
        ),
      );
      await repo.updateRequest(_edit(requestId: request.id));
      final detail = await repo.fetchRequestDetail(request.id);
      expect(detail.history, hasLength(2));
      for (final event in detail.history) {
        expect(event.actorId, owner.id);
        expect(event.actorName, owner.name);
      }
    }
  });

  test(
    'rejected assigned and completed edits leave content and history intact',
    () async {
      final repo = MockRequestRepository(delay: Duration.zero);
      for (final requestId in ['mock-2', 'mock-1']) {
        final before = await repo.fetchRequestDetail(requestId);
        await expectLater(
          repo.updateRequest(_edit(requestId: requestId)),
          throwsA(isA<Exception>()),
        );
        final after = await repo.fetchRequestDetail(requestId);
        expect(after.request.title, before.request.title);
        expect(after.request.status, before.request.status);
        expect(after.description, before.description);
        expect(after.studentPhotos, before.studentPhotos);
        expect(after.history, hasLength(before.history.length));
        for (var i = 0; i < before.history.length; i++) {
          expect(after.history[i].status, before.history[i].status);
          expect(after.history[i].note, before.history[i].note);
          expect(after.history[i].createdAt, before.history[i].createdAt);
          expect(after.history[i].actorId, before.history[i].actorId);
          expect(after.history[i].actorName, before.history[i].actorName);
        }
      }
    },
  );

  test('failed edit adds no audit, then an explicit retry adds one', () async {
    final repo = MockRequestRepository.withSamplePending()..failUpdate = true;
    final before = await repo.fetchRequestDetail('mock-3');
    await expectLater(repo.updateRequest(_edit()), throwsA(isA<Exception>()));
    final failed = await repo.fetchRequestDetail('mock-3');
    expect(failed.request.title, before.request.title);
    expect(failed.description, before.description);
    expect(failed.history, hasLength(1));

    repo.failUpdate = false;
    await repo.updateRequest(_edit());
    final retried = await repo.fetchRequestDetail('mock-3');
    expect(retried.history, hasLength(2));
    expect(retried.history.last.note, 'Sinh viên chỉnh sửa thông tin yêu cầu');
    expect(retried.history.last.actorId, 'mock-student');
  });
}

EditRepairRequest _edit({
  String requestId = 'mock-3',
  String title = 'Cửa sổ đã chỉnh sửa',
}) => EditRepairRequest(
  requestId: requestId,
  title: title,
  categoryId: 'cat-noithat',
  description: 'Đã bổ sung mô tả sự cố',
);
