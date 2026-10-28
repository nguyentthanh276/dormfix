import 'package:flutter/material.dart';
import '../data/student_confirmation_repository.dart';

class ConfirmFixedDialog extends StatefulWidget {
  final String requestId;
  final VoidCallback onSuccess;

  const ConfirmFixedDialog({
    super.key,
    required this.requestId,
    required this.onSuccess,
  });

  @override
  State<ConfirmFixedDialog> createState() => _ConfirmFixedDialogState();
}

class _ConfirmFixedDialogState extends State<ConfirmFixedDialog> {
  final _noteController = TextEditingController();
  final _repo = StudentConfirmationRepository();
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Xác nhận đã khắc phục'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bạn có chắc chắn sự cố đã được sửa chữa đạt yêu cầu?'),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Nhận xét (không bắt buộc)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
        FilledButton(
          onPressed: _submitting
              ? null
              : () async {
                  setState(() => _submitting = true);
                  try {
                    await _repo.confirmFixed(
                      requestId: widget.requestId,
                      note: _noteController.text,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      widget.onSuccess();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _submitting = false);
                  }
                },
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Xác nhận hoàn tất'),
        ),
      ],
    );
  }
}