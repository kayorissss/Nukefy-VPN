import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/screenshot_service.dart';

import '../../l10n/strings.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

void showNukefySnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: AppTextStyles.bodyRegular),
        backgroundColor: error ? context.palette.error.withValues(alpha: 0.9) : context.palette.surface,
      ),
    );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  required String cancel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: AppTextStyles.headline),
      content: Text(body, style: context.palette.secondaryStyle),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: context.palette.error),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Error card you can actually send to someone: the text is selectable and a
/// copy button puts the whole message on the clipboard. Every raw error in the
/// app used to be a picture of a string.
class CopyableError extends StatelessWidget {
  const CopyableError({super.key, required this.message, this.strings, this.title});

  final String message;
  final S? strings;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: .38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700, color: AppColors.error)),
                  const SizedBox(height: 4),
                ],
                NukefySelectableText(
                  message,
                  style: AppTextStyles.bodySecondary.copyWith(color: AppColors.error),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: s?.t('copy') ?? 'Copy',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message));
              if (context.mounted) {
                showNukefySnack(context, s?.t('copied') ?? 'Copied');
              }
            },
            icon: Icon(Icons.copy_rounded, size: 17, color: AppColors.error),
          ),
        ],
      ),
    );
  }
}

/// Wraps the whole app so a PrintScreen press behaves the way Windows users
/// expect even though the client runs elevated: Windows hides the key from the
/// shell (Explorer / Snipping Tool) while an elevated window has focus, so the
/// app captures the screen itself, saves a PNG and puts the image on the
/// clipboard.
class PrintScreenCatcher extends StatefulWidget {
  const PrintScreenCatcher({super.key, required this.child});

  final Widget child;

  @override
  State<PrintScreenCatcher> createState() => _PrintScreenCatcherState();
}

class _PrintScreenCatcherState extends State<PrintScreenCatcher> {
  bool _busy = false;

  Future<void> _capture() async {
    if (_busy || !Platform.isWindows) return;
    _busy = true;
    final path = await ScreenshotService.instance.capture();
    _busy = false;
    if (!mounted) return;
    showNukefySnack(
      context,
      path == null
          ? context.read<SettingsProvider>().strings.t('shotFailed')
          : '${context.read<SettingsProvider>().strings.t('shotSaved')}: $path',
      error: path == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return widget.child;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.printScreen): () => unawaited(_capture()),
      },
      child: Focus(autofocus: true, child: widget.child),
    );
  }
}

/// Selectable text with a menu that fits the app.
///
/// Flutter draws its own selection menu; the real Win32 menu cannot be asked
/// for inside a Flutter surface, so this one is styled to the app theme and
/// offers the entries people actually need (copy / select all / copy all).
class NukefySelectableText extends StatefulWidget {
  const NukefySelectableText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.selectAllOnFocus = false,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final bool selectAllOnFocus;

  @override
  State<NukefySelectableText> createState() => _NukefySelectableTextState();
}

class _NukefySelectableTextState extends State<NukefySelectableText> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.text;
  }

  @override
  void didUpdateWidget(covariant NukefySelectableText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _controller.text = widget.text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.read<SettingsProvider>().strings;
    return TextField(
      controller: _controller,
      readOnly: true,
      maxLines: widget.maxLines,
      style: widget.style,
      cursorColor: p.accent,
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
      contextMenuBuilder: (context, editable) => AdaptiveTextSelectionToolbar(
        anchors: editable.contextMenuAnchors,
        children: [
          _MenuEntry(
            icon: Icons.copy_rounded,
            label: s.t('copy'),
            onTap: () {
              final selection = editable.textEditingValue.selection;
              final text = selection.isValid && !selection.isCollapsed
                  ? selection.textInside(editable.textEditingValue.text)
                  : editable.textEditingValue.text;
              Clipboard.setData(ClipboardData(text: text));
              editable.hideToolbar();
              showNukefySnack(context, s.t('copied'));
            },
          ),
          _MenuEntry(
            icon: Icons.select_all_rounded,
            label: s.t('selectAll'),
            onTap: () {
              editable.selectAll(SelectionChangedCause.toolbar);
              editable.showToolbar();
            },
          ),
          _MenuEntry(
            icon: Icons.copy_all_rounded,
            label: s.t('copyAll'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: editable.textEditingValue.text));
              editable.hideToolbar();
              showNukefySnack(context, s.t('copied'));
            },
          ),
        ],
      ),
    );
  }
}

class _MenuEntry extends StatelessWidget {
  const _MenuEntry({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: p.textSecondary),
            const SizedBox(width: 8),
            Text(label, style: AppTextStyles.bodyRegular.copyWith(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
