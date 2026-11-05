import '../../../core/models/app_role.dart';
import '../../admin_rooms/models/admin_room.dart';
import '../../profile/models/phone_rules.dart';
import '../models/managed_account.dart';
import 'admin_accounts_repository.dart';

/// Local demo data for UI checks before Supabase is configured.
class MockAdminAccountsRepository implements AdminAccountsRepository {
  const MockAdminAccountsRepository();

  static final List<ManagedAccount> _accounts = [
    const ManagedAccount(
      fullName: 'Nguyễn Minh An',
      identityCode: 'SV001',
      role: AppRole.student,
      status: AccountStatus.active,
    ),
    const ManagedAccount(
      fullName: 'Trần Thu Bình',
      identityCode: 'SV002',
      role: AppRole.student,
      status: AccountStatus.locked,
    ),
    const ManagedAccount(
      fullName: 'Lê Quốc Cường',
      identityCode: 'SV003',
      role: AppRole.student,
      status: AccountStatus.revoked,
    ),
    const ManagedAccount(
      fullName: 'Phạm Gia Huy',
      identityCode: 'SV004',
      role: AppRole.student,
      status: AccountStatus.active,
    ),
    const ManagedAccount(
      fullName: 'Võ Thành Long',
      identityCode: 'KTV001',
      role: AppRole.technician,
      status: AccountStatus.active,
    ),
    const ManagedAccount(
      fullName: 'Đặng Hoàng Nam',
      identityCode: 'KTV002',
      role: AppRole.technician,
      status: AccountStatus.locked,
    ),
    const ManagedAccount(
      fullName: 'Bùi Văn Phúc',
      identityCode: 'KTV003',
      role: AppRole.technician,
      status: AccountStatus.revoked,
    ),
  ];

  static final Set<String> _emails = {
    'sv001@example.com',
    'sv002@example.com',
    'sv003@example.com', // Đã thu hồi
    'sv004@example.com',
    'ktv001@example.com',
    'ktv002@example.com',
    'ktv003@example.com', // Đã thu hồi
  };

  static final Map<String, String> _studentPhones = {
    'SV001': '0901111111',
    'SV002': '0902222222',
    'SV004': '0904444444',
  };

  static final Map<String, String> _studentRoomIds = {
    'SV001': 'room-1',
    'SV002': 'room-3',
    'SV004': 'room-2',
  };

  static const Map<String, Set<String>> _unfinishedTechnicianJobs = {
    'KTV001': {'assigned'},
    'KTV002': {'awaiting_rework'},
  };

  static final List<AdminRoom> _mockRooms = [
    AdminRoom(
      id: 'room-1',
      code: 'DEMO-A101',
      building: 'Tòa A',
      isActive: true,
      studentNames: ['Nguyễn Minh An'],
    ),
    AdminRoom(
      id: 'room-2',
      code: 'A2-305',
      building: 'Tòa A',
      isActive: true,
      studentNames: ['Phạm Gia Huy'],
    ),
    AdminRoom(
      id: 'room-3',
      code: 'B1-112',
      building: 'Tòa B',
      isActive: true,
      studentNames: [],
    ),
    AdminRoom(
      id: 'room-4',
      code: 'C3-210',
      building: 'Tòa C',
      isActive: false,
      studentNames: [],
    ),
  ];

