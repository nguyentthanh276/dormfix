import 'dart:async';

import 'package:dormfix/core/data/admin_catalog_failure.dart';
import 'package:dormfix/features/admin_rooms/data/admin_room_repository.dart';
import 'package:dormfix/features/admin_rooms/presentation/admin_room_list_screen.dart';
import 'package:dormfix/features/incident_categories/data/incident_category_repository.dart';
import 'package:dormfix/features/incident_categories/models/incident_category_item.dart';
import 'package:dormfix/features/incident_categories/presentation/category_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedRoomRepository extends MockAdminRoomRepository {
  final pending = Completer<void>();
  var attempts = 0;

  @override
  Future<void> addRoom({required String code, required String building}) async {
    if (++attempts == 1) await pending.future;
    await super.addRoom(code: code, building: building);
  }
}

class _DelayedCategoryRepository extends MockIncidentCategoryRepository {
  _DelayedCategoryRepository()
    : super(
        categories: [
          IncidentCategoryItem(
            id: 'test-category',
            name: 'Điện thử nghiệm',
            isActive: true,
            createdAt: DateTime.utc(2026, 11, 10),
          ),
        ],
      );

  final pending = Completer<void>();
  var attempts = 0;

  @override
  Future<void> toggleCategoryStatus(String id, bool currentStatus) async {
    attempts++;
    await pending.future;
    await super.toggleCategoryStatus(id, currentStatus);
  }
}

void main() {
  testWidgets('room editor waits for server and keeps the draft on duplicate', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _DelayedRoomRepository();
    await tester.pumpWidget(
      MaterialApp(home: AdminRoomListScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm phòng'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'A-101');
    await tester.enterText(find.byType(TextFormField).at(1), 'Tòa A');
    await tester.tap(find.text('Lưu'));
    await tester.pump();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(repository.attempts, 1);
    expect(find.text('Phòng A-101'), findsNothing);
    final saveButton = find.descendant(
      of: dialog,
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

    repository.pending.completeError(
      const AdminCatalogFailure('Mã phòng đã tồn tại.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mã phòng đã tồn tại.'), findsOneWidget);
    expect(find.text('A-101'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'A-102');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(find.text('Phòng A-102'), findsOneWidget);
    expect(repository.attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category switch waits for the server then refreshes status', (
    tester,
  ) async {
    final repository = _DelayedCategoryRepository();
    await tester.pumpWidget(
      MaterialApp(home: CategoryListScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    final toggle = find.byType(Switch);
    await tester.tap(toggle);
    await tester.pump();
    expect(repository.attempts, 1);
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(tester.widget<Switch>(toggle).onChanged, isNull);
    repository.pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(find.text('Ngừng sử dụng'), findsOneWidget);
  });
}
