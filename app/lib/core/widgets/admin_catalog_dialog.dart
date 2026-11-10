import 'package:flutter/material.dart';

import '../data/admin_catalog_failure.dart';

enum AdminCatalogDialogResult { saved, refresh }

/// Keeps the draft open until the repository acknowledges the save.
class AdminCatalogDialog extends StatefulWidget {
  const AdminCatalogDialog({
    super.key,
    required this.title,
    required this.submitLabel,
    required this.fields,
    required this.onSave,
    this.destructive = false,
  });

  final String title;
  final String submitLabel;
  final Widget Function(bool enabled) fields;
  final Future<void> Function() onSave;
  final bool destructive;

  @override
  State<AdminCatalogDialog> createState() => _AdminCatalogDialogState();
}

class _AdminCatalogDialogState extends State<AdminCatalogDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _error;
  bool _saving = false;
  bool _refreshRequired = false;

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (_saving || _refreshRequired || form == null || !form.validate()) return;
    form.save();
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave();
      if (mounted) Navigator.of(context).pop(AdminCatalogDialogResult.saved);
    } on AdminCatalogFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _refreshRequired =
            failure.accessDenied || failure.conflict || failure.uncertain;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Chưa xác nhận được kết quả. Hãy tải lại danh sách trước khi thử lại.';
        _refreshRequired = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope<AdminCatalogDialogResult>(
      canPop: !_saving && !_refreshRequired,
      child: AlertDialog(
        scrollable: true,
        title: Text(widget.title),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_refreshRequired) widget.fields(!_saving),
              if (_error != null) ...[
                if (!_refreshRequired) const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: colorScheme.error)),
              ],
            ],
          ),
        ),
        actions: [
          if (_refreshRequired)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(AdminCatalogDialogResult.refresh),
              child: const Text('Đóng và tải lại'),
            )
          else ...[
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: widget.destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                    )
                  : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.submitLabel),
            ),
          ],
        ],
      ),
    );
  }
}
