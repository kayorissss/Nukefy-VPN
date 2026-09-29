
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/providers/servers_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/utils/link_parser.dart';
import 'widgets/nukefy_feedback.dart';

class ImportActions {
  static Future<void> paste(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!context.mounted) return;
      showNukefySnack(context, context.read<SettingsProvider>().strings.t('clipboardEmpty'));
      return;
    }
    await handleText(context, text);
  }

  static Future<void> manual(BuildContext context) async {
    final s = context.read<SettingsProvider>().strings;
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('enterManually')),
        content: TextField(
          controller: controller,
          minLines: 4,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
          decoration: InputDecoration(hintText: s.t('manualHint')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(s.t('add')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    await handleText(context, text);
  }

  static Future<void> fromFile(BuildContext context) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json', 'txt', 'conf', 'yaml', 'yml'],
    );
    if (file == null || !context.mounted) return;
    final text = String.fromCharCodes(await file.readAsBytes());
    if (!context.mounted) return;
    await handleText(context, text);
  }

  static Future<void> handleText(BuildContext context, String text) async {
    final servers = context.read<ServersProvider>();
    final s = context.read<SettingsProvider>().strings;
    final parsed = LinkParser.parseInput(text);
    if (parsed.subscriptionUrls.isNotEmpty) {
      for (final url in parsed.subscriptionUrls) {
        await servers.addSubscription(url);
      }
      if (!context.mounted) return;
      showNukefySnack(context, s.t('subscriptionAdded'));
    }
    if (parsed.servers.isNotEmpty) {
      final count = await servers.addDrafts(parsed.servers);
      if (!context.mounted) return;
      showNukefySnack(context, '${s.t('serversAdded')}: $count');
    }
    if (!parsed.isEmpty && context.mounted) {
      await context.read<SettingsProvider>().update((value) => value.seenWelcome = true);
    }
    if (parsed.isEmpty) {
      if (!context.mounted) return;
      showNukefySnack(context, s.t('unknownFormat'), error: true);
    } else if (parsed.warnings.isNotEmpty && context.mounted) {
      showNukefySnack(context, s.t('partial'));
    }
  }
}
