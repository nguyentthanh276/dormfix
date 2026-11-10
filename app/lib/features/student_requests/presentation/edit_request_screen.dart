import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/dormfix_app_bar.dart';

import 'package:image_picker/image_picker.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_view.dart';
import '../data/request_repository.dart';
import '../models/edit_repair_request.dart';
import '../models/incident_category.dart';
import '../models/new_repair_request.dart';
import '../models/request_detail.dart';
import '../models/request_rules.dart';
import '../models/student_request_id.dart';
import '../models/student_request_mutation.dart';
import 'widgets/category_tile.dart';
import 'widgets/request_photo.dart';

/// DF-011: Form chỉnh sửa yêu cầu sửa chữa khi ở trạng thái Chờ tiếp nhận (pending).
class EditRequestScreen extends StatefulWidget {
  final RequestRepository repository;
  final RequestDetail detail;
  final VoidCallback? onUpdated;
  final Future<List<AttachmentDraft>> Function()? pickAttachments;

  const EditRequestScreen({
    super.key,
    required this.repository,
    required this.detail,
    this.onUpdated,
    this.pickAttachments,
  });

  @override
  State<EditRequestScreen> createState() => _EditRequestScreenState();
}

class _EditRequestScreenState extends State<EditRequestScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  final _picker = ImagePicker();

  List<IncidentCategory> _categories = [];
  String? _categoryId;
  String? _categoryError;

  late final List<String> _keptPhotos;
  final List<AttachmentDraft> _newImages = [];

  bool _loadingCategories = false;
  bool _submitting = false;
  bool _picking = false;
  bool _uncertain = false;
  bool _denied = false;
  bool _conflict = false;
  bool _foreground = true;
  bool _verified = true;
  bool _saved = false;
  bool _leaving = false;
  bool _confirmedLeave = false;
  Future<bool>? _accessCheck;
  StreamSubscription<void>? _accessSubscription;
  StudentRequestMutation? _mutation;
  int _identity = 0;
  String? _errorText;

  bool get _versioned => widget.repository.supportsVersionedMutations;
  bool get _locked =>
      _submitting ||
      _picking ||
      _uncertain ||
      _denied ||
      _conflict ||
      !_verified;
  int get _totalImagesCount => _keptPhotos.length + _newImages.length;
  bool get _dirty =>
      _titleCtrl.text != widget.detail.request.title ||
      _descCtrl.text != widget.detail.description ||
      _categoryId != _initialCategoryId ||
      _keptPhotos.length != widget.detail.studentPhotos.length ||
      _newImages.isNotEmpty;
  String? _initialCategoryId;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.detail.request.title);
    _descCtrl = TextEditingController(text: widget.detail.description);
    _keptPhotos = List<String>.from(widget.detail.studentPhotos);
    _titleCtrl.addListener(_draftChanged);
    _descCtrl.addListener(_draftChanged);
    WidgetsBinding.instance.addObserver(this);
    _accessSubscription = widget.repository.accessChanges.listen(
      (_) => _deny(),
      onError: (Object _) => _deny(),
    );
    _loadCategories();
  }

  void _draftChanged() {
    if (mounted && !_denied) setState(() {});
  }

  @override
  void didUpdateWidget(covariant EditRequestScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.detail.request.id != widget.detail.request.id) {
      _deny();
    }
  }

  @override
  void dispose() {
    _identity++;
    WidgetsBinding.instance.removeObserver(this);
    _accessSubscription?.cancel();
    _clearImages();
    _titleCtrl.removeListener(_draftChanged);
    _descCtrl.removeListener(_draftChanged);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final identity = _identity;
    setState(() {
      _loadingCategories = true;
      _errorText = null;
    });
    try {
      final result = await widget.repository.fetchCategories();
      if (mounted && identity == _identity) {
        setState(() {
          _categories = result;
          final initialId = widget.detail.categoryId;
          final current = _categories.where(
            (c) => initialId == null
                ? c.name == widget.detail.request.categoryName
                : c.id == initialId,
          );
          if (current.isNotEmpty) {
            _categoryId = _initialCategoryId = current.first.id;
          }
        });
      }
    } on RequestFailure catch (failure) {
      if (!mounted || identity != _identity) return;
      if (failure.accessDenied) {
        _deny();
      } else {
        setState(() => _errorText = failure.message);
      }
    } catch (_) {
      if (mounted && identity == _identity) {
        setState(() => _errorText = 'Không tải được loại sự cố. Hãy thử lại.');
      }
    } finally {
      if (mounted && identity == _identity) {
        setState(() => _loadingCategories = false);
      }
    }
  }

  void _clearImages() {
    for (final photo in _newImages) {
      unawaited(MemoryImage(photo.bytes).evict());
    }
    _newImages.clear();
  }

  void _deny() {
    if (!mounted || _denied) return;
    _identity++;
    setState(() {
      _denied = true;
      _titleCtrl.clear();
      _descCtrl.clear();
      _categories = [];
      _keptPhotos.clear();
      _clearImages();
      _mutation = null;
      _submitting = false;
      _errorText =
          'Bạn không còn quyền chỉnh sửa yêu cầu này. Vui lòng đăng nhập lại.';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_versioned || !mounted || _denied) return;
    if (state == AppLifecycleState.resumed) {
      setState(() => _foreground = true);
      if (!_submitting) unawaited(_revalidate());
    } else {
      setState(() {
        _foreground = false;
        _verified = false;
      });
    }
  }

  Future<bool> _revalidate() {
    if (_denied || _conflict) return Future.value(false);
    return _accessCheck ??= _checkAccess().whenComplete(
      () => _accessCheck = null,
    );
  }

  Future<bool> _checkAccess() async {
    final identity = _identity;
    setState(() => _verified = false);
    try {
      final current = await widget.repository.fetchRequestDetail(
        widget.detail.request.id,
      );
      if (!mounted || identity != _identity) return false;
      if (_saved) {
        if (_foreground) _finish();
        return true;
      }
      if (!_uncertain &&
          (!current.canEdit ||
              current.request.status != RepairStatus.pending ||
              current.request.version != widget.detail.request.version)) {
        setState(() {
          _conflict = true;
          _errorText =
              'Yêu cầu đã thay đổi. Hãy tải lại chi tiết trước khi chỉnh sửa.';
        });
        return false;
      }
      setState(() => _verified = _foreground);
      return true;
    } on RequestFailure catch (failure) {
      if (!mounted || identity != _identity) return false;
      if (failure.accessDenied) {
        _deny();
      } else {
        setState(() => _errorText = failure.message);
      }
      return false;
    } catch (_) {
      if (mounted && identity == _identity) {
        setState(
          () => _errorText =
              'Không thể kiểm tra quyền truy cập. Vui lòng thử lại.',
        );
      }
      return false;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<List<AttachmentDraft>> _pickNative() async {
    final files = await _picker.pickMultiImage();
    final picked = <AttachmentDraft>[];
    for (final file in files) {
      if (!mounted || _denied) return [];
      final problem = RequestRules.checkNewImage(
        currentCount: _totalImagesCount + picked.length,
        sizeBytes: await file.length(),
        fileName: file.name,
      );
      if (problem != null) throw RequestFailure(problem);
      if (!mounted || _denied) return [];
      picked.add(
        AttachmentDraft(name: file.name, bytes: await file.readAsBytes()),
      );
    }
    return picked;
  }

  Future<void> _pickImages() async {
    if (_locked || !_foreground) return;
    final identity = _identity;
    setState(() => _picking = true);
    try {
      final photos = await (widget.pickAttachments?.call() ?? _pickNative());
      if (!mounted || identity != _identity) return;
      if (_versioned && !await _revalidate()) return;
      if (!mounted || identity != _identity) return;
      for (final photo in photos) {
        final problem = RequestRules.checkNewImage(
          currentCount: _totalImagesCount,
          sizeBytes: photo.bytes.length,
          fileName: photo.name,
        );
        if (problem != null || photo.bytes.isEmpty) {
          _showMessage(problem ?? 'Ảnh không hợp lệ.');
          continue;
        }
        setState(() => _newImages.add(photo));
      }
    } on RequestFailure catch (failure) {
      if (mounted && identity == _identity) _showMessage(failure.message);
    } catch (_) {
      if (mounted && identity == _identity) {
        _showMessage('Không thể chọn ảnh. Vui lòng thử lại.');
      }
    } finally {
      if (mounted && identity == _identity) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting ||
        _picking ||
        _denied ||
        _conflict ||
        !_foreground ||
        !_verified) {
      return;
    }
    FocusScope.of(context).unfocus();

    final categoryError = RequestRules.validateCategory(_categoryId);
    setState(() => _categoryError = categoryError);
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk || categoryError != null) return;

    final identity = _identity;
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      if (_versioned) {
        await _submitVersioned();
      } else {
        await widget.repository.updateRequest(
          EditRepairRequest(
            requestId: widget.detail.request.id,
            title: _titleCtrl.text.trim(),
            categoryId: _categoryId!,
            description: _descCtrl.text.trim(),
            keepPhotos: List.of(_keptPhotos),
            newAttachments: List.of(_newImages),
          ),
        );
      }
      if (!mounted || identity != _identity) return;
      _saved = true;
      if (_foreground) {
        if (_verified) {
          _finish();
        } else {
          await _revalidate();
        }
      }
    } on RequestFailure catch (failure) {
      if (!mounted || identity != _identity) return;
      if (failure.accessDenied) {
        _deny();
      } else {
        setState(() {
          _uncertain = failure.uncertain;
          _conflict = failure.conflict;
          _errorText = failure.uncertain
              ? 'Chưa xác nhận được thay đổi. Bấm kiểm tra lại để tránh lưu trùng.'
              : failure.message;
        });
      }
    } catch (_) {
      if (mounted && identity == _identity) {
        setState(() {
          _uncertain = _versioned && _mutation != null;
          _errorText = _uncertain
              ? 'Chưa xác nhận được thay đổi. Bấm kiểm tra lại để tránh lưu trùng.'
              : 'Không thể lưu thay đổi. Vui lòng thử lại.';
        });
      }
    } finally {
      if (mounted && identity == _identity) setState(() => _submitting = false);
    }
  }

  Future<void> _submitVersioned() async {
    final request = widget.detail.request;
    if (!_uncertain || _mutation == null) {
      final attachmentIds = <String>[];
      for (final path in _keptPhotos) {
        final attachment = _attachmentFor(path);
        if (attachment == null) {
          throw const RequestFailure(
            'Ảnh cũ chưa tải được. Hãy tải lại chi tiết trước khi lưu.',
            conflict: true,
          );
        }
        attachmentIds.add(attachment.id);
      }
      _mutation = StudentRequestMutation.edit(
        actionId: createStudentRequestId(),
        requestId: request.id,
        expectedVersion: request.version,
        title: _titleCtrl.text,
        categoryId: _categoryId!,
        description: _descCtrl.text,
        keepAttachmentIds: attachmentIds,
        attachments: _newImages,
      );
    }
    final mutation = _mutation!;
    final receipt = await widget.repository.submitMutation(mutation);
    if (receipt.requestId != request.id ||
        receipt.actionId != mutation.actionId ||
        receipt.version != request.version + 1 ||
        receipt.status != RepairStatus.pending ||
        receipt.feedbackId != null) {
      throw const RequestFailure(
        'Chưa xác nhận được thay đổi.',
        uncertain: true,
      );
    }
  }

  RequestAttachment? _attachmentFor(String path) {
    for (final attachment in widget.detail.attachments) {
      if (attachment.storagePath == path &&
          attachment.resultId == null &&
          attachment.feedbackId == null) {
        return attachment;
      }
    }
    return null;
  }

  void _finish() {
    widget.onUpdated?.call();
    if (!mounted) return;
    _showMessage('Đã cập nhật yêu cầu sửa chữa');
    Navigator.of(context).pop(true);
  }

  Future<void> _leave() async {
    if (_submitting || (_accessCheck != null && !_denied) || _leaving) return;
    if (!_versioned || _denied || _conflict || (!_dirty && !_uncertain)) {
      Navigator.of(context).pop();
      return;
    }
    _leaving = true;
    final discard = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(
          _uncertain ? 'Kiểm tra lại chi tiết?' : 'Bỏ thay đổi đang nhập?',
        ),
        content: Text(
          _uncertain
              ? 'Thay đổi có thể đã được lưu. Hãy kiểm tra chi tiết trước khi sửa lại.'
              : 'Nội dung chưa lưu sẽ bị bỏ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Tiếp tục nhập'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_uncertain ? 'Xem chi tiết' : 'Bỏ thay đổi'),
          ),
        ],
      ),
    );
    _leaving = false;
    if (!mounted || discard != true) return;
    setState(() => _confirmedLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop:
          _confirmedLeave ||
          (!_submitting &&
              (_accessCheck == null || _denied) &&
              (!_versioned ||
                  _denied ||
                  _conflict ||
                  (!_dirty && !_uncertain))),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: DormFixAppBar(
          title: 'Chỉnh sửa yêu cầu',
          leading: BackButton(onPressed: _leave),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_denied || _conflict) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorText!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _leave,
                child: const Text('Quay lại chi tiết'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_foreground || _accessCheck != null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_verified) {
      return ErrorView(
        message: _errorText ?? 'Cần kiểm tra lại quyền truy cập.',
        onRetry: _revalidate,
      );
    }
    if (_loadingCategories) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_categories.isEmpty) {
      return ErrorView(
        message: _errorText ?? 'Chưa có loại sự cố nào.',
        onRetry: _loadCategories,
      );
    }
    return _buildForm();
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    ),
  );

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _label('Phòng'),
          TextFormField(
            initialValue: widget.detail.request.roomCode,
            readOnly: true,
            decoration: const InputDecoration(
              filled: true,
              fillColor: AppColors.fieldBg,
              prefixIcon: Icon(Icons.meeting_room_outlined),
            ),
          ),
          _label('Tiêu đề *'),
          TextFormField(
            key: const Key('student-edit-title'),
            controller: _titleCtrl,
            enabled: !_locked,
            validator: RequestRules.validateTitle,
            decoration: const InputDecoration(
              hintText: 'Tóm tắt sự cố (ví dụ: Vòi nước rò rỉ)',
              prefixIcon: Icon(Icons.title),
            ),
          ),
          _label('Loại sự cố *'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cat in _categories)
                CategoryTile(
                  category: cat,
                  selected: _categoryId == cat.id,
                  onTap: () {
                    if (_locked) return;
                    setState(() {
                      _categoryId = cat.id;
                      _categoryError = null;
                    });
                  },
                ),
            ],
          ),
          if (_categoryError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _categoryError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          _label('Mô tả chi tiết *'),
          TextFormField(
            key: const Key('student-edit-description'),
            controller: _descCtrl,
            enabled: !_locked,
            maxLines: 4,
            validator: RequestRules.validateDescription,
            decoration: const InputDecoration(
              hintText: 'Mô tả vị trí, hiện tượng, mức độ nghiêm trọng...',
              alignLabelWithHint: true,
            ),
          ),
          _label(
            'Ảnh đính kèm ($_totalImagesCount/${RequestRules.maxImages}, mỗi ảnh tối đa ${RequestRules.maxImageMb} MB)',
          ),
          _buildImages(),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _submitting || _picking ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_uncertain ? 'Kiểm tra lại' : 'Lưu thay đổi'),
          ),
        ],
      ),
    );
  }

  Widget _buildImages() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      // Ảnh cũ đã đính kèm
      for (var i = 0; i < _keptPhotos.length; i++)
        Stack(
          clipBehavior: Clip.none,
          children: [
            if (_attachmentFor(_keptPhotos[i]) case final attachment?)
              RequestPhoto(
                key: ValueKey(attachment.id),
                repository: widget.repository,
                requestId: widget.detail.request.id,
                attachment: attachment,
                onAccessDenied: _deny,
              )
            else
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppColors.fieldBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withAlpha(100)),
                ),
                child: const Center(
                  child: Icon(
                    Icons.image_outlined,
                    color: AppColors.primary,
                    size: 32,
                  ),
                ),
              ),
            _removePhoto(
              key: ValueKey('student-edit-remove-existing-$i'),
              onPressed: () => setState(() => _keptPhotos.removeAt(i)),
            ),
          ],
        ),
      // Ảnh mới chọn
      for (var i = 0; i < _newImages.length; i++)
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _newImages[i].bytes,
                width: 84,
                height: 84,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 84,
                  height: 84,
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
            _removePhoto(
              key: ValueKey('student-edit-remove-new-$i'),
              onPressed: () => setState(() {
                unawaited(MemoryImage(_newImages[i].bytes).evict());
                _newImages.removeAt(i);
              }),
            ),
          ],
        ),
      if (_totalImagesCount < RequestRules.maxImages)
        InkWell(
          key: const Key('student-edit-add-photos'),
          onTap: _locked ? null : _pickImages,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.add_a_photo_outlined,
              color: AppColors.primary,
            ),
          ),
        ),
    ],
  );

  Widget _removePhoto({required Key key, required VoidCallback onPressed}) =>
      Positioned(
        right: 0,
        top: 0,
        child: IconButton(
          key: key,
          tooltip: 'Xóa ảnh',
          onPressed: _locked ? null : onPressed,
          icon: const Icon(Icons.close),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
          ),
        ),
      );
}
