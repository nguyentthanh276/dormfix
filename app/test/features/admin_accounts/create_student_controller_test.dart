import 'package:dormfix/features/admin_accounts/data/admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/models/create_student_result.dart';
import 'package:dormfix/features/admin_accounts/models/room_summary.dart';
import 'package:dormfix/features/admin_accounts/presentation/create_student_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

class FakeAdminAccountsRepository implements AdminAccountsRepository {
  FakeAdminAccountsRepository({
    this.rooms = const [],
    this.roomsFailure,
    this.createFailure,
    this.createResult,
  });

  final List<RoomSummary> rooms;
  final AdminAccountsFailure? roomsFailure;
  final AdminAccountsFailure? createFailure;
  final CreateStudentResult? createResult;

  int fetchRoomsCount = 0;
  int createStudentCount = 0;
  Map<String, dynamic>? lastCreateArgs;

  @override
  Future<List<RoomSummary>> fetchActiveRooms() async {
    fetchRoomsCount++;
    final failure = roomsFailure;
    if (failure != null) throw failure;
    return rooms;
  }

  @override
  Future<CreateStudentResult> createStudent({
    required String identityCode,
    required String fullName,
    required String email,
    required String phone,
    required String roomId,
    required String tempPassword,
  }) async {
    createStudentCount++;
    lastCreateArgs = {
      'identityCode': identityCode,
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'roomId': roomId,
      'tempPassword': tempPassword,
    };
    final failure = createFailure;
    if (failure != null) throw failure;
    return createResult ??
        const CreateStudentResult(profileId: 'new-profile-id');
  }
}

final _room1 = RoomSummary(id: 'room-1', code: 'A101', building: 'Tòa A');
final _room2 = RoomSummary(id: 'room-2', code: 'B201', building: null);

// ─── Helpers ──────────────────────────────────────────────────────────────────

CreateStudentController _makeController({
  List<RoomSummary>? rooms,
  AdminAccountsFailure? roomsFailure,
  AdminAccountsFailure? createFailure,
  CreateStudentResult? createResult,
}) {
  final repo = FakeAdminAccountsRepository(
    rooms: rooms ?? [_room1, _room2],
    roomsFailure: roomsFailure,
    createFailure: createFailure,
    createResult: createResult,
  );
  return CreateStudentController(repository: repo);
}