  @override
  Future<List<ManagedAccount>> list({
    required String query,
    AppRole? role,
    AccountStatus? status,
    required int offset,
    required int limit,
  }) async {
    final needle = _normalize(query.trim());
    final filtered =
        _accounts
            .where(
              (account) =>
                  (role == null || account.role == role) &&
                  (status == null || account.status == status) &&
                  (needle.isEmpty ||
                      _normalize(account.fullName).contains(needle) ||
                      _normalize(account.identityCode).contains(needle)),
            )
            .toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
    return filtered.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<CreatedStudentResult> createStudent({
    required String identityCode,
    required String fullName,
    required String email,
    required String phone,
    required String roomId,
    String? temporaryPassword,
  }) async {
    final trimmedCode = identityCode.trim();
    final trimmedName = fullName.trim();
    final trimmedEmail = email.trim().toLowerCase();
    final trimmedPhone = phone.trim();

    // 1. Kiểm tra trường bắt buộc
    if (trimmedCode.isEmpty) {
      throw const AdminAccountsFailure('Mã Sinh viên không được để trống.');
    }
    if (trimmedName.isEmpty) {
      throw const AdminAccountsFailure('Họ tên Sinh viên không được để trống.');
    }
    if (trimmedEmail.isEmpty) {
      throw const AdminAccountsFailure('Email không được để trống.');
    }
    final emailRegex = RegExp(
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
    );
    if (!emailRegex.hasMatch(trimmedEmail)) {
      throw const AdminAccountsFailure('Email không đúng định dạng.');
    }
    if (trimmedPhone.isEmpty) {
      throw const AdminAccountsFailure('Số điện thoại không được để trống.');
    }
    final phoneRegex = RegExp(r'^(0|\+84)[0-9]{9}$');
    if (!phoneRegex.hasMatch(trimmedPhone)) {
      throw const AdminAccountsFailure('Số điện thoại không đúng định dạng.');
    }
    if (roomId.trim().isEmpty) {
      throw const AdminAccountsFailure('Vui lòng chọn phòng cho Sinh viên.');
    }

    // 2. Kiểm tra phòng tồn tại và đang hoạt động
    final room = _mockRooms.cast<AdminRoom?>().firstWhere(
      (r) => r?.id == roomId,
      orElse: () => null,
    );
    if (room == null) {
      throw const AdminAccountsFailure('Phòng không tồn tại.');
    }
    if (!room.isActive) {
      throw const AdminAccountsFailure(
        'Chỉ được gắn Sinh viên vào phòng đang hoạt động.',
      );
    }

    // 3. Kiểm tra tính duy nhất (toàn hệ thống, kể cả tài khoản đã thu hồi)
    final codeExists = _accounts.any(
      (a) => a.identityCode.trim().toLowerCase() == trimmedCode.toLowerCase(),
    );
    if (codeExists) {
      throw const AdminAccountsFailure(
        'Mã Sinh viên đã tồn tại trên hệ thống.',
      );
    }

    final emailExists = _emails.any(
      (e) => e.trim().toLowerCase() == trimmedEmail,
    );
    if (emailExists) {
      throw const AdminAccountsFailure('Email đã tồn tại trên hệ thống.');
    }

    // 4. Mật khẩu tạm
    final tempPassword =
        (temporaryPassword != null && temporaryPassword.trim().length >= 6)
        ? temporaryPassword.trim()
        : 'DF@${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';

    final newStudent = ManagedAccount(
      fullName: trimmedName,
      identityCode: trimmedCode,
      role: AppRole.student,
      status: AccountStatus.active,
    );
    _accounts.add(newStudent);
    _emails.add(trimmedEmail);
    _studentPhones[trimmedCode] = trimmedPhone;
    _studentRoomIds[trimmedCode] = room.id;

    return CreatedStudentResult(
      id: 'mock-sv-${DateTime.now().millisecondsSinceEpoch}',
      identityCode: trimmedCode,
      fullName: trimmedName,
      email: trimmedEmail,
      phone: trimmedPhone,
      role: 'student',
      status: 'active',
      mustChangePassword: true,
      temporaryPassword: tempPassword,
      roomId: room.id,
      roomCode: room.code,
      roomBuilding: room.building,
    );
  }

  @override
  Future<CreatedTechnicianResult> createTechnician({
    required String identityCode,
    required String fullName,
    required String email,
    required String phone,
    String? temporaryPassword,
  }) async {
    final trimmedCode = identityCode.trim();
    final trimmedName = fullName.trim();
    final trimmedEmail = email.trim().toLowerCase();
    final trimmedPhone = phone.trim();

    if (trimmedCode.isEmpty) {
      throw const AdminAccountsFailure('Mã Kỹ thuật viên không được để trống.');
    }
    if (trimmedName.isEmpty) {
      throw const AdminAccountsFailure(
        'Họ tên Kỹ thuật viên không được để trống.',
      );
    }
    if (trimmedEmail.isEmpty) {
      throw const AdminAccountsFailure('Email không được để trống.');
    }
    final emailRegex = RegExp(
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
    );
    if (!emailRegex.hasMatch(trimmedEmail)) {
      throw const AdminAccountsFailure('Email không đúng định dạng.');
    }
    if (trimmedPhone.isEmpty) {
      throw const AdminAccountsFailure('Số điện thoại không được để trống.');
    }
    final phoneRegex = RegExp(r'^(0|\+84)[0-9]{9}$');
    if (!phoneRegex.hasMatch(trimmedPhone)) {
      throw const AdminAccountsFailure('Số điện thoại không đúng định dạng.');
    }

    if (_accounts.any(
      (account) =>
          account.identityCode.trim().toLowerCase() ==
          trimmedCode.toLowerCase(),
    )) {
      throw const AdminAccountsFailure(
        'Mã Kỹ thuật viên đã tồn tại trên hệ thống.',
      );
    }
    if (_emails.any((value) => value.toLowerCase() == trimmedEmail)) {
      throw const AdminAccountsFailure('Email đã tồn tại trên hệ thống.');
    }

    final tempPassword =
        (temporaryPassword != null && temporaryPassword.trim().length >= 6)
        ? temporaryPassword.trim()
        : 'DF@${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    _accounts.add(
      ManagedAccount(
        fullName: trimmedName,
        identityCode: trimmedCode,
        role: AppRole.technician,
        status: AccountStatus.active,
      ),
    );
    _emails.add(trimmedEmail);

    return CreatedTechnicianResult(
      id: 'mock-ktv-${DateTime.now().millisecondsSinceEpoch}',
      identityCode: trimmedCode,
      fullName: trimmedName,
      email: trimmedEmail,
      phone: trimmedPhone,
      status: 'active',
      mustChangePassword: true,
      temporaryPassword: tempPassword,
    );
  }

