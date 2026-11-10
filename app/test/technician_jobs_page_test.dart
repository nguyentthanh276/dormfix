import 'dart:async';
import 'dart:typed_data';

import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/technician_jobs/data/technician_jobs_repository.dart';
import 'package:dormfix/features/technician_jobs/models/technician_job.dart';
import 'package:dormfix/features/technician_jobs/presentation/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/technician_jobs_fakes.dart';

typedef _TestBody = Future<void> Function(
  WidgetTester tester,
  TechnicianTestAuthRepository auth,
  TechnicianTestJobsRepository jobs,
);

void _test(String name, _TestBody body) {
  testWidgets(name, (tester) async {
    final auth = TechnicianTestAuthRepository();
    final jobs = TechnicianTestJobsRepository();
    try {
      await body(tester, auth, jobs);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await auth.dispose();
    }
  });
}

Future<void> _mount(
  WidgetTester tester,
  TechnicianTestAuthRepository auth,
  TechnicianTestJobsRepository? jobs, {
  bool settle = true,
}) async {
  await tester.pumpWidget(
    DormFixApp(authRepository: auth, technicianJobsRepository: jobs),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _openDetail(WidgetTester tester) async {
  await tester.tap(find.text('Vòi nước phòng A101 rò rỉ'));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    250,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 35,
  );
  await tester.pumpAndSettle();
}

void main() {
  _test('missing repository preserves the role Home and a friendly message', (
    tester,
    auth,
    jobs,
  ) async {
    await _mount(tester, auth, null);
    expect(find.text('Công việc được giao'), findsOneWidget);
    expect(find.text('Vai trò: Kỹ thuật viên'), findsOneWidget);
    expect(
      find.textContaining('Danh sách công việc chưa sẵn sàng'),
      findsOneWidget,
    );
    expect(find.text('Cá nhân'), findsOneWidget);
  });

  _test('list shows loading and an empty response with refresh', (
    tester,
    auth,
    jobs,
  ) async {
    final pending = Completer<List<TechnicianJob>>();
    jobs.loadJobs = () => pending.future;
    await _mount(tester, auth, jobs, settle: false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('Bạn chưa được phân công công việc nào.'), findsOneWidget);
    jobs.loadJobs = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('DF000001'), findsOneWidget);
  });

  _test('list retry recovers and preserves server ordering and rework status', (
    tester,
    auth,
    jobs,
  ) async {
    jobs.loadJobs = () async =>
        throw const TechnicianJobsFailure('Không thể tải công việc.');
    await _mount(tester, auth, jobs);
    expect(find.text('Không thể tải công việc.'), findsOneWidget);
    jobs.loadJobs = null;
    jobs.jobs = [
      technicianJob(id: 'job-2', title: 'Công việc mới nhất'),
      technicianJob(),
    ];
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('DF000002')).dy,
      lessThan(tester.getTopLeft(find.text('DF000001')).dy),
    );
    expect(find.text('Chờ xử lý lại'), findsNWidgets(2));
    jobs.jobs = [];
    await tester.drag(
      find.byKey(const Key('technician-jobs-list')),
      const Offset(0, 350),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bạn chưa được phân công công việc nào.'), findsOneWidget);
  });

  _test('detail renders every read-only section and protected photo group', (
    tester,
    auth,
    jobs,
  ) async {
    jobs.detail = technicianDetail(withPhotos: true);
    await _mount(tester, auth, jobs);
    await _openDetail(tester);
    expect(find.text('Chi tiết công việc'), findsOneWidget);
    await _scrollTo(tester, 'Sinh viên liên hệ');
    expect(find.text('Họ tên: Sinh viên Nguyễn An'), findsOneWidget);
    expect(find.text('Điện thoại: 0901234567'), findsOneWidget);
    await _scrollTo(tester, 'Ảnh sự cố');
    await _scrollTo(tester, 'Kết quả sửa chữa');
    await _scrollTo(tester, 'Đã thay ống nối dưới bồn rửa.');
    await _scrollTo(tester, 'Phản hồi của sinh viên');
    await _scrollTo(tester, 'Nước vẫn rò ở đầu nối.');
    await _scrollTo(tester, 'Lịch sử xử lý');
    await _scrollTo(tester, 'Cần kiểm tra lại đầu nối.');
    await _scrollTo(tester, 'Lịch sử phân công');
    await _scrollTo(tester, 'Lý do chuyển: Phân công theo chuyên môn nước.');
    expect(
      jobs.attachmentCalls,
      containsAll(['request-photo', 'result-photo', 'feedback-photo']),
    );
    expect(find.text('Bắt đầu xử lý'), findsNothing);
    expect(find.text('Gửi kết quả'), findsNothing);
    expect(find.text('Chuyển công việc'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _test('completed and cancelled details remain explicitly read-only', (
    tester,
    auth,
    jobs,
  ) async {
    jobs.detail = technicianDetail(status: RepairStatus.completed);
    await _mount(tester, auth, jobs);
    await _openDetail(tester);
    expect(
      find.text('Công việc đã hoàn tất. Thông tin chỉ để xem.'),
      findsOneWidget,
    );
    jobs.detail = technicianDetail(status: RepairStatus.cancelled);
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(
      find.text('Công việc đã hủy. Thông tin chỉ để xem.'),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
  });

  _test('detail loading, error and retry do not expose a previous payload', (
    tester,
    auth,
    jobs,
  ) async {
    final pending = Completer<TechnicianJobDetail>();
    jobs.loadDetail = () => pending.future;
    await _mount(tester, auth, jobs);
    await tester.tap(find.text('Vòi nước phòng A101 rò rỉ'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(
      const TechnicianJobsFailure('Không thể tải chi tiết.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Không thể tải chi tiết.'), findsOneWidget);
    jobs.loadDetail = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Chi tiết công việc · Chỉ xem'), findsOneWidget);
  });

  _test(
    'transfer denial clears detail and stale list card; retry can recover',
    (tester, auth, jobs) async {
      await _mount(tester, auth, jobs);
      await _openDetail(tester);
      jobs.loadDetail = () async => throw const TechnicianJobsFailure(
        'Không còn phân công.',
        accessDenied: true,
      );
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Bạn không còn quyền xem công việc này.'),
        findsOneWidget,
      );
      expect(find.text('Vòi nước phòng A101 rò rỉ'), findsNothing);
      expect(find.byType(Image), findsNothing);
      jobs.loadDetail = null;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('Vòi nước phòng A101 rò rỉ'), findsOneWidget);
    },
  );

  _test(
    'photo access denial invalidates the complete detail, not just the image',
    (tester, auth, jobs) async {
      jobs.detail = technicianDetail(withPhotos: true);
      jobs.loadAttachment = (_) async => throw const TechnicianJobsFailure(
        'Không còn quyền xem ảnh.',
        accessDenied: true,
      );
      await _mount(tester, auth, jobs);
      await _openDetail(tester);
      if (find
          .textContaining('Bạn không còn quyền xem công việc này.')
          .evaluate()
          .isEmpty) {
        await _scrollTo(tester, 'Ảnh sự cố');
      }
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Bạn không còn quyền xem công việc này.'),
        findsOneWidget,
      );
      expect(find.text('Họ tên: Sinh viên Nguyễn An'), findsNothing);
      expect(find.text('Vòi nước phòng A101 rò rỉ'), findsNothing);
      expect(find.byType(Image), findsNothing);
    },
  );

  _test(
    'a failed photo supports a scoped retry without leaking storage paths',
    (tester, auth, jobs) async {
      jobs.detail = technicianDetail(withPhotos: true);
      jobs.loadAttachment = (_) async =>
          throw const TechnicianJobsFailure('private path');
      await _mount(tester, auth, jobs);
      await _openDetail(tester);
      await _scrollTo(tester, 'Ảnh sự cố');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('photo-retry-request-photo')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('private path'), findsNothing);
      jobs.loadAttachment = null;
      final count = jobs.attachmentCalls.length;
      await tester.tap(find.byKey(const ValueKey('photo-retry-request-photo')));
      await tester.pumpAndSettle();
      expect(jobs.attachmentCalls.length, greaterThan(count));
      expect(find.byType(Image), findsWidgets);
    },
  );

  _test(
    'logout from detail clears its local history and Back cannot reopen it',
    (tester, auth, jobs) async {
      await _mount(tester, auth, jobs);
      await _openDetail(tester);
      await tester
          .widget<TechnicianHomePage>(find.byType(TechnicianHomePage))
          .controller
          .signOut();
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập DormFix'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết công việc'), findsNothing);
      expect(find.text('Vòi nước phòng A101 rò rỉ'), findsNothing);
    },
  );

  _test('session expiry clears photos and ignores a late detail response', (
    tester,
    auth,
    jobs,
  ) async {
    final pending = Completer<TechnicianJobDetail>();
    jobs.loadDetail = () => pending.future;
    await _mount(tester, auth, jobs);
    await tester.tap(find.text('Vòi nước phòng A101 rò rỉ'));
    await tester.pump();
    auth.hasSession = false;
    await tester.pumpAndSettle();
    pending.complete(technicianDetail(withPhotos: true));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập DormFix'), findsOneWidget);
    expect(find.text('Chi tiết công việc'), findsNothing);
    expect(jobs.attachmentCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  _test('identity switch clears old detail and loads the new account list', (
    tester,
    auth,
    jobs,
  ) async {
    await _mount(tester, auth, jobs);
    await _openDetail(tester);
    final controller = tester
        .widget<TechnicianHomePage>(find.byType(TechnicianHomePage))
        .controller;
    auth.profile = technicianProfile(id: 'technician-2');
    jobs.jobs = [technicianJob(id: 'job-2', title: 'Công việc tài khoản mới')];
    await controller.signIn(email: 'new@example.com', password: 'temporary');
    await tester.pumpAndSettle();
    expect(find.text('Chi tiết công việc'), findsNothing);
    expect(find.text('Công việc tài khoản mới'), findsOneWidget);
    expect(find.text('Vòi nước phòng A101 rò rỉ'), findsNothing);
  });

  _test('periodic revalidation never overlaps and resume rechecks permission', (
    tester,
    auth,
    jobs,
  ) async {
    await _mount(tester, auth, jobs);
    await _openDetail(tester);
    final pending = Completer<TechnicianJobDetail>();
    jobs.loadDetail = () => pending.future;
    await tester.pump(const Duration(seconds: 30));
    expect(jobs.detailCalls, 2);
    jobs.loadDetail = () async => throw const TechnicianJobsFailure(
      'Đã chuyển công việc.',
      accessDenied: true,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(jobs.detailCalls, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(jobs.detailCalls, 2);
    pending.complete(technicianDetail());
    await tester.pumpAndSettle();
    expect(jobs.detailCalls, 3);
    expect(
      find.textContaining('Bạn không còn quyền xem công việc này.'),
      findsOneWidget,
    );
  });

  _test('a late photo cannot restore sensitive data after expiry', (
    tester,
    auth,
    jobs,
  ) async {
    final pending = Completer<Uint8List>();
    jobs.detail = technicianDetail(withPhotos: true);
    jobs.loadAttachment = (_) => pending.future;
    await _mount(tester, auth, jobs);
    await tester.tap(find.text('Vòi nước phòng A101 rò rỉ'));
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Ảnh sự cố'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    auth.hasSession = false;
    await tester.pumpAndSettle();
    pending.complete(technicianPng());
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập DormFix'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _test('an old account list response cannot replace the new account data', (
    tester,
    auth,
    jobs,
  ) async {
    final pending = Completer<List<TechnicianJob>>();
    jobs.loadJobs = () => pending.future;
    await _mount(tester, auth, jobs, settle: false);
    await tester.pump();
    final controller = tester
        .widget<TechnicianHomePage>(find.byType(TechnicianHomePage))
        .controller;
    auth.profile = technicianProfile(id: 'technician-2');
    jobs.loadJobs = null;
    jobs.jobs = [
      technicianJob(id: 'job-2', title: 'Công việc của kỹ thuật viên mới'),
    ];
    await controller.signIn(email: 'new@example.com', password: 'temporary');
    await tester.pumpAndSettle();
    pending.complete([technicianJob()]);
    await tester.pumpAndSettle();
    expect(find.text('Công việc của kỹ thuật viên mới'), findsOneWidget);
    expect(find.text('Vòi nước phòng A101 rò rỉ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _test('expiry evicts rendered private images and clears their owned bytes', (
    tester,
    auth,
    jobs,
  ) async {
    jobs.detail = technicianDetail(withPhotos: true);
    await _mount(tester, auth, jobs);
    await _openDetail(tester);
    await _scrollTo(tester, 'Ảnh sự cố');
    await tester.pumpAndSettle();
    final images = tester
        .widgetList<Image>(find.byType(Image))
        .map((widget) => widget.image)
        .whereType<MemoryImage>()
        .toList();
    expect(images, isNotEmpty);
    expect(images.first.bytes.any((byte) => byte != 0), isTrue);
    auth.hasSession = false;
    await tester.pumpAndSettle();
    for (final image in images) {
      expect(image.bytes.every((byte) => byte == 0), isTrue);
      final key = await image.obtainKey(ImageConfiguration.empty);
      final status = PaintingBinding.instance.imageCache.statusForKey(key);
      expect(status.live || status.keepAlive || status.pending, isFalse);
    }
    expect(find.byType(Image), findsNothing);
  });

  _test('a denied photo invalidates an overlapping detail refresh response', (
    tester,
    auth,
    jobs,
  ) async {
    final photo = Completer<Uint8List>();
    final detail = Completer<TechnicianJobDetail>();
    jobs.detail = technicianDetail(withPhotos: true);
    jobs.loadAttachment = (_) => photo.future;
    await _mount(tester, auth, jobs);
    await tester.tap(find.text('Vòi nước phòng A101 rò rỉ'));
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Ảnh sự cố'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(jobs.attachmentCalls, isNotEmpty);
    jobs.loadDetail = () => detail.future;
    await tester.pump(const Duration(seconds: 15));
    photo.completeError(
      const TechnicianJobsFailure(
        'Quyền ảnh đã bị thu hồi.',
        accessDenied: true,
      ),
    );
    await tester.pumpAndSettle();
    detail.complete(technicianDetail(withPhotos: true));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Bạn không còn quyền xem công việc này.'),
      findsOneWidget,
    );
    expect(find.text('Vòi nước phòng A101 rò rỉ'), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  _test('Vietnamese list and long detail fit a 320px viewport', (
    tester,
    auth,
    jobs,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, auth, jobs);
    expect(tester.takeException(), isNull);
    await _openDetail(tester);
    await _scrollTo(tester, 'Lịch sử phân công');
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Công việc được giao'), findsOneWidget);
  });
}
