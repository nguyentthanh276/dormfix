import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/dormfix_app_bar.dart';
import '../../../core/widgets/error_view.dart';
import '../data/request_repository.dart';
import '../models/incident_category.dart';
import '../models/new_repair_request.dart';
import '../models/request_rules.dart';
import '../models/student_request_id.dart';
import 'widgets/category_tile.dart';

/// DF-007: form tạo yêu cầu sửa chữa kèm tối đa 5 ảnh.
class CreateRequestScreen extends StatefulWidget {
  final RequestRepository repository;
  final String? roomCode; // lấy từ tài khoản, hiển thị chỉ đọc
  final VoidCallback onCreated; // gọi sau khi tạo thành công

  const CreateRequestScreen({
    super.key,
    required this.repository,
    required this.roomCode,
    required this.onCreated,
  });

  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _picker = ImagePicker();

  List<IncidentCategory> _categories = [];
  String? _categoryId;
  String? _categoryError;
  final List<AttachmentDraft> _images = [];

  bool _loadingCategories = false;
  bool _submitting = false; // true khi đang gửi: khóa nút để không gửi lặp
  bool _allowPop = false;
  bool _confirmingLeave = false;
  bool _pickingImages = false;
  bool _uncertain = false;
  NewRepairRequest? _pendingRequest;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(_draftChanged);
    _descCtrl.addListener(_draftChanged);
    _loadCategories();
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_draftChanged);
    _descCtrl.removeListener(_draftChanged);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _hasDraft =>
      _titleCtrl.text.isNotEmpty ||
      _descCtrl.text.isNotEmpty ||
      _categoryId != null ||
      _images.isNotEmpty;

  void _draftChanged() {
    if (mounted) {
      setState(() {
        if (!_submitting && !_uncertain) _pendingRequest = null;
      });
    }
  }

  Future<void> _leave() async {
    if (_submitting || _confirmingLeave) return;
    if (!_hasDraft || _allowPop) {
      Navigator.of(context).pop();
      return;
    }
    _confirmingLeave = true;
    final discard = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _uncertain ? 'Kiểm tra danh sách yêu cầu?' : 'Bỏ yêu cầu đang nhập?',
        ),
        content: Text(
          _uncertain
              ? 'Yêu cầu có thể đã được lưu. Hãy kiểm tra danh sách trước khi tạo một yêu cầu mới.'
              : 'Nội dung chưa gửi sẽ không được lưu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Tiếp tục nhập'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_uncertain ? 'Xem danh sách' : 'Bỏ thay đổi'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _confirmingLeave = false;
    if (discard != true) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _errorText = null;
    });
    try {
      final result = await widget.repository.fetchCategories();
      if (mounted) setState(() => _categories = result);
    } on RequestFailure catch (failure) {
      if (mounted) setState(() => _errorText = failure.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = 'Không tải được loại sự cố. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickImages() async {
    if (_pickingImages || _submitting || _uncertain) return;
    setState(() => _pickingImages = true);
    try {
      final files = await _picker.pickMultiImage();
      for (final file in files) {
        if (!mounted || _submitting || _uncertain) return;
        final bytes = await file.readAsBytes();
        final problem = RequestRules.checkNewImage(
          currentCount: _images.length,
          sizeBytes: bytes.length,
          fileName: file.name,
        );
        if (!mounted || _submitting || _uncertain) return;
        if (problem != null) {
          _showMessage(problem);
          continue; // bỏ qua ảnh sai, vẫn xét ảnh tiếp theo
        }
        setState(() {
          _pendingRequest = null;
          _images.add(AttachmentDraft(name: file.name, bytes: bytes));
        });
      }
    } catch (_) {
      if (mounted) _showMessage('Không thể chọn ảnh. Vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting || _pickingImages) return;
    FocusScope.of(context).unfocus();

    // Loại sự cố chọn bằng lưới ô nên kiểm tra riêng, ngoài Form.
    final categoryError = RequestRules.validateCategory(_categoryId);
    setState(() => _categoryError = categoryError);
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk || categoryError != null) return;

    _pendingRequest ??= NewRepairRequest(
      requestId: createStudentRequestId(),
      title: _titleCtrl.text.trim(),
      categoryId: _categoryId!,
      description: _descCtrl.text.trim(),
      attachments: List.unmodifiable(_images),
    );
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await widget.repository.createRequest(_pendingRequest!);
      if (!mounted) return;
      _allowPop = true;
      _showMessage('Đã gửi yêu cầu sửa chữa');
      widget.onCreated(); // báo cho màn cha (chuyển về danh sách)
    } on RequestFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _uncertain = failure.uncertain;
        _errorText = failure.uncertain
            ? 'Chưa xác nhận được yêu cầu đã lưu. Bấm kiểm tra lại để tránh tạo trùng.'
            : failure.message;
        if (failure.accessDenied) {
          _pendingRequest = null;
          _images.clear();
          _titleCtrl.clear();
          _descCtrl.clear();
          _categoryId = null;
        }
      });
    } catch (_) {
      // Lỗi khi ghi thì không tự thử lại, sinh viên tự bấm gửi lại.
      if (mounted) {
        setState(() {
          _uncertain = !widget.repository.allowsDemoFallback;
          _errorText = _uncertain
              ? 'Chưa xác nhận được yêu cầu đã lưu. Bấm kiểm tra lại để tránh tạo trùng.'
              : 'Gửi yêu cầu thất bại. Vui lòng thử lại.';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _allowPop || (!_hasDraft && !_submitting),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: DormFixAppBar(
          title: 'Tạo yêu cầu sửa chữa',
          roleLabel: 'Sinh viên',
          leading: Navigator.of(context).canPop()
              ? BackButton(onPressed: _leave)
              : null,
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
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
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: AppColors.primaryDark,
      ),
    ),
  );

  Widget _buildForm() {
    final noRoom = widget.roomCode == null;
    final errorColor = Theme.of(context).colorScheme.error;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('Loại sự cố *'),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
            children: [
              for (final c in _categories)
                CategoryTile(
                  category: c,
                  selected: _categoryId == c.id,
                  onTap: _submitting || _uncertain
                      ? () {}
                      : () => setState(() {
                          _pendingRequest = null;
                          _categoryId = c.id;
                          _categoryError = null;
                        }),
                ),
            ],
          ),
          if (_categoryError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _categoryError!,
                style: TextStyle(color: errorColor, fontSize: 12),
              ),
            ),
          Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label('Phòng'),
                // Phòng: chỉ đọc, lấy từ tài khoản, sinh viên không được chọn.
                TextFormField(
                  key: const Key('roomField'),
                  initialValue: widget.roomCode ?? 'Chưa được gắn phòng',
                  enabled: false,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.meeting_room_outlined, size: 20),
                  ),
                ),
                _label('Tiêu đề *'),
                TextFormField(
                  key: const Key('titleField'),
                  controller: _titleCtrl,
                  enabled: !_submitting && !_uncertain,
                  decoration: const InputDecoration(
                    hintText: 'VD: Hỏng bóng đèn nhà tắm',
                  ),
                  textInputAction:
                      TextInputAction.next, // bấm Next nhảy sang ô kế
                  validator: RequestRules.validateTitle,
                ),
                _label('Mô tả chi tiết *'),
                TextFormField(
                  key: const Key('descField'),
                  controller: _descCtrl,
                  enabled: !_submitting && !_uncertain,
                  decoration: const InputDecoration(
                    hintText: 'Mô tả tình trạng, vị trí, thời điểm xảy ra...',
                  ),
                  minLines: 4,
                  maxLines: 6,
                  validator: RequestRules.validateDescription,
                ),
              ],
            ),
          ),
          _label(
            'Ảnh đính kèm (${_images.length}/${RequestRules.maxImages}, mỗi ảnh tối đa ${RequestRules.maxImageMb} MB)',
          ),
          _buildImages(),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(_errorText!, style: TextStyle(color: errorColor)),
          ],
          if (noRoom) ...[
            const SizedBox(height: 12),
            Text(
              'Tài khoản chưa được gắn phòng nên chưa thể gửi yêu cầu.',
              style: TextStyle(color: errorColor),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              // null = nút bị khóa: đang gửi hoặc chưa có phòng
              key: const Key('create-request-submit'),
              onPressed: (_submitting || _pickingImages || noRoom)
                  ? null
                  : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_uncertain ? 'Kiểm tra lại yêu cầu' : 'Gửi yêu cầu'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImages() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var i = 0; i < _images.length; i++)
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _images[i].bytes,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 72,
                  height: 72,
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
            Positioned(
              right: -6,
              top: -6,
              child: GestureDetector(
                onTap: _submitting || _uncertain
                    ? null
                    : () => setState(() {
                        _pendingRequest = null;
                        _images.removeAt(i);
                      }),
                child: const CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.red,
                  child: Icon(Icons.close, size: 12, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      if (_images.length < RequestRules.maxImages)
        InkWell(
          onTap: _submitting || _uncertain || _pickingImages
              ? null
              : _pickImages,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withAlpha(120)),
            ),
            child: const Icon(
              Icons.add_a_photo_outlined,
              color: AppColors.primary,
            ),
          ),
        ),
    ],
  );
}
