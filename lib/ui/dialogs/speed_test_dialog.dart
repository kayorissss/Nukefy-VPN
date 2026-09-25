import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/server_model.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/speed_test_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';

Future<void> showSpeedTest(BuildContext context, ServerModel server) async {
  final s = context.read<SettingsProvider>().strings;
  final vpn = context.read<VpnProvider>();
  if (vpn.status != VpnStatus.connected || vpn.activeServerId != server.id) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('speedTest')),
        content: Text(s.t('speedNeed')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('cancel'))),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await vpn.connect(server);
            },
            child: Text(s.t('connect')),
          ),
        ],
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SpeedDialog(httpPort: context.read<SettingsProvider>().settings.httpPort),
  );
}

class _SpeedDialog extends StatefulWidget {
  const _SpeedDialog({required this.httpPort});
  final int httpPort;

  @override
  State<_SpeedDialog> createState() => _SpeedDialogState();
}

class _SpeedDialogState extends State<_SpeedDialog> {
  SpeedTestResult? _result;
  String? _error;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final result = await SpeedTestService().run(httpPort: widget.httpPort);
      if (!mounted) return;
      setState(() {
        _result = result;
        _running = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    return AlertDialog(
      title: Text(s.t('speedTest')),
      content: _running
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(s.t('testing'), style: AppTextStyles.bodySecondary),
                Text(s.t('speedThrough'), style: AppTextStyles.bodySecondary),
              ],
            )
          : _error != null
              ? Text('${s.t('testFailed')}\n$_error', style: AppTextStyles.bodySecondary)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('↓ ${FormatUtils.speed(_result!.downloadBps)}', style: AppTextStyles.monoValue.copyWith(color: AppColors.success, fontSize: 18)),
                    const SizedBox(height: 6),
                    Text('↑ ${FormatUtils.speed(_result!.uploadBps)}', style: AppTextStyles.monoValue.copyWith(color: AppColors.cyan, fontSize: 18)),
                    const SizedBox(height: 6),
                    Text(FormatUtils.bytes(_result!.bytes), style: AppTextStyles.bodySecondary),
                  ],
                ),
      actions: [
        TextButton(onPressed: _running ? null : () => Navigator.pop(context), child: Text(s.t('close') == 'close' ? s.t('cancel') : s.t('cancel'))),
      ],
    );
  }
}
