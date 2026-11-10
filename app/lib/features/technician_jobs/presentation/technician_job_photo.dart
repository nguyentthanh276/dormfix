// Đóng góp của Nguyễn Tiến Thành (DF-022).
// Phạm vi gồm tải, hiển thị và dọn ảnh đính kèm trong màn chi tiết.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/technician_jobs_repository.dart';
import '../models/technician_job.dart';

/// Holds only a private in-memory image; no reusable URLs or disk cache.
class TechnicianJobPhoto extends StatefulWidget {
  const TechnicianJobPhoto({
    super.key,
    required this.requestId,
    required this.attachment,
    required this.repository,
    required this.onAccessDenied,
  });

  final String requestId;
  final JobAttachment attachment;
  final TechnicianJobsRepository repository;
  final VoidCallback onAccessDenied;

  @override
  State<TechnicianJobPhoto> createState() => _TechnicianJobPhotoState();
}

class _TechnicianJobPhotoState extends State<TechnicianJobPhoto> {
  Uint8List? _bytes;
  MemoryImage? _image;
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant TechnicianJobPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.requestId != widget.requestId ||
        oldWidget.attachment.storagePath != widget.attachment.storagePath ||
        oldWidget.attachment.id != widget.attachment.id) {
      _generation++;
      _loading = false;
      unawaited(_load());
    }
  }

  // DF-022: Xóa ảnh khỏi bộ nhớ đệm và dọn vùng dữ liệu ảnh của widget.
  void _clearImage() {
    final image = _image;
    _image = null;
    if (image != null) unawaited(image.evict());
    _bytes?.fillRange(0, _bytes!.length, 0);
    _bytes = null;
  }

  // DF-022: Tải ảnh theo ID yêu cầu và thông tin ảnh đính kèm.
  Future<void> _load() async {
    if (_loading) return;
    final generation = ++_generation;
    _clearImage();
    setState(() => _loading = true);
    try {
      final bytes = await widget.repository.fetchAttachment(
        widget.requestId,
        widget.attachment,
      );
      if (!mounted || generation != _generation) return;
      // Own this buffer, so disposing it never mutates repository/shared bytes.
      final owned = Uint8List.fromList(bytes);
      setState(() {
        _bytes = owned;
        _image = MemoryImage(owned);
      });
    } on TechnicianJobsFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      // DF-022: Báo màn chi tiết khi không còn quyền tải ảnh.
      if (failure.accessDenied) widget.onAccessDenied();
    } catch (_) {
      // Transport and object paths must not be rendered to the user.
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _clearImage();
    super.dispose();
  }

  Widget _failure() => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image_outlined),
        const SizedBox(height: 8),
        const Text('Không tải được ảnh.', textAlign: TextAlign.center),
        TextButton(
          key: ValueKey('photo-retry-${widget.attachment.id}'),
          onPressed: () => unawaited(_load()),
          child: const Text('Tải lại ảnh'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Semantics(
      label: 'Ảnh đính kèm',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: _loading
              ? const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                )
              : image == null
              ? _failure()
              : Image(
                  image: image,
                  height: 200,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => _failure(),
                ),
        ),
      ),
    );
  }
}
