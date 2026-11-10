import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/repair_status.dart';
import '../../../core/widgets/dormfix_app_bar.dart';
import '../../../core/widgets/error_view.dart';
import '../../student_requests/data/request_repository.dart';
import '../../student_requests/models/new_repair_request.dart';
import '../../student_requests/models/request_detail.dart';
import '../../student_requests/models/request_rules.dart';
import '../../student_requests/models/student_request_id.dart';
import '../../student_requests/models/student_request_mutation.dart';
import '../models/student_confirmation_submission.dart';

enum _ReasonAction { confirm, rework, cancel, reopen }

/// An explicit student action with an optional or required reason.
class StudentResultActionForm extends StatefulWidget {
  const StudentResultActionForm({
    super.key,
    required this.repository,
    required this.detail,
    required StudentResultAction this.action,
    this.pickAttachments,
  }) : _mutationAction = null;

  const StudentResultActionForm.cancel({
    super.key,
    required this.repository,
    required this.detail,
  }) : action = null,
       pickAttachments = null,
       _mutationAction = _ReasonAction.cancel;

  const StudentResultActionForm.reopen({
    super.key,
    required this.repository,
    required this.detail,
    this.pickAttachments,
  }) : action = null,
       _mutationAction = _ReasonAction.reopen;

  final RequestRepository repository;
  final RequestDetail detail;
  final StudentResultAction? action;
  final _ReasonAction? _mutationAction;
  final Future<List<AttachmentDraft>> Function()? pickAttachments;

  @override
  State<StudentResultActionForm> createState() =>
      _StudentResultActionFormState();
}

