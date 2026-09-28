import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'storage_service.dart';

class MusicTrack {
  MusicTrack({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.size,
    required this.addedAt,
    this.durationMs,
    this.artworkPath,
  });

  final String id;
  String path;
  String title;
  String artist;
  String album;
  int size;
  int? durationMs;
  String? artworkPath;
  DateTime addedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'title': title,
        'artist': artist,
        'album': album,
        'size': size,
        'durationMs': durationMs,
        'artworkPath': artworkPath,
        'addedAt': addedAt.toIso8601String(),
      };

  factory MusicTrack.fromJson(Map<String, dynamic> json) => MusicTrack(
        id: '${json['id'] ?? ''}',
        path: '${json['path'] ?? ''}',
        title: '${json['title'] ?? ''}',
        artist: '${json['artist'] ?? ''}',
        album: '${json['album'] ?? ''}',
        size: (json['size'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt(),
        artworkPath: (json['artworkPath'] as String?)?.trim().isEmpty == true ? null : json['artworkPath'] as String?,
        addedAt: DateTime.tryParse('${json['addedAt']}') ?? DateTime.now(),
      );
}

class MusicPlaylist {
  MusicPlaylist({
    required this.id,
    required this.name,
    required this.icon,
    required this.trackIds,
    required this.createdAt,
  });

  final String id;
  String name;
  String icon;
  List<String> trackIds;
  DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'trackIds': trackIds,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) => MusicPlaylist(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        icon: '${json['icon'] ?? 'music_note'}',
        trackIds: (json['trackIds'] as List?)?.map((e) => '$e').toList() ?? <String>[],
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      );
}

/// Local music library and one-player queue. Files are copied into the app's
/// support directory so a user can safely remove the original download.
class MusicService extends ChangeNotifier {
  MusicService(this._storage, {audio_service.AudioHandler? backgroundHandler})
      : _background = backgroundHandler {
    if (_background == null) {
      _player.onPositionChanged.listen((value) {
        position = value;
        notifyListeners();
      });
      _player.onDurationChanged.listen((value) {
        duration = value;
        final track = currentTrack;
        if (track != null && (track.durationMs == null || track.durationMs == 0)) {
          track.durationMs = value.inMilliseconds;
          _save();
        }
        notifyListeners();
      });
      _player.onPlayerStateChanged.listen((value) {
        isPlaying = value == PlayerState.playing;
        notifyListeners();
      });
      _player.onPlayerComplete.listen((_) => next());
    } else {
      _background.mediaItem.listen((item) {
        currentId = item?.id;
        duration = item?.duration ?? Duration.zero;
        if (item == null) {
          position = Duration.zero;
          isPlaying = false;
        }
        notifyListeners();
      });
      _background.playbackState.listen((state) {
        position = state.updatePosition;
        isPlaying = state.playing;
        notifyListeners();
      });
    }
  }

  static const _key = 'music_library';
  static const supportedExtensions = <String>[
    'mp3',
    'm4a',
    'aac',
    'flac',
    'ogg',
    'opus',
    'wav',
    'webm',
    'ape',
    'aiff',
    'aif',
  ];

  final StorageService _storage;
  final audio_service.AudioHandler? _background;
  final AudioPlayer _player = AudioPlayer();
  final Uuid _uuid = const Uuid();
  final List<MusicTrack> tracks = [];
  final List<MusicPlaylist> playlists = [];
  final List<String> _queue = [];

  String? currentId;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;
  bool busy = false;
  String? error;

  MusicTrack? get currentTrack => currentId == null
      ? null
      : tracks.where((track) => track.id == currentId).firstOrNull;

