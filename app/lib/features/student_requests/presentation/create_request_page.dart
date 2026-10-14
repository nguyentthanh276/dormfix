import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/request_repository.dart';
import '../models/incident_category.dart';
import '../models/new_repair_request.dart';
import '../models/request_rules.dart';

/// DF-007: form tạo yêu cầu sửa chữa kèm tối đa 5 ảnh.
class CreateRequestPage extends StatefulWidget {
  const CreateRequestPage({
    super.key,
    required this.repository,
    required this.roomCode,
  });

  final RequestRepository repository;
  final String? roomCode; // lấy từ tài khoản, hiển thị chỉ đọc

  @override
  State<CreateRequestPage> createState() => _CreateRequestPageState();
}

class _CreateRequestPageState extends State<CreateRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _picker = ImagePicker();

  List<IncidentCategory> _categories = [];
  String? _categoryId;
  final List<AttachmentDraft> _images = [];

  bool _loadingCategories = false;
  bool _submitting = false; // true khi đang gửi: khóa nút để không gửi lặp
  String? _errorText;

  @override
  void initState() {
    super.initState();
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
      if (mounted) setState(() => _categories = result);
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
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final problem = RequestRules.checkNewImage(
        currentCount: _images.length,
        sizeBytes: bytes.length,
        fileName: file.name,
      );
      if (!mounted) return;
      if (problem != null) {
        _showMessage(problem);
        continue; // bỏ qua ảnh sai, vẫn xét ảnh tiếp theo
      }
      setState(
        () => _images.add(AttachmentDraft(name: file.name, bytes: bytes)),
      );
    }
  }

  Future<void> _submit() async {
    if (_submitting) return; // chống gửi lặp (ngoài việc khóa nút)
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await widget.repository.createRequest(
        NewRepairRequest(
          title: _titleCtrl.text.trim(),
          categoryId: _categoryId!,
          description: _descCtrl.text.trim(),
          attachments: List.of(_images),
        ),
      );
      if (!mounted) return;
      _showMessage('Đã gửi yêu cầu sửa chữa');
      Navigator.pop(context, true); // true = đã tạo, danh sách sẽ tải lại
    } catch (_) {
      // Lỗi khi ghi thì không tự thử lại, sinh viên tự bấm gửi lại.
      if (!mounted) return;
      setState(() {
        _errorText = 'Gửi yêu cầu thất bại. Vui lòng thử lại.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tạo yêu cầu sửa chữa')),
    body: SafeArea(child: _body()),
  );

  Widget _body() {
    if (_loadingCategories) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_categories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorText ?? 'Chưa có loại sự cố nào.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadCategories,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    return _buildForm();
  }

  Widget _buildForm() {
    final noRoom = widget.roomCode == null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Phòng: chỉ đọc, lấy từ tài khoản, sinh viên không được chọn.
            TextFormField(
              key: const Key('roomField'),
              initialValue: widget.roomCode ?? 'Chưa được gắn phòng',
              enabled: false,
              decoration: const InputDecoration(labelText: 'Phòng'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('titleField'),
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Tiêu đề *'),
              textInputAction: TextInputAction.next, // bấm Next nhảy sang ô kế
              validator: RequestRules.validateTitle,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('categoryField'),
              decoration: const InputDecoration(labelText: 'Loại sự cố *'),
              items: [
                for (final c in _categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
              validator: RequestRules.validateCategory,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('descField'),
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Mô tả *',
                alignLabelWithHint: true,
              ),
              minLines: 3,
              maxLines: 6,
              validator: RequestRules.validateDescription,
            ),
            const SizedBox(height: 16),
            _buildImages(),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (noRoom) ...[
              const SizedBox(height: 12),
              Text(
                'Tài khoản chưa được gắn phòng nên chưa thể gửi yêu cầu.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              // null = nút bị khóa: đang gửi hoặc chưa có phòng
              onPressed: (_submitting || noRoom) ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Gửi yêu cầu'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImages() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Ảnh đính kèm (${_images.length}/${RequestRules.maxImages}, mỗi ảnh tối đa ${RequestRules.maxImageMb} MB)',
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _images.length; i++)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _images[i].bytes,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: InkWell(
                    onTap: () => setState(() => _images.removeAt(i)),
                    child: const CircleAvatar(
                      radius: 11,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          if (_images.length < RequestRules.maxImages)
            OutlinedButton.icon(
              onPressed: _submitting ? null : _pickImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Thêm ảnh'),
            ),
        ],
      ),
    ],
  );
}
