import '../../../core/models/app_role.dart';
import '../models/managed_account.dart';
import 'admin_accounts_repository.dart';

/// DF-028/029/030: local demo data for UI checks before Supabase is configured.
class MockAdminAccountsRepository implements AdminAccountsRepository {
  static const _accounts = [
    ManagedAccount(fullName: 'Nguyễn Minh An', identityCode: 'SV001', role: AppRole.student, status: AccountStatus.active),
    ManagedAccount(fullName: 'Trần Thu Bình', identityCode: 'SV002', role: AppRole.student, status: AccountStatus.locked),
    ManagedAccount(fullName: 'Lê Quốc Cường', identityCode: 'SV003', role: AppRole.student, status: AccountStatus.revoked),
    ManagedAccount(fullName: 'Phạm Gia Huy', identityCode: 'SV004', role: AppRole.student, status: AccountStatus.active),
    ManagedAccount(fullName: 'Võ Thành Long', identityCode: 'KTV001', role: AppRole.technician, status: AccountStatus.active),
    ManagedAccount(fullName: 'Đặng Hoàng Nam', identityCode: 'KTV002', role: AppRole.technician, status: AccountStatus.locked),
    ManagedAccount(fullName: 'Bùi Văn Phúc', identityCode: 'KTV003', role: AppRole.technician, status: AccountStatus.revoked),
  ];

  @override
  Future<List<ManagedAccount>> list({required String query, AppRole? role, AccountStatus? status, required int offset, required int limit}) async {
    final needle = _normalize(query.trim());
    final filtered = _accounts.where((account) =>
      (role == null || account.role == role) &&
      (status == null || account.status == status) &&
      (needle.isEmpty || _normalize(account.fullName).contains(needle) || _normalize(account.identityCode).contains(needle))
    ).toList()..sort((a, b) => a.fullName.compareTo(b.fullName));
    return filtered.skip(offset).take(limit).toList(growable: false);
  }

  static String _normalize(String value) {
    const from = 'áàảãạăắằẳẵặâấầẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiii ooooooooooooooooo uuuuuuuuuuu yyyyyd'.replaceAll(' ', '');
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
