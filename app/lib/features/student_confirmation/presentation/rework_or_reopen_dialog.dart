import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/student_confirmation_repository.dart';
import '../models/confirmation_input.dart';

class ReworkOrReopenDialog extends StatefulWidget {
  final String requestId;
  final ConfirmationAction
  action; // requestRework (DF-015) hoặc reopenRequest (DF-016)
  final String? requestRoomId;
  final String? currentStudentRoomId;
  final VoidCallback onSuccess;

  const ReworkOrReopenDialog({
    super.key,
    required this.requestId,
    required this.action,
    this.requestRoomId,
    this.currentStudentRoomId,
    required this.onSuccess,
  });

  @override
  State<ReworkOrReopenDialog> createState() => _ReworkOrReopenDialogState();
}

class _ReworkOrReopenDialogState extends State<ReworkOrReopenDialog> {
  final _reasonCtrl = TextEditingController();
  final _repo = StudentConfirmationRepository();
  final _picker = ImagePicker();
  final List<String> _selectedImagePaths = [];
  bool _submitting = false;

  bool get isRework => widget.action == ConfirmationAction.requestRework;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_selectedImagePaths.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chỉ được chọn tối đa 5 hình ảnh.')),
      );
      return;
    }

    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final file = File(picked.path);
      final size = await file.length();
      if (size > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ảnh vượt quá dung lượng cho phép (tối đa 5 MB).'),
            ),
          );
        }
        return;
      }
      setState(() => _selectedImagePaths.add(picked.path));
    }
  }

  Future<void> _submit() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập lý do cụ thể.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      if (isRework) {
        // DF-015
        await _repo.requestRework(
          requestId: widget.requestId,
          reason: reason,
          imagePaths: _selectedImagePaths,
        );
      } else {
        // DF-016
        await _repo.reopenRequest(
          requestId: widget.requestId,
          requestRoomId: widget.requestRoomId ?? '',
          currentStudentRoomId: widget.currentStudentRoomId ?? '',
          reason: reason,
          imagePaths: _selectedImagePaths,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = isRework ? 'Yêu cầu sửa lại' : 'Mở lại yêu cầu sửa chữa';

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Lý do (bắt buộc) *',
                hintText: isRework
                    ? 'Mô tả chi tiết những điểm chưa đạt...'
                    : 'Nêu lý do sự cố phát sinh lại...',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ảnh đính kèm (${_selectedImagePaths.length}/5)',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextButton.icon(
                  onPressed: _selectedImagePaths.length >= 5 || _submitting
                      ? null
                      : _pickImage,
                  icon: const Icon(Icons.add_photo_alternate, size: 18),
                  label: const Text('Thêm ảnh'),
                ),
              ],
            ),
            if (_selectedImagePaths.isNotEmpty)
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImagePaths.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_selectedImagePaths[i]),
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: _submitting
                                ? null
                                : () => setState(
                                    () => _selectedImagePaths.removeAt(i),
                                  ),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(3),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: isRework ? Colors.orange.shade800 : null,
          ),
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isRework ? 'Gửi yêu cầu sửa lại' : 'Xác nhận mở lại'),
        ),
      ],
    );
  }
}