  @override
  Future<StudentAccountEditDetails> getStudentForEdit(
    String identityCode,
  ) async {
    final index = _accounts.indexWhere(
      (account) =>
          account.identityCode.toLowerCase() ==
          identityCode.trim().toLowerCase(),
    );
    if (index < 0 || _accounts[index].role != AppRole.student) {
      throw const AdminAccountsFailure(
        'Không tìm thấy Sinh viên có thể cập nhật.',
      );
    }
    final account = _accounts[index];
    if (account.status == AccountStatus.revoked) {
      throw const AdminAccountsFailure(
        'Không thể cập nhật tài khoản đã thu hồi.',
      );
    }
    final roomId = _studentRoomIds[account.identityCode] ?? '';
    final room = _mockRooms.cast<AdminRoom?>().firstWhere(
      (item) => item?.id == roomId,
      orElse: () => null,
    );
    return StudentAccountEditDetails(
      fullName: account.fullName,
      phone: _studentPhones[account.identityCode] ?? '',
      roomId: roomId,
      roomCode: room?.code ?? '',
      roomBuilding: room?.building ?? '',
    );
  }

  @override
  Future<void> updateStudent({
    required String identityCode,
    required String fullName,
    required String phone,
    required String roomId,
  }) async {
    final normalizedCode = identityCode.trim().toLowerCase();
    final index = _accounts.indexWhere(
      (account) => account.identityCode.toLowerCase() == normalizedCode,
    );
    if (index < 0 || _accounts[index].role != AppRole.student) {
      throw const AdminAccountsFailure(
        'Không tìm thấy Sinh viên có thể cập nhật.',
      );
    }
    if (_accounts[index].status == AccountStatus.revoked) {
      throw const AdminAccountsFailure(
        'Không thể cập nhật tài khoản đã thu hồi.',
      );
    }
    if (fullName.trim().isEmpty) {
      throw const AdminAccountsFailure('Họ tên Sinh viên không được để trống.');
    }
    if (PhoneRules.validatePhone(phone) != null) {
      throw const AdminAccountsFailure('Số điện thoại không đúng định dạng.');
    }
    final room = _mockRooms.cast<AdminRoom?>().firstWhere(
      (item) => item?.id == roomId,
      orElse: () => null,
    );
    if (room == null || !room.isActive) {
      throw const AdminAccountsFailure(
        'Chỉ được chuyển Sinh viên vào phòng đang hoạt động.',
      );
    }

    final account = _accounts[index];
    _accounts[index] = ManagedAccount(
      fullName: fullName.trim(),
      identityCode: account.identityCode,
      role: account.role,
      status: account.status,
    );
    _studentPhones[account.identityCode] = phone.trim();
    _studentRoomIds[account.identityCode] = room.id;
  }

