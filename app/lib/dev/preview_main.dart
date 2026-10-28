import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/models/repair_status.dart';
import '../core/theme/app_theme.dart';
import '../features/student_confirmation/models/confirmation_input.dart';
import '../features/student_confirmation/presentation/confirm_fixed_dialog.dart';
import '../features/student_confirmation/presentation/rework_or_reopen_dialog.dart';
import '../features/student_requests/models/repair_request.dart';
import '../features/student_requests/presentation/status_chip.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  if (config.isConfigured) {
    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
      );
    } catch (e) {
      debugPrint('Supabase init note: $e');
    }
  }

  runApp(
    MaterialApp(
      title: 'DormFix - Xem thử Sinh viên',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const StudentDevPreviewScreen(),
    ),
  );
}

class StudentDevPreviewScreen extends StatefulWidget {
  const StudentDevPreviewScreen({super.key});

  @override
  State<StudentDevPreviewScreen> createState() =>
      _StudentDevPreviewScreenState();
}

class _StudentDevPreviewScreenState extends State<StudentDevPreviewScreen> {
  final String studentRoomCode = 'DEMO-A101';
  final String studentRoomId = 'demo-room-id';

  late List<RepairRequest> _sampleRequests;

  @override
  void initState() {
    super.initState();
    _loadSampleData();
  }

  void _loadSampleData() {
    _sampleRequests = [
      RepairRequest(
        id: 'req-001',
        requestCode: 'DF000001',
        title: 'Bóng đèn huỳnh quang nhấp nháy (Thợ đã sửa xong)',
        categoryName: 'Điện',
        roomCode: studentRoomCode,
        status:
            RepairStatus.awaitingConfirmation, // Dùng để test DF-014 và DF-015
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      ),
      RepairRequest(
        id: 'req-002',
        requestCode: 'DF000002',
        title: 'Khóa cửa ban công bị kẹt (Đã hoàn tất trước đó)',
        categoryName: 'Nội thất',
        roomCode: studentRoomCode,
        status: RepairStatus.completed, // Dùng để test DF-016
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      RepairRequest(
        id: 'req-003',
        requestCode: 'DF000003',
        title: 'Vòi xịt vệ sinh rò nước',
        categoryName: 'Nước',
        roomCode: studentRoomCode,
        status: RepairStatus.inProgress,
        createdAt: DateTime.now().subtract(const Duration(hours: 12)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yêu cầu sửa chữa'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.school, color: Colors.deepOrange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sinh viên: Nguyễn Văn An - Phòng: $studentRoomCode',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._sampleRequests.map((req) => _buildRequestCard(req)),
        ],
      ),
    );
  }

  Widget _buildRequestCard(RepairRequest req) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  req.requestCode,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
                const Spacer(),
                StatusChip(status: req.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              req.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '${req.categoryName} · Phòng ${req.roomCode}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const Divider(height: 24),

            if (req.status == RepairStatus.awaitingConfirmation) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange.shade800,
                      ),
                      icon: const Icon(Icons.replay, size: 18),
                      label: const Text('Yêu cầu sửa lại'),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => ReworkOrReopenDialog(
                            requestId: req.id,
                            action:
                                ConfirmationAction.requestRework, // [DF-015]
                            onSuccess: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Đã gửi yêu cầu thợ sửa lại thành công!',
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Đã khắc phục'),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => ConfirmFixedDialog(
                            requestId: req.id, // [DF-014]
                            onSuccess: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Đã xác nhận hoàn tất sửa chữa!',
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ] else if (req.status == RepairStatus.completed) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Mở lại yêu cầu sự cố này'),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => ReworkOrReopenDialog(
                        requestId: req.id,
                        action: ConfirmationAction.reopenRequest, // [DF-016]
                        requestRoomId: studentRoomId,
                        currentStudentRoomId: studentRoomId,
                        onSuccess: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã mở lại yêu cầu thành công!'),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ] else ...[
              Text(
                'Đơn đang được xử lý, chưa cần xác nhận.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
