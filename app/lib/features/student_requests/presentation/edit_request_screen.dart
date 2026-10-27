import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_view.dart';
import '../data/request_repository.dart';
import '../models/edit_repair_request.dart';
import '../models/incident_category.dart';
import '../models/new_repair_request.dart';
import '../models/request_detail.dart';
import '../models/request_rules.dart';
import 'widgets/category_tile.dart';

/// DF-011: Form chỉnh sửa yêu cầu sửa chữa khi ở trạng thái Chờ tiếp nhận (pending).
class EditRequestScreen extends StatefulWidget {
  final RequestRepository repository;
  final RequestDetail detail;
  final VoidCallback? onUpdated;

  const EditRequestScreen({
    super.key,
    required this.repository,
    required this.detail,
    this.onUpdated,
  });

  @override
  State<EditRequestScreen> createState() => _EditRequestScreenState();
}

class _EditRequestScreenState extends State<EditRequestScreen> {
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
  String? _errorText;

  int get _totalImagesCount => _keptPhotos.length + _newImages.length;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.detail.request.title);
    _descCtrl = TextEditingController(text: widget.detail.description);
    _keptPhotos = List<String>.from(widget.detail.studentPhotos);
    _loadCategories();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _errorText = null;
    });
    try {
      final result = await widget.repository.fetchCategories();
      if (mounted) {
        setState(() {
          _categories = result;
          // Khớp categoryId theo categoryName hiện tại
          final current = _categories.where(
            (c) => c.name == widget.detail.request.categoryName,
          );
          if (current.isNotEmpty) {
            _categoryId = current.first.id;
          }
        });
      }
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
    final files = await _picker.pickMultiImage();
    if (!mounted || _submitting) return;
    for (final file in files) {
      final bytes = await file.readAsBytes();
      if (!mounted || _submitting) return;
      final problem = RequestRules.checkNewImage(
        currentCount: _totalImagesCount,
        sizeBytes: bytes.length,
        fileName: file.name,
      );
      if (!mounted) return;
      if (problem != null) {
        _showMessage(problem);
        continue;
      }
      setState(
        () => _newImages.add(AttachmentDraft(name: file.name, bytes: bytes)),
      );
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();

    final categoryError = RequestRules.validateCategory(_categoryId);
    setState(() => _categoryError = categoryError);
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk || categoryError != null) return;

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
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
      if (!mounted) return;
      widget.onUpdated?.call();
      if (!mounted) return;
      _showMessage('Đã cập nhật yêu cầu sửa chữa');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        appBar: AppBar(title: const Text('Chỉnh sửa yêu cầu')),
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
            controller: _titleCtrl,
            enabled: !_submitting,
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
                    if (_submitting) return;
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
            controller: _descCtrl,
            enabled: !_submitting,
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
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Lưu thay đổi'),
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
            Container(
              width: 72,
              height: 72,
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
            Positioned(
              right: -6,
              top: -6,
              child: GestureDetector(
                onTap: _submitting
                    ? null
                    : () => setState(() => _keptPhotos.removeAt(i)),
                child: const CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.red,
                  child: Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
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
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              right: -6,
              top: -6,
              child: GestureDetector(
                onTap: _submitting
                    ? null
                    : () => setState(() => _newImages.removeAt(i)),
                child: const CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.red,
                  child: Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      if (_totalImagesCount < RequestRules.maxImages)
        InkWell(
          onTap: _submitting ? null : _pickImages,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 72,
            height: 72,
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
}