class _StudentResultActionFormState extends State<StudentResultActionForm>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();
  final _photos = <AttachmentDraft>[];
  StreamSubscription<void>? _accessSubscription;
  StudentConfirmationSubmission? _submission;
  StudentRequestMutation? _mutation;
  StudentConfirmationReceipt? _pendingReceipt;
  Future<bool>? _accessCheck;
  String? _error;
  bool _submitting = false;
  bool _picking = false;
  bool _checking = false;
  bool _uncertain = false;
  bool _denied = false;
  bool _conflict = false;
  bool _foreground = true;
  bool _accessVerified = true;
  bool _allowPop = false;
  bool _confirmingLeave = false;
  int _identityGeneration = 0;

  _ReasonAction get _action =>
      widget._mutationAction ??
      (widget.action == StudentResultAction.requestRework
          ? _ReasonAction.rework
          : _ReasonAction.confirm);
  bool get _allowsPhotos =>
      _action == _ReasonAction.rework || _action == _ReasonAction.reopen;
  bool get _hasDraft => _note.text.isNotEmpty || _photos.isNotEmpty;
  bool get _locked =>
      _submitting ||
      _uncertain ||
      _picking ||
      _checking ||
      _denied ||
      _conflict ||
      !_accessVerified;
  String get _title => switch (_action) {
    _ReasonAction.confirm => 'Xác nhận đã khắc phục',
    _ReasonAction.rework => 'Yêu cầu sửa lại',
    _ReasonAction.cancel => 'Hủy yêu cầu',
    _ReasonAction.reopen => 'Mở lại yêu cầu',
  };
  String get _instructions => switch (_action) {
    _ReasonAction.confirm =>
      'Chỉ xác nhận sau khi bạn đã kiểm tra sự cố được khắc phục.',
    _ReasonAction.rework =>
      'Mô tả phần chưa được khắc phục để kỹ thuật viên tiếp tục xử lý.',
    _ReasonAction.cancel => 'Vui lòng cho biết lý do bạn muốn hủy yêu cầu này.',
    _ReasonAction.reopen => 'Mô tả sự cố tái diễn. Yêu cầu sẽ quay về Chờ tiếp nhận để Admin phân công lại.',
  };
  String get _noteLabel => switch (_action) {
    _ReasonAction.confirm => 'Nhận xét (không bắt buộc)',
    _ReasonAction.rework => 'Lý do sửa lại *',
    _ReasonAction.cancel => 'Lý do hủy *',
    _ReasonAction.reopen => 'Lý do mở lại *',
  };
  String get _emptyReason => switch (_action) {
    _ReasonAction.confirm => '',
    _ReasonAction.rework => 'Vui lòng nhập lý do sửa lại.',
    _ReasonAction.cancel => 'Vui lòng nhập lý do hủy.',
    _ReasonAction.reopen => 'Vui lòng nhập lý do mở lại.',
  };
  String get _submitLabel => switch (_action) {
    _ReasonAction.confirm => _title,
    _ReasonAction.rework => 'Gửi yêu cầu sửa lại',
    _ReasonAction.cancel => 'Xác nhận hủy',
    _ReasonAction.reopen => 'Gửi yêu cầu mở lại',
  };
  RepairStatus get _resultStatus => switch (_action) {
    _ReasonAction.confirm => RepairStatus.completed,
    _ReasonAction.rework => RepairStatus.awaitingRework,
    _ReasonAction.cancel => RepairStatus.cancelled,
    _ReasonAction.reopen => RepairStatus.pending,
  };

  bool _isEligible(RequestDetail detail) => switch (_action) {
    _ReasonAction.confirm || _ReasonAction.rework =>
      detail.request.status == RepairStatus.awaitingConfirmation,
    _ReasonAction.cancel =>
      detail.canCancel &&
          (detail.request.status == RepairStatus.pending ||
              detail.request.status == RepairStatus.assigned),
    _ReasonAction.reopen =>
      detail.request.status == RepairStatus.completed && detail.canReopen,
  };

  void _clearSubmission() {
    _submission = null;
    _mutation = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _note.addListener(_draftChanged);
    _accessSubscription = widget.repository.accessChanges.listen(
      (_) => _deny(),
      onError: (Object _) => _deny(),
    );
  }

  void _draftChanged() {
    if (!mounted) return;
    setState(() {
      if (!_uncertain && !_submitting) _clearSubmission();
    });
  }

  @override
  void didUpdateWidget(covariant StudentResultActionForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.detail.request.id != widget.detail.request.id ||
        oldWidget.action != widget.action ||
        oldWidget._mutationAction != widget._mutationAction) {
      _deny();
    }
  }

  void _clearPhotos() {
    for (final photo in _photos) {
      unawaited(MemoryImage(photo.bytes).evict());
    }
    _photos.clear();
  }

  void _deny() {
    if (!mounted || _denied) return;
    _identityGeneration++;
    _note.clear();
    setState(() {
      _clearPhotos();
      _clearSubmission();
      _pendingReceipt = null;
      _submitting = false;
      _uncertain = false;
      _denied = true;
      _checking = false;
      _error = 'Bạn không còn quyền xử lý yêu cầu này. Vui lòng đăng nhập lại.';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      setState(() => _foreground = true);
      if (!_submitting && !_denied) unawaited(_revalidate());
    } else {
      setState(() {
        _foreground = false;
        _accessVerified = false;
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
    final generation = _identityGeneration;
    setState(() => _checking = true);
    try {
      final detail = await widget.repository.fetchRequestDetail(
        widget.detail.request.id,
      );
      if (!mounted || generation != _identityGeneration || _denied) {
        return false;
      }
      if (_pendingReceipt != null) {
        if (_foreground) _finish(_pendingReceipt!);
        return true;
      }
      if (!_uncertain &&
          (!_isEligible(detail) ||
              detail.request.version != widget.detail.request.version)) {
        setState(() {
          _conflict = true;
          _error =
              'Yêu cầu đã thay đổi. Hãy tải lại chi tiết trước khi thao tác.';
        });
        return false;
      }
      setState(() => _accessVerified = true);
      return true;
    } on RequestFailure catch (failure) {
      if (!mounted || generation != _identityGeneration) return false;
      if (failure.accessDenied) {
        _deny();
      } else {
        setState(() => _error = failure.message);
      }
      return false;
    } catch (_) {
      if (mounted && generation == _identityGeneration) {
        setState(
          () => _error = 'Không thể kiểm tra quyền truy cập. Vui lòng thử lại.',
        );
      }
      return false;
    } finally {
      if (mounted && generation == _identityGeneration) {
        setState(() => _checking = false);
      }
    }
  }

  Future<List<AttachmentDraft>> _pickNative() async {
    final files = await ImagePicker().pickMultiImage();
    final result = <AttachmentDraft>[];
    for (final file in files) {
      if (!mounted || _denied) return [];
      final problem = RequestRules.checkNewImage(
        currentCount: _photos.length + result.length,
        sizeBytes: await file.length(),
        fileName: file.name,
      );
      if (problem != null) throw RequestFailure(problem);
      result.add(
        AttachmentDraft(name: file.name, bytes: await file.readAsBytes()),
      );
    }
    return result;
  }

  Future<void> _pick() async {
    if (_locked || !_foreground) return;
    final generation = _identityGeneration;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final selected = await (widget.pickAttachments?.call() ?? _pickNative());
      if (!mounted || generation != _identityGeneration || _denied) return;
      if (!await _revalidate()) return;
      if (!mounted || generation != _identityGeneration || _denied) return;
      for (final photo in selected) {
        final problem = RequestRules.checkNewImage(
          currentCount: _photos.length,
          sizeBytes: photo.bytes.length,
          fileName: photo.name,
        );
        if (problem != null || photo.bytes.isEmpty) {
          setState(() => _error = problem ?? 'Ảnh không hợp lệ.');
          continue;
        }
        setState(() {
          _clearSubmission();
          _photos.add(photo);
        });
      }
    } on RequestFailure catch (failure) {
      if (mounted && generation == _identityGeneration) {
        setState(() => _error = failure.message);
      }
    } catch (_) {
      if (mounted && generation == _identityGeneration) {
        setState(() => _error = 'Không thể chọn ảnh. Vui lòng thử lại.');
      }
    } finally {
      if (mounted && generation == _identityGeneration) {
        setState(() => _picking = false);
      }
    }
  }

  bool _validReceipt(StudentConfirmationReceipt receipt, String actionId) =>
      receipt.requestId == widget.detail.request.id &&
      receipt.actionId == actionId &&
      receipt.version == widget.detail.request.version + 1 &&
      receipt.status == _resultStatus &&
      receipt.feedbackId == (_allowsPhotos ? actionId : null);

  Future<StudentConfirmationReceipt> _send() {
    final action = widget.action;
    final request = widget.detail.request;
    if (action != null) {
      return widget.repository.submitConfirmation(
        _submission ??= StudentConfirmationSubmission(
          actionId: createStudentRequestId(),
          requestId: request.id,
          expectedVersion: request.version,
          action: action,
          note: _note.text,
          attachments: _photos,
        ),
      );
    }
    return widget.repository.submitMutation(
      _mutation ??= _action == _ReasonAction.cancel
          ? StudentRequestMutation.cancel(
              actionId: createStudentRequestId(),
              requestId: request.id,
              expectedVersion: request.version,
              reason: _note.text,
            )
          : StudentRequestMutation.reopen(
              actionId: createStudentRequestId(),
              requestId: request.id,
              expectedVersion: request.version,
              reason: _note.text,
              attachments: _photos,
            ),
    );
  }

  void _finish(StudentConfirmationReceipt receipt) {
    _allowPop = true;
    Navigator.of(context).pop(receipt);
  }

  Future<void> _submit() async {
    if (_submitting ||
        _picking ||
        _checking ||
        _denied ||
        _conflict ||
        !_foreground ||
        !_accessVerified) {
      return;
    }
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final generation = _identityGeneration;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final receipt = await _send();
      if (!mounted || generation != _identityGeneration || _denied) return;
      if (!_validReceipt(
        receipt,
        _submission?.actionId ?? _mutation!.actionId,
      )) {
        throw const RequestFailure(
          'Chưa xác nhận được kết quả thao tác.',
          uncertain: true,
        );
      }
      _pendingReceipt = receipt;
      if (_foreground) {
        if (_accessVerified) {
          _finish(receipt);
        } else {
          await _revalidate();
        }
      }
    } on RequestFailure catch (failure) {
      if (!mounted || generation != _identityGeneration) return;
      if (failure.accessDenied) {
        _deny();
      } else {
        setState(() {
          _uncertain = failure.uncertain;
          _conflict = failure.conflict;
          _error = failure.uncertain
              ? 'Chưa xác nhận được kết quả. Bấm kiểm tra lại để tránh gửi trùng.'
              : failure.message;
        });
      }
    } catch (_) {
      if (mounted && generation == _identityGeneration) {
        setState(() {
          _uncertain = true;
          _error = 'Chưa xác nhận được kết quả. Bấm kiểm tra lại để tránh gửi trùng.';
        });
      }
    } finally {
      if (mounted && generation == _identityGeneration) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _leave() async {
    if (_submitting || _checking || _confirmingLeave) return;
    if (_denied || _conflict || (!_hasDraft && !_uncertain) || _allowPop) {
      Navigator.of(context).pop();
      return;
    }
    _confirmingLeave = true;
    final discard = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(
          _uncertain ? 'Kiểm tra lại chi tiết?' : 'Bỏ nội dung đang nhập?',
        ),
        content: Text(
          _uncertain
              ? 'Thao tác có thể đã được lưu. Hãy kiểm tra trạng thái trước khi gửi thao tác khác.'
              : 'Nội dung chưa gửi sẽ không được lưu.',
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
    _confirmingLeave = false;
    if (!mounted || discard != true) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _identityGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _accessSubscription?.cancel();
    _note.removeListener(_draftChanged);
    _note.dispose();
    _clearPhotos();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop:
        _allowPop ||
        (!_submitting &&
            !_checking &&
            (_denied || _conflict || (!_hasDraft && !_uncertain))),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: DormFixAppBar(
        title: _title,
        roleLabel: 'Sinh viên',
        leading: BackButton(onPressed: _leave),
      ),
      body: !_foreground || _checking
          ? const Center(child: CircularProgressIndicator())
          : _denied || _conflict
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _leave,
                      child: const Text('Quay lại chi tiết'),
                    ),
                  ],
                ),
              ),
            )
          : !_accessVerified
          ? ErrorView(
              message: _error ?? 'Cần kiểm tra lại quyền truy cập.',
              onRetry: _revalidate,
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${widget.detail.request.requestCode} · ${widget.detail.request.title}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(_instructions),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: const Key('student-result-note'),
                      controller: _note,
                      enabled: !_locked,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(labelText: _noteLabel),
                      validator: (value) =>
                          _action != _ReasonAction.confirm &&
                              (value?.trim().isEmpty ?? true)
                          ? _emptyReason
                          : null,
                    ),
                    if (_allowsPhotos) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Ảnh phản hồi (${_photos.length}/5) · Mỗi ảnh tối đa 5 MB',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (var i = 0; i < _photos.length; i++)
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    _photos[i].bytes,
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
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton(
                                    key: ValueKey('student-result-remove-$i'),
                                    tooltip: 'Xóa ảnh',
                                    onPressed: _locked
                                        ? null
                                        : () => setState(() {
                                            _clearSubmission();
                                            unawaited(
                                              MemoryImage(_photos[i].bytes)
                                                  .evict(),
                                            );
                                            _photos.removeAt(i);
                                          }),
                                    icon: const Icon(Icons.close),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .surface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const Key('student-result-add-photos'),
                        onPressed: _locked || _photos.length >= 5
                            ? null
                            : _pick,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('Thêm ảnh'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        key: const Key('student-result-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: const Key('student-result-submit'),
                      onPressed:
                          _submitting ||
                              _picking ||
                              _checking ||
                              _denied ||
                              _conflict ||
                              !_accessVerified
                          ? null
                          : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(switch (_action) {
                              _ReasonAction.confirm =>
                                Icons.check_circle_outline,
                              _ReasonAction.cancel => Icons.cancel_outlined,
                              _ReasonAction.rework ||
                              _ReasonAction.reopen => Icons.replay,
                            }),
                      label: Text(_uncertain ? 'Kiểm tra lại' : _submitLabel),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}