  Future<Directory> get _directory async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'music'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> load() async {
    final json = _storage.readJson(_key);
    if (json == null) return;
    tracks
      ..clear()
      ..addAll((json['tracks'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => MusicTrack.fromJson(Map<String, dynamic>.from(item)))
          .where((track) => track.id.isNotEmpty && track.path.isNotEmpty));
    playlists
      ..clear()
      ..addAll((json['playlists'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => MusicPlaylist.fromJson(Map<String, dynamic>.from(item)))
          .where((playlist) => playlist.id.isNotEmpty));
    final missing = tracks.where((track) => !File(track.path).existsSync()).map((track) => track.id).toSet();
    var changed = missing.isNotEmpty;
    if (missing.isNotEmpty) {
      tracks.removeWhere((track) => missing.contains(track.id));
      for (final playlist in playlists) {
        playlist.trackIds.removeWhere(missing.contains);
      }
    }
    // Older library entries did not persist embedded artwork. Enrich them
    // once on load so covers survive both app restarts and the original file
    // being moved or deleted.
    final needsArtwork = tracks.where((track) =>
        track.artworkPath == null || !File(track.artworkPath!).existsSync());
    if (needsArtwork.isNotEmpty) {
      final directory = await _directory;
      for (final track in needsArtwork) {
        final metadata = _readMetadata(File(track.path), getImage: true);
        final artwork = await _saveArtwork(metadata, directory, track.id);
        if (artwork != null) {
          track.artworkPath = artwork;
          changed = true;
        }
      }
    }
    if (changed) await _save();
    _queue
      ..clear()
      ..addAll(tracks.map((track) => track.id));
    notifyListeners();
  }

  Future<List<MusicTrack>> importFiles() async {
    if (busy) return const [];
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
    );
    if (picked.isEmpty) return const [];
    busy = true;
    error = null;
    notifyListeners();
    final added = <MusicTrack>[];
    try {
      final directory = await _directory;
      for (final item in picked) {
        final sourcePath = item.path;
        if (sourcePath == null || sourcePath.isEmpty) continue;
        final source = File(sourcePath);
        if (!source.existsSync()) continue;
        if (tracks.any((track) => track.path == source.path)) continue;
        final id = _uuid.v4();
        final extension = p.extension(source.path).toLowerCase();
        final base = _safeName(p.basenameWithoutExtension(source.path));
        var destination = File(p.join(directory.path, '$base$extension'));
        if (destination.existsSync()) destination = File(p.join(directory.path, '$id$extension'));
        if (source.path != destination.path) await source.copy(destination.path);
        final metadata = _readMetadata(destination, getImage: true);
        final artworkPath = await _saveArtwork(metadata, directory, id);
        final fallback = _fallbackNames(p.basenameWithoutExtension(source.path));
        final track = MusicTrack(
          id: id,
          path: destination.path,
          title: _clean(metadata?.title) ?? fallback.title,
          artist: _clean(metadata?.artist) ?? fallback.artist,
          album: _clean(metadata?.album) ?? '',
          size: await destination.length(),
          durationMs: metadata?.duration?.inMilliseconds,
          artworkPath: artworkPath,
          addedAt: DateTime.now(),
        );
        tracks.add(track);
        added.add(track);
      }
      await _save();
      notifyListeners();
      return added;
    } catch (e) {
      error = '$e';
      notifyListeners();
      return added;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  AudioMetadata? _readMetadata(File file, {required bool getImage}) {
    try {
      return readMetadata(file, getImage: getImage);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _saveArtwork(AudioMetadata? metadata, Directory musicDirectory, String id) async {
    final pictures = metadata?.pictures ?? const [];
    if (pictures.isEmpty) return null;
    final picture = pictures.firstWhere(
      (item) => item.bytes.isNotEmpty,
      orElse: () => pictures.first,
    );
    if (picture.bytes.isEmpty || picture.bytes.length > 12 * 1024 * 1024) return null;
    final extension = switch (picture.mimetype.toLowerCase()) {
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      _ => '.jpg',
    };
    try {
      final directory = Directory(p.join(musicDirectory.path, 'artwork'));
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, '$id$extension'));
      await file.writeAsBytes(picture.bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static ({String title, String artist}) _fallbackNames(String filename) {
    final clean = filename.trim();
    final match = RegExp(r'^(.+?)\s+[-–—]\s+(.+)$').firstMatch(clean);
    if (match != null) {
      return (
        artist: match.group(1)!.trim(),
        title: match.group(2)!.trim(),
      );
    }
    return (title: clean, artist: '');
  }

  static String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  static String _safeName(String value) {
    final clean = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    if (clean.isEmpty) return 'track';
    final limit = clean.length > 120 ? 120 : clean.length;
    return clean.substring(0, limit);
  }

  Future<void> play(MusicTrack track, {List<String>? queue}) async {
    if (!File(track.path).existsSync()) {
      error = 'musicFileMissing';
      notifyListeners();
      return;
    }
    if (queue != null) {
      _queue
        ..clear()
        ..addAll(queue);
    } else if (_queue.isEmpty) {
      _queue.addAll(tracks.map((item) => item.id));
    }
    final orderedIds = _queue.where((id) => tracks.any((item) => item.id == id)).toList();
    if (!orderedIds.contains(track.id)) orderedIds.add(track.id);
    if (_background != null) {
      final items = orderedIds
          .map((id) => tracks.where((item) => item.id == id).firstOrNull)
          .whereType<MusicTrack>()
          .toList();
      _queue
        ..clear()
        ..addAll(items.map((item) => item.id));
      await _background.customAction('loadQueue', {
        'index': _queue.indexOf(track.id),
        'items': [
          for (final item in items)
            {
              'id': item.id,
              'path': item.path,
              'title': item.title,
              'artist': item.artist,
              'album': item.album,
              'durationMs': item.durationMs,
              'artworkPath': item.artworkPath,
            },
        ],
      });
      currentId = track.id;
      position = Duration.zero;
      duration = track.durationMs == null ? Duration.zero : Duration(milliseconds: track.durationMs ?? 0);
      notifyListeners();
      return;
    }
    await _player.stop();
    await _player.setSourceDeviceFile(track.path);
    currentId = track.id;
    position = Duration.zero;
    duration = track.durationMs == null ? Duration.zero : Duration(milliseconds: track.durationMs ?? 0);
    await _player.resume();
    notifyListeners();
  }

  Future<void> toggle() async {
    if (currentTrack == null) return;
    if (_background != null) {
      if (isPlaying) {
        await _background.pause();
      } else {
        await _background.play();
      }
    } else if (isPlaying) {
      await _player.pause();
    } else {
      await _player.resume();
    }
    notifyListeners();
  }

  Future<void> seek(Duration value) => _background != null ? _background.seek(value) : _player.seek(value);

  Future<void> previous() async {
    if (position > const Duration(seconds: 4)) {
      await seek(Duration.zero);
      return;
    }
    if (_background != null) {
      await _background.skipToPrevious();
      return;
    }
    final index = _queue.indexOf(currentId ?? '');
    if (index > 0) {
      final track = tracks.where((item) => item.id == _queue[index - 1]).firstOrNull;
      if (track != null) await play(track);
    } else {
      await seek(Duration.zero);
    }
  }

  Future<void> next() async {
    if (_background != null) {
      await _background.skipToNext();
      return;
    }
    final index = _queue.indexOf(currentId ?? '');
    if (index >= 0 && index + 1 < _queue.length) {
      final track = tracks.where((item) => item.id == _queue[index + 1]).firstOrNull;
      if (track != null) await play(track);
      return;
    }
    await _player.stop();
    isPlaying = false;
    notifyListeners();
  }

  Future<void> stop() async {
    if (_background != null) {
      await _background.stop();
    } else {
      await _player.stop();
    }
    currentId = null;
    position = Duration.zero;
    duration = Duration.zero;
    isPlaying = false;
    notifyListeners();
  }

  Future<void> removeTrack(MusicTrack track) async {
    if (track.id == currentId) await stop();
    final file = File(track.path);
    if (file.existsSync()) await file.delete();
    final artwork = track.artworkPath == null ? null : File(track.artworkPath!);
    if (artwork != null && artwork.existsSync()) await artwork.delete();
    tracks.removeWhere((item) => item.id == track.id);
    for (final playlist in playlists) {
      playlist.trackIds.remove(track.id);
    }
    await _save();
    notifyListeners();
  }

  Future<void> renameTrack(MusicTrack track, String title, String artist) async {
    track.title = title.trim().isEmpty ? track.title : title.trim();
    track.artist = artist.trim();
    await _save();
    notifyListeners();
  }

  /// Reorders the visible queue and persists the resulting library order.
  /// [newIndex] follows ReorderableListView's legacy callback: it is the
  /// insertion index before the dragged item is removed and may equal the
  /// list length when dropped after the last row.
  Future<void> reorder(int oldIndex, int newIndex, List<MusicTrack> visible) async {
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    final reordered = List<MusicTrack>.from(visible);
    final moving = reordered.removeAt(oldIndex);
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex > reordered.length) return;
    reordered.insert(newIndex, moving);
    final visibleIds = visible.map((track) => track.id).toSet();
    final hidden = tracks.where((track) => !visibleIds.contains(track.id)).toList();
    tracks
      ..clear()
      ..addAll(reordered)
      ..addAll(hidden);
    _queue
      ..clear()
      ..addAll(tracks.map((track) => track.id));
    await _save();
    notifyListeners();
  }

  Future<MusicPlaylist> createPlaylist(String name, {String icon = 'music_note'}) async {
    final playlist = MusicPlaylist(
      id: _uuid.v4(),
      name: name.trim(),
      icon: icon,
      trackIds: <String>[],
      createdAt: DateTime.now(),
    );
    playlists.add(playlist);
    await _save();
    notifyListeners();
    return playlist;
  }

  Future<void> renamePlaylist(MusicPlaylist playlist, String name, String icon) async {
    if (name.trim().isNotEmpty) playlist.name = name.trim();
    playlist.icon = icon;
    await _save();
    notifyListeners();
  }

  Future<void> deletePlaylist(MusicPlaylist playlist) async {
    playlists.removeWhere((item) => item.id == playlist.id);
    await _save();
    notifyListeners();
  }

  Future<void> setTrackInPlaylist(MusicPlaylist playlist, String trackId, bool selected) async {
    if (selected) {
      if (!playlist.trackIds.contains(trackId)) playlist.trackIds.add(trackId);
    } else {
      playlist.trackIds.remove(trackId);
    }
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    await _storage.writeJson(_key, {
      'tracks': tracks.map((track) => track.toJson()).toList(),
      'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
