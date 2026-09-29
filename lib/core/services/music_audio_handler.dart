import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as just_audio;

/// Background audio_service handler used on Android. The Flutter UI talks to
/// it through customAction so the same queue continues when the activity is
/// covered, locked, or removed from recents.
class MusicAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  MusicAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.currentIndexStream.listen((index) {
      if (index == null || index < 0 || index >= queue.value.length) return;
      mediaItem.add(queue.value[index]);
    });
  }

  final just_audio.AudioPlayer _player = just_audio.AudioPlayer();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    } else {
      await stop();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    mediaItem.add(null);
    await super.stop();
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'setVolume') {
      final value = (extras?['value'] as num?)?.toDouble();
      if (value != null) await _player.setVolume(value.clamp(0.0, 1.0).toDouble());
      return null;
    }
    if (name != 'loadQueue') return super.customAction(name, extras);
    final rawItems = extras?['items'];
    final rawIndex = extras?['index'];
    if (rawItems is! List || rawItems.isEmpty) return null;
    final items = rawItems.whereType<Map>().map((raw) {
      final item = Map<String, dynamic>.from(raw);
      final durationMs = (item['durationMs'] as num?)?.toInt();
      final artwork = '${item['artworkPath'] ?? ''}'.trim();
      return MediaItem(
        id: '${item['id'] ?? ''}',
        title: '${item['title'] ?? ''}',
        artist: '${item['artist'] ?? ''}',
        album: '${item['album'] ?? ''}',
        duration: durationMs == null || durationMs <= 0 ? null : Duration(milliseconds: durationMs),
        artUri: artwork.isEmpty ? null : Uri.file(artwork),
      );
    }).where((item) => item.id.isNotEmpty).toList();
    if (items.isEmpty) return null;
    final index = rawIndex is num ? rawIndex.toInt().clamp(0, items.length - 1).toInt() : 0;
    final sources = <just_audio.AudioSource>[];
    for (final item in items) {
      final raw = rawItems.cast<Map>().firstWhere(
        (candidate) => '${candidate['id'] ?? ''}' == item.id,
        orElse: () => <String, dynamic>{},
      );
      final path = '${raw['path'] ?? ''}';
      if (path.isNotEmpty) {
        sources.add(just_audio.AudioSource.uri(Uri.file(path), tag: item));
      }
    }
    if (sources.isEmpty) return null;
    final safeIndex = index < sources.length ? index : sources.length - 1;
    queue.add(items.take(sources.length).toList(growable: false));
    await _player.setAudioSources(
      sources,
      initialIndex: safeIndex,
      preload: true,
    );
    mediaItem.add(queue.value[safeIndex]);
    await _player.play();
    return null;
  }

  void _broadcastState(just_audio.PlaybackEvent event) {
    final processing = switch (_player.processingState) {
      just_audio.ProcessingState.idle => AudioProcessingState.idle,
      just_audio.ProcessingState.loading => AudioProcessingState.loading,
      just_audio.ProcessingState.buffering => AudioProcessingState.buffering,
      just_audio.ProcessingState.ready => AudioProcessingState.ready,
      just_audio.ProcessingState.completed => AudioProcessingState.completed,
    };
    final playing = _player.playing && processing == AudioProcessingState.ready;
    playbackState.add(
      playbackState.value.copyWith(
        controls: <MediaControl>[
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const <int>[0, 1, 2],
        processingState: processing,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
    );
  }
}