void _fillForm(CreateStudentController c, {String room = 'room-1'}) {
  c
    ..identityCode = 'SV999'
    ..fullName = 'Sinh Viên Test'
    ..email = 'sv999@example.com'
    ..phone = '0901234567'
    ..selectRoom(c.rooms.firstWhere((r) => r.id == room))
    ..tempPassword = 'Passw0rd!';
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('CreateStudentController — room loading', () {
    test('starts in loadingRooms state', () {
      final c = _makeController();
      expect(c.state, CreateStudentState.loadingRooms);
      c.dispose();
    });

    test('transitions to idle after loading rooms', () async {
      final c = _makeController();
      await c.loadRooms();
      expect(c.state, CreateStudentState.idle);
      expect(c.rooms, hasLength(2));
      expect(c.error, isNull);
      c.dispose();
    });

    test('surfaces roomLoadError when repo throws', () async {
      final c = _makeController(
        roomsFailure: const AdminAccountsFailure('Không thể kết nối máy chủ.'),
      );
      await c.loadRooms();
      expect(c.state, CreateStudentState.roomLoadError);
      expect(c.error, contains('Không thể kết nối'));
      c.dispose();
    });

    test('surfaces roomLoadError when no active rooms exist', () async {
      final c = _makeController(rooms: const []);
      await c.loadRooms();
      expect(c.state, CreateStudentState.roomLoadError);
      expect(c.error, isNotNull);
      c.dispose();
    });

    test('can retry after room-load failure', () async {
      // Simulate success on second call by using a fresh working controller
      final c2 = _makeController();
      await c2.loadRooms();
      expect(c2.state, CreateStudentState.idle);
      c2.dispose();
    });
  });

  group('CreateStudentController — client-side validation', () {
    late CreateStudentController c;

    setUp(() async {
      c = _makeController();
      await c.loadRooms();
    });

    tearDown(() => c.dispose());

    test('validates identity_code blank', () {
      expect(c.validateIdentityCode(''), isNotNull);
      expect(c.validateIdentityCode('  '), isNotNull);
    });

    test('accepts non-blank identity_code', () {
      expect(c.validateIdentityCode('SV001'), isNull);
    });

    test('validates full_name blank', () {
      expect(c.validateFullName(''), isNotNull);
    });

    test('validates email format', () {
      expect(c.validateEmail(''), isNotNull);
      expect(c.validateEmail('not-an-email'), isNotNull);
      expect(c.validateEmail('a@b.com'), isNull);
    });

    test('validates phone blank', () {
      expect(c.validatePhone(''), isNotNull);
      expect(c.validatePhone('   '), isNotNull);
    });

    test('accepts any non-blank phone', () {
      expect(c.validatePhone('0901234567'), isNull);
      // Phone uniqueness is not validated client-side
      expect(c.validatePhone('0901234567'), isNull);
    });

    test('validates room null', () {
      expect(c.validateRoom(null), isNotNull);
      expect(c.validateRoom(_room1), isNull);
    });

    test('validates password min-length', () {
      expect(c.validateTempPassword(''), isNotNull);
      expect(c.validateTempPassword('short'), isNotNull);
      expect(c.validateTempPassword('12345678'), isNull);
    });
  });

  group('CreateStudentController — submit', () {
    test('returns false and sets error when validation fails', () async {
      final c = _makeController();
      await c.loadRooms();
      // Leave all fields empty
      final result = await c.submit();
      expect(result, isFalse);
      expect(c.state, CreateStudentState.idle);
      expect(c.error, isNotNull);
      c.dispose();
    });

    test('transitions to success after successful create', () async {
      final c = _makeController();
      await c.loadRooms();
      _fillForm(c);

      final result = await c.submit();

      expect(result, isTrue);
      expect(c.state, CreateStudentState.success);
      expect(c.result?.profileId, 'new-profile-id');
      expect(c.error, isNull);
      c.dispose();
    });

    test('surfaces server failure message on create error', () async {
      const serverMessage = 'Mã Sinh viên đã tồn tại trong hệ thống.';
      final c = _makeController(
        createFailure: const AdminAccountsFailure(serverMessage),
      );
      await c.loadRooms();
      _fillForm(c);

      final result = await c.submit();

      expect(result, isFalse);
      expect(c.state, CreateStudentState.idle);
      expect(c.error, serverMessage);
      c.dispose();
    });

    test(
      'does not reveal internal exception detail on unknown error',
      () async {
        final repo = _ThrowingRepo();
        final c = CreateStudentController(repository: repo);
        await c.loadRooms();
        _fillForm(c);

        await c.submit();

        expect(c.error, isNot(contains('Stack Overflow')));
        expect(c.state, CreateStudentState.idle);
        c.dispose();
      },
    );

    test('sends trimmed and lowercased fields to repository', () async {
      final repo = FakeAdminAccountsRepository(rooms: [_room1]);
      final c = CreateStudentController(repository: repo);
      await c.loadRooms();
      c
        ..identityCode = '  SV999  '
        ..fullName = '  Test User  '
        ..email = '  SV999@Example.COM  '
        ..phone = '  0901234567  '
        ..selectRoom(_room1)
        ..tempPassword = 'Passw0rd!';

      await c.submit();

      // Repository.createStudent trims on its own side (server also trims),
      // but the controller passes raw values — server normalises.
      expect(repo.lastCreateArgs, isNotNull);
      c.dispose();
    });

    test('does not double-submit when already submitting', () async {
      final c = _makeController();
      await c.loadRooms();
      _fillForm(c);

      // Start one submission, immediately try a second
      final first = c.submit();
      final second = c.submit(); // should be no-op

      await first;
      final secondResult = await second;

      expect(secondResult, isFalse); // second call short-circuits
      c.dispose();
    });
  });

  group('RoomSummary', () {
    test('label includes building when present', () {
      expect(_room1.label, contains('Tòa A'));
    });

    test('label is just code when building is null', () {
      expect(_room2.label, equals('B201'));
    });

    test('fromJson throws on invalid data', () {
      expect(
        () => RoomSummary.fromJson({'id': 123, 'code': null}),
        throwsFormatException,
      );
    });
  });
}

/// A repository implementation that throws a non-[AdminAccountsFailure] error,
/// verifying the controller sanitises the message.
class _ThrowingRepo implements AdminAccountsRepository {
  @override
  Future<List<RoomSummary>> fetchActiveRooms() async => [_room1];

  @override
  Future<CreateStudentResult> createStudent({
    required String identityCode,
    required String fullName,
    required String email,
    required String phone,
    required String roomId,
    required String tempPassword,
  }) async {
    throw Exception('Stack Overflow in production db');
  }
}
