import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/models/repair_status.dart';
import '../core/theme/app_theme.dart';
import '../features/admin_requests/models/technician_info.dart';
import '../features/admin_requests/presentation/admin_shell_screen.dart';
import '../features/student_requests/models/repair_request.dart';
import '../features/technician_jobs/presentation/technician_shell_screen.dart';

RepairRequest _r(
  int n,
  String title,
  String category,
  String room,
  RepairStatus status,
  int hoursAgo,
) => RepairRequest(
  id: 'mock-$n',
  requestCode: 'DF${n.toString().padLeft(6, '0')}',
  title: title,
  categoryName: category,
  roomCode: room,
  status: status,
  createdAt: DateTime.now().subtract(Duration(hours: hoursAgo)),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final config = AppConfig.fromEnvironment();
    final url = config.isConfigured
        ? config.supabaseUrl
        : 'https://nxobutgnhceyabjbiiya.supabase.co';
    final anonKey = config.isConfigured
        ? config.supabasePublishableKey
        : 'sb_publishable_8qBgRmWg83Xow5zO8iXSkg_D_qANsCF';

    await Supabase.initialize(url: url, publishableKey: anonKey);
  } catch (e) {
    debugPrint('Supabase init warning: $e');
  }

  final requests = [
    _r(1, 'Hỏng bóng đèn', 'Điện', 'A2-305', RepairStatus.pending, 2),
    _r(2, 'Rò nước bồn rửa', 'Nước', 'B1-112', RepairStatus.assigned, 30),
    _r(3, 'Quạt trần kêu to', 'Điện', 'A2-305', RepairStatus.inProgress, 50),
    _r(
      4,
      'Cửa tủ gãy bản lề',
      'Nội thất',
      'B1-112',
      RepairStatus.completed,
      90,
    ),
    _r(5, 'Wi-Fi yếu', 'Khác', 'A2-305', RepairStatus.awaitingConfirmation, 70),
    _r(6, 'Ổ cắm không điện', 'Điện', 'C3-210', RepairStatus.cancelled, 120),
  ];
  const technicians = [
    TechnicianInfo(
      id: 't1',
      name: 'Lê Văn Cường',
      phone: '0987 111 222',
      activeJobs: 2,
    ),
    TechnicianInfo(
      id: 't2',
      name: 'Phạm Minh Đức',
      phone: '0987 333 444',
      activeJobs: 1,
    ),
  ];
  const role = String.fromEnvironment('ROLE', defaultValue: 'admin');

  runApp(
    MaterialApp(
      title: 'DormFix - Admin Preview',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: role == 'technician'
          ? TechnicianShellScreen(
              jobs: requests.where((r) => r.id != 'mock-1').toList(),
              name: 'Lê Văn Cường',
              phone: '0987 111 222',
              onSignOut: () {},
            )
          : AdminShellScreen(
              requests: requests,
              technicians: technicians,
              name: 'Ban Quản lý KTX',
              onSignOut: () {},
            ),
    ),
  );
}
