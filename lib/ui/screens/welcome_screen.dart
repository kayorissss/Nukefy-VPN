import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_text_styles.dart';
import '../import_actions.dart';
import '../widgets/nukefy_background.dart';
import '../widgets/nukefy_logo.dart';
import 'qr_scanner_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final s = settings.strings;
    return NukefyBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                const NukefyLogo(size: 96)
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .scale(begin: const Offset(0.9, 0.9)),
                const SizedBox(height: 22),
                Text(s.t('welcomeTitle'), textAlign: TextAlign.center, style: AppTextStyles.title)
                    .animate()
                    .fadeIn(delay: 120.ms),
                const SizedBox(height: 10),
                Text(s.t('welcomeBody'), textAlign: TextAlign.center, style: AppTextStyles.bodySecondary),
                const Spacer(),
                _WelcomeButton(icon: Icons.content_paste_rounded, label: s.t('paste'), onTap: () => ImportActions.paste(context)),
                const SizedBox(height: 10),
                _WelcomeButton(icon: Icons.edit_rounded, label: s.t('manual'), onTap: () => ImportActions.manual(context)),
                const SizedBox(height: 10),
                _WelcomeButton(
                  icon: Icons.qr_code_scanner_rounded,
                  label: s.t('qr'),
                  onTap: () async {
                    final text = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
                    );
                    if (text != null && context.mounted) {
                      await ImportActions.handleText(context, text);
                    }
                  },
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: () => settings.update((value) => value.seenWelcome = true),
                  child: Text(s.t('skip')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeButton extends StatelessWidget {
  const _WelcomeButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(label),
        ),
      ),
    );
  }
}