  @override
  Future<void> revokeAccount({
    required String identityCode,
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const AdminAccountsFailure('Vui lòng nhập lý do thu hồi.');
    }
    final index = _accounts.indexWhere(
      (account) =>
          account.identityCode.toLowerCase() ==
          identityCode.trim().toLowerCase(),
    );
    if (index < 0 || _accounts[index].role == AppRole.admin) {
      throw const AdminAccountsFailure('Không tìm thấy tài khoản hợp lệ.');
    }
    final account = _accounts[index];
    if (account.status == AccountStatus.revoked) {
      throw const AdminAccountsFailure('Tài khoản đã được thu hồi.');
    }
    if (account.role == AppRole.technician &&
        (_unfinishedTechnicianJobs[account.identityCode]?.isNotEmpty ??
            false)) {
      throw const AdminAccountsFailure(
        'Không thể thu hồi Kỹ thuật viên còn công việc chưa hoàn tất.',
      );
    }
    _accounts[index] = ManagedAccount(
      fullName: account.fullName,
      identityCode: account.identityCode,
      role: account.role,
      status: AccountStatus.revoked,
    );
  }

  @override
  Future<void> restoreAccount({
    required String identityCode,
    String? roomId,
  }) async {
    final index = _accounts.indexWhere(
      (account) =>
          account.identityCode.toLowerCase() ==
          identityCode.trim().toLowerCase(),
    );
    if (index < 0 || _accounts[index].role == AppRole.admin) {
      throw const AdminAccountsFailure('Không tìm thấy tài khoản hợp lệ.');
    }
    final account = _accounts[index];
    if (account.status != AccountStatus.revoked) {
      throw const AdminAccountsFailure('Tài khoản chưa bị thu hồi.');
    }
    if (account.role == AppRole.student) {
      if (roomId == null || roomId.trim().isEmpty) {
        throw const AdminAccountsFailure(
          'Vui lòng chọn phòng đang hoạt động cho Sinh viên.',
        );
      }
      final room = _mockRooms.cast<AdminRoom?>().firstWhere(
        (item) => item?.id == roomId,
        orElse: () => null,
      );
      if (room == null || !room.isActive) {
        throw const AdminAccountsFailure(
          'Chỉ được khôi phục Sinh viên vào phòng đang hoạt động.',
        );
      }
      _studentRoomIds[account.identityCode] = room.id;
    } else {
      if (roomId != null) {
        throw const AdminAccountsFailure(
          'Kỹ thuật viên không được gắn phòng KTX.',
        );
      }
      if (_unfinishedTechnicianJobs[account.identityCode]?.isNotEmpty ??
          false) {
        throw const AdminAccountsFailure(
          'Không thể khôi phục Kỹ thuật viên còn công việc chưa hoàn tất.',
        );
      }
    }
    _accounts[index] = ManagedAccount(
      fullName: account.fullName,
      identityCode: account.identityCode,
      role: account.role,
      status: AccountStatus.active,
    );
  }

  @override
  Future<ResetPasswordResult> resetPassword({
    required String identityCode,
  }) async {
    final index = _accounts.indexWhere(
      (account) =>
          account.identityCode.toLowerCase() ==
          identityCode.trim().toLowerCase(),
    );
    if (index < 0 || _accounts[index].role == AppRole.admin) {
      throw const AdminAccountsFailure('Không tìm thấy tài khoản hợp lệ.');
    }
    final account = _accounts[index];
    final temporaryPassword =
        'DF@${DateTime.now().microsecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    return ResetPasswordResult(
      id: 'mock-account-${account.identityCode}',
      identityCode: account.identityCode,
      fullName: account.fullName,
      role: account.role.databaseValue,
      status: account.status.databaseValue,
      mustChangePassword: true,
      temporaryPassword: temporaryPassword,
    );
  }

  @override
  Future<List<AdminRoom>> getActiveRooms() async {
    return _mockRooms.where((r) => r.isActive).toList(growable: false);
  }

  static String _normalize(String value) {
    const from =
        'áàảãạăắằẳẵặâấầẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ';
    const to =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final lower = value.toLowerCase();
    final out = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      final index = from.indexOf(char);
      out.write(index < 0 ? char : to[index]);
    }
    return out.toString();
  }
}
