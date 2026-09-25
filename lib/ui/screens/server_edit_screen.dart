import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/servers_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/nukefy_feedback.dart';

class ServerEditScreen extends StatefulWidget {
  const ServerEditScreen({super.key, required this.serverId});

  final String serverId;

  @override
  State<ServerEditScreen> createState() => _ServerEditScreenState();
}

class _ServerEditScreenState extends State<ServerEditScreen> {
  late final TextEditingController _json;
  String? _detour;
  String? _error;

  @override
  void initState() {
    super.initState();
    final server = context.read<ServersProvider>().byId(widget.serverId);
    _detour = server?.detourServerId;
    final payload = server?.endpoint ?? server?.outbound ?? {
      'name': server?.name,
      'address': server?.address,
      'port': server?.port,
      'protocol': server?.protocol,
    };
    _json = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final servers = context.watch<ServersProvider>().servers;
    final others = servers.where((item) => item.id != widget.serverId).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('edit')),
        actions: [
          TextButton(onPressed: _save, child: Text(s.t('save'))),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('editJson'), style: AppTextStyles.bodySecondary),
            const SizedBox(height: 8),
            Text(s.t('chainHint'), style: AppTextStyles.bodySecondary),
            DropdownButton<String?>(
              value: _detour,
              isExpanded: true,
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(s.t('none'))),
                for (final server in others)
                  DropdownMenuItem(value: server.id, child: Text(server.name)),
              ],
              onChanged: (value) => setState(() => _detour = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _json,
                maxLines: null,
                expands: true,
                style: AppTextStyles.monoValue,
              ),
            ),
            if (_error != null)
              Text(_error!, style: AppTextStyles.bodySecondary.copyWith(color: Colors.redAccent)),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final s = context.read<SettingsProvider>().strings;
    final servers = context.read<ServersProvider>();
    final server = servers.byId(widget.serverId);
    if (server == null) return;
    try {
      final decoded = jsonDecode(_json.text);
      if (decoded is! Map) {
        setState(() => _error = s.t('invalidJson'));
        return;
      }
      final map = decoded.map((key, value) => MapEntry(key.toString(), value));
      final type = (map['type'] ?? '').toString();
      if (type == 'wireguard' || server.isWireGuard) {
        server.endpoint = map;
      } else if (map.containsKey('type') || map.containsKey('server')) {
        server.outbound = map;
        final host = map['server'] ?? map['address'];
        final port = map['server_port'] ?? map['port'];
        if (host is String && host.isNotEmpty) server.address = host;
        if (port is num) server.port = port.toInt();
        if (type.isNotEmpty && type != 'wireguard') server.protocol = type;
      }
      final tag = map['tag'] ?? map['name'];
      if (tag is String && tag.isNotEmpty) server.name = tag;
      server.detourServerId = _detour;
      await servers.updateServer(server);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      setState(() => _error = '$error');
      showNukefySnack(context, s.t('invalidJson'), error: true);
    }
  }
}
