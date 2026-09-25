import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_text_styles.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  String _text = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/sing-box.log');
  }

  Future<void> _load() async {
    final file = await _file();
    final text = file.existsSync() ? await file.readAsString() : '';
    if (!mounted) return;
    setState(() {
      _text = text.isEmpty ? context.read<SettingsProvider>().strings.t('logEmpty') : text;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('showLog')),
        actions: [
          IconButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: _text)),
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            onPressed: () => SharePlus.instance.share(ShareParams(text: _text)),
            icon: const Icon(Icons.share_rounded),
          ),
          IconButton(
            onPressed: () async {
              final file = await _file();
              if (file.existsSync()) await file.writeAsString('');
              await _load();
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(_text, style: AppTextStyles.monoValue),
            ),
    );
  }
}
