import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/request_repository.dart';
import '../../models/request_detail.dart';

/// Bytes stay inside the authenticated screen; every load is authorized again.
class RequestPhoto extends StatefulWidget {
  const RequestPhoto({
    super.key,
    required this.repository,
    required this.requestId,
    required this.attachment,
    required this.onAccessDenied,
    this.expanded = false,
    this.onTap,
  });

  final RequestRepository repository;
  final String requestId;
  final RequestAttachment attachment;
  final VoidCallback onAccessDenied;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  State<RequestPhoto> createState() => _RequestPhotoState();
}

class _RequestPhotoState extends State<RequestPhoto>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _accessSubscription;
  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;
  bool _denied = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
    _load();
  }

  void _subscribe() {
    _accessSubscription = widget.repository.accessChanges.listen(
      (_) => _deny(),
      onError: (Object _) => _deny(),
    );
  }

  @override
  void didUpdateWidget(covariant RequestPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.requestId != widget.requestId ||
        oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.storagePath != widget.attachment.storagePath) {
      _accessSubscription?.cancel();
      _clearBytes();
      _denied = false;
      _subscribe();
      _load();
    }
  }

  void _clearBytes() {
    final bytes = _bytes;
    _bytes = null;
    if (bytes != null) unawaited(MemoryImage(bytes).evict());
  }

  void _deny() {
    if (!mounted || _denied) return;
    _generation++;
    setState(() {
      _clearBytes();
      _denied = true;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _denied) widget.onAccessDenied();
    });
  }

  Future<void> _load() async {
    if (_denied) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _clearBytes();
    });
    try {
      final bytes = await widget.repository.fetchAttachment(
        widget.requestId,
        widget.attachment,
      );
      if (!mounted || generation != _generation || _denied) return;
      setState(() => _bytes = bytes);
    } on RequestFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      if (failure.accessDenied) {
        _deny();
      } else {
        setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _denied) return;
    if (state == AppLifecycleState.resumed) {
      _load();
    } else {
      _generation++;
      setState(() {
        _clearBytes();
        _loading = true;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _accessSubscription?.cancel();
    _clearBytes();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    Widget child;
    if (_denied) {
      child = const Center(child: Icon(Icons.lock_outline));
    } else if (_loading) {
      child = const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_failed || bytes == null) {
      child = Center(
        child: IconButton(
          tooltip: 'Thử tải lại ảnh',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      );
    } else {
      child = Image.memory(
        bytes,
        key: ValueKey('request-photo-${widget.attachment.id}'),
        fit: widget.expanded ? BoxFit.contain : BoxFit.cover,
        gaplessPlayback: false,
        excludeFromSemantics: false,
        semanticLabel: 'Ảnh đính kèm yêu cầu',
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
      if (widget.expanded) child = InteractiveViewer(child: child);
    }
    if (widget.expanded) return SizedBox.expand(child: child);
    return Semantics(
      button: true,
      label: 'Mở ảnh đính kèm',
      child: InkWell(
        onTap: _denied ? null : widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 112, height: 92, child: child),
        ),
      ),
    );
  }
}
