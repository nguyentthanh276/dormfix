import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/technician_job.dart';
import '../models/technician_workflow.dart';

typedef TechnicianResultImagePicker = Future<List<XFile>> Function();

/// An in-memory draft, scoped to the currently authorized detail page.
class TechnicianResultForm extends StatefulWidget {
  const TechnicianResultForm({
    super.key,
    required this.job,
    required this.onSubmit,
    required this.onCancel,
    this.busy = false,
    this.retryOnly = false,
    this.pickImages,
    this.onPickingChanged,
  });

  final TechnicianJob job;
  final Future<void> Function(TechnicianResultSubmission) onSubmit;
  final VoidCallback onCancel;
  final bool busy;
  final bool retryOnly;
  final TechnicianResultImagePicker? pickImages;
  final ValueChanged<bool>? onPickingChanged;

  @override
  State<TechnicianResultForm> createState() => _TechnicianResultFormState();
}

class _TechnicianResultFormState extends State<TechnicianResultForm>
    with AutomaticKeepAliveClientMixin {
  final _content = TextEditingController();
  final _photos = <TechnicianResultPhoto>[];
  TechnicianResultSubmission? _submission;
  String? _error;
  bool _picking = false;
  bool _sending = false;

  bool get _busy => widget.busy || _picking || _sending;

  @override
  bool get wantKeepAlive => true;

  Future<void> _pick() async {
    if (_busy || widget.retryOnly) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    widget.onPickingChanged?.call(true);
    try {
      final files =
          await (widget.pickImages?.call() ?? ImagePicker().pickMultiImage());
      if (!mounted) return;
      if (_photos.length + files.length >
          TechnicianResultSubmission.maxPhotos) {
        throw const TechnicianWorkflowFailure(
          'Chỉ được đính kèm tối đa 5 ảnh.',
        );
      }
      final picked = <TechnicianResultPhoto>[];
      for (final file in files) {
        final length = await file.length();
        if (!mounted) return;
        if (length > TechnicianResultPhoto.maxBytes) {
          throw const TechnicianWorkflowFailure('Mỗi ảnh tối đa 5 MB.');
        }
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        picked.add(
          TechnicianResultPhoto.fromBytes(name: file.name, bytes: bytes),
        );
      }
      if (!mounted) return;
      setState(() {
        _photos.addAll(picked);
        _submission = null;
      });
    } on TechnicianWorkflowFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không đọc được ảnh. Vui lòng chọn lại.');
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
        widget.onPickingChanged?.call(false);
      }
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    try {
      // Keep the same ID and bytes for a user-triggered uncertain retry.
      _submission ??= TechnicianResultSubmission.create(
        job: widget.job,
        content: _content.text,
        photos: _photos,
      );
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() {
        _sending = true;
        _error = null;
      });
      await widget.onSubmit(_submission!);
    } on TechnicianWorkflowFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _content.dispose();
    for (final photo in _photos) {
      unawaited(MemoryImage(photo.bytes).evict());
    }
    _photos.clear();
    _submission = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Card(
      key: const Key('technician-result-form'),
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Kết quả sửa chữa mới',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('technician-result-content'),
              controller: _content,
              enabled: !_busy && !widget.retryOnly,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Nội dung kết quả *',
                hintText: 'Mô tả việc đã xử lý và kết quả sửa chữa',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _submission = null,
            ),
            const SizedBox(height: 12),
            Text('Ảnh kết quả (${_photos.length}/5) · Không bắt buộc'),
            const Text('JPG, PNG hoặc WebP; mỗi ảnh tối đa 5 MB.'),
            for (final photo in _photos)
              Padding(
                key: ValueKey('draft-photo-${photo.id}'),
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Image.memory(
                      photo.bytes,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(
                        width: 72,
                        height: 72,
                        child: Icon(Icons.image_outlined),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(photo.name)),
                    IconButton(
                      tooltip: 'Xóa ảnh ${photo.name}',
                      onPressed: _busy || widget.retryOnly
                          ? null
                          : () {
                              setState(() {
                                unawaited(MemoryImage(photo.bytes).evict());
                                _photos.remove(photo);
                                _submission = null;
                              });
                            },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              key: const Key('technician-add-result-photos'),
              onPressed: _busy || widget.retryOnly || _photos.length >= 5
                  ? null
                  : _pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_picking ? 'Đang đọc ảnh...' : 'Thêm ảnh'),
            ),
            if (widget.retryOnly)
              const Text(
                'Chưa xác nhận được lần gửi trước. Gửi lại sẽ dùng cùng nội dung và ảnh để tránh tạo kết quả trùng.',
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('technician-submit-result'),
              onPressed: _busy ? null : _submit,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _sending
                    ? 'Đang gửi...'
                    : widget.retryOnly
                    ? 'Gửi lại cùng kết quả'
                    : 'Gửi kết quả',
              ),
            ),
            TextButton(
              onPressed: _busy || widget.retryOnly ? null : widget.onCancel,
              child: const Text('Hủy nhập kết quả'),
            ),
          ],
        ),
      ),
    );
  }
}
