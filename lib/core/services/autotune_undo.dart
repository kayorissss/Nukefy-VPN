import '../models/app_settings.dart';
import 'storage_service.dart';

/// A revertible record of one auto-setup run.
///
/// The wizard is meant to be safe: whatever it may change is written down
/// first, so a single "undo" can put the settings back exactly as they were.
/// The record lives in the same encrypted vault as the settings themselves, so
/// it survives a restart — a user who only notices a change a day later can
/// still revert it instead of hunting through the app for every switch.
class AutoTuneUndo {
  AutoTuneUndo._();

  static final AutoTuneUndo instance = AutoTuneUndo._();
  static const _key = 'autotune_undo';

  AutoTuneUndoRecord? _cached;

  Future<AutoTuneUndoRecord?> load() async {
    if (_cached != null) return _cached;
    final json = StorageService.instance.readJson(_key);
    if (json == null) return null;
    try {
      _cached = AutoTuneUndoRecord.fromJson(json);
    } catch (_) {
      // A record we cannot read is worse than no record: drop it.
      _cached = null;
      await StorageService.instance.remove(_key);
    }
    return _cached;
  }

  Future<void> save(AutoTuneUndoRecord record) async {
    _cached = record;
    await StorageService.instance.writeJson(_key, record.toJson());
  }

  Future<void> clear() async {
    _cached = null;
    await StorageService.instance.remove(_key);
  }
}

/// Everything one auto-setup run touched, and enough state to reverse it.
class AutoTuneUndoRecord {
  AutoTuneUndoRecord({
    required this.at,
    required this.settings,
    required this.ids,
    this.subscriptionId,
    this.zapretStarted = false,
    this.proxyDisabled = false,
  });

  /// When the run happened (shown next to the undo button).
  final DateTime at;

  /// Full settings snapshot from just before the run.
  final Map<String, dynamic> settings;

  /// Plan item ids that were actually applied.
  final List<String> ids;

  /// Subscription the wizard added itself, if any.
  final String? subscriptionId;

  /// Whether the wizard started winws (so undo may stop it again).
  final bool zapretStarted;

  /// Whether the wizard turned the system proxy off (backup file allows undo).
  final bool proxyDisabled;

  AppSettings get snapshot => AppSettings.fromJson(settings);

  bool get touchesSystem => proxyDisabled || zapretStarted || ids.contains('boot') || ids.contains('tray');

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'settings': settings,
        'ids': ids,
        if (subscriptionId != null) 'subscription': subscriptionId,
        'zapret': zapretStarted,
        'proxy': proxyDisabled,
      };

  factory AutoTuneUndoRecord.fromJson(Map<String, dynamic> json) {
    final rawSettings = json['settings'];
    return AutoTuneUndoRecord(
      at: DateTime.tryParse('${json['at']}') ?? DateTime.now(),
      settings: rawSettings is Map
          ? rawSettings.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{},
      ids: (json['ids'] is List) ? List<String>.from(json['ids'] as List) : const [],
      subscriptionId: json['subscription']?.toString(),
      zapretStarted: json['zapret'] == true,
      proxyDisabled: json['proxy'] == true,
    );
  }
}
