import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _handled = false;
  bool _allowed = !Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      Permission.camera.request().then((status) {
        if (mounted) setState(() => _allowed = status.isGranted);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('qr'))),
      body: !Platform.isAndroid && !Platform.isIOS
          ? Center(child: Text(s.t('qrDesktop')))
          : !_allowed
          ? Center(child: Text(s.t('noCamera')))
          : MobileScanner(
              onDetect: (capture) {
                if (_handled) return;
                final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
                if (value == null || value.trim().isEmpty) return;
                _handled = true;
                Navigator.pop(context, value);
              },
            ),
    );
  }
}
