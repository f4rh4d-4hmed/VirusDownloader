import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class RenameDialog extends StatefulWidget {
  final String fileName;
  final ValueChanged<String> onConfirm;

  const RenameDialog({
    Key? key,
    required this.fileName,
    required this.onConfirm,
  }) : super(key: key);

  static Future<void> show(
    BuildContext context,
    String fileName, {
    required ValueChanged<String> onConfirm,
  }) {
    return showDialog(
      context: context,
      builder: (context) => RenameDialog(
        fileName: fileName,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final TextEditingController _controller;
  late final String _extension;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _extension = p.extension(widget.fileName);
    final nameWithoutExt = p.basenameWithoutExtension(widget.fileName);
    _controller = TextEditingController(text: nameWithoutExt);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validateAndSubmit() {
    final newName = _controller.text.trim();
    if (newName.isEmpty) {
      setState(() => _errorMessage = 'Filename cannot be empty');
      return;
    }

    final illegalChars = RegExp(r'[\\/:*?"<>|]');
    if (illegalChars.hasMatch(newName)) {
      setState(() {
        _errorMessage = 'Contains illegal characters (\\ / : * ? " < > |)';
      });
      return;
    }

    setState(() => _errorMessage = null);
    widget.onConfirm('$newName$_extension');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename File'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: 'New Name',
              suffixText: _extension,
              errorText: _errorMessage,
            ),
            autofocus: true,
            onSubmitted: (_) => _validateAndSubmit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _validateAndSubmit,
          child: const Text('Rename'),
        ),
      ],
    );
  }
}
