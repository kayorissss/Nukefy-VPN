import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/music_service.dart';
import '../../core/theme/app_colors.dart;
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../l10n/strings.dart';
import '../widgets/nukefy_background.dart';
import '../widgets/responsive_sections.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

enum _MusicView { list, table, grid }

class _MusicScreenState extends State<MusicScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  _MusicView _view = _MusicView.list;
  bool _newestFirst = true;
  String? _playlistId;
  String? _selectedId;

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<MusicTrack> _visible(MusicService music) {
    final query = _search.text.trim().toLowerCase();
    final playlist = _playlistId == null
        ? null
        : music.playlists.where((item) => item.id == _playlistId).firstOrNull;
    final source = playlist == null
        ? [...music.tracks]
        : [
            for (final id in playlist.trackIds)
              music.tracks.where((track) => track.id == id).firstOrNull,
          ].whereType<MusicTrack>().toList();
    source.removeWhere((track) => query.isNotEmpty &&
        !'${track.title} ${track.artist} ${track.album}'.toLowerCase().contains(query));
    source.sort((a, b) => _newestFirst
        ? b.addedAt.compareTo(a.addedAt)
        : a.addedAt.compareTo(b.addedAt));
    return source;
  }

  Future<void> _import() async {
    final music = context.read<MusicService>();
    final added = await music.importFiles();
    if (!mounted || added.isEmpty) return;
    setState(() => _selectedId = added.first.id);
    final s = context.read<SettingsProvider>().strings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${added.length} ${s.t('musicImported')}')),
    );
  }

  void _keyboardDelete(MusicService music) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext?.findAncestorWidgetOfExactType<EditableText>() != null) return;
    _deleteSelected(music);
  }

  Future<void> _deleteSelected(MusicService music) async {
    final id = _selectedId ?? music.currentId;
    final track = id == null ? null : music.tracks.where((item) => item.id == id).firstOrNull;
    if (track == null) return;
    final s = context.read<SettingsProvider>().strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.t('musicDeleteTitle')),
        content: Text('${s.t('musicDeleteBody')}\n\n${track.title}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(s.t('delete'))),
        ],
      ),
    );
    if (confirmed == true) {
      await music.removeTrack(track);
      if (mounted) setState(() => _selectedId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicService>();
    final s = context.watch<SettingsProvider>().strings;
    final visible = _visible(music);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.delete): () => _keyboardDelete(music),
        const SingleActivator(LogicalKeyboardKey.backspace): () => _keyboardDelete(music),
        const SingleActivator(LogicalKeyboardKey.keyB): () => _keyboardDelete(music),
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: NukefyBackground(
          child: SafeArea(
            bottom: false,
            child: ResponsiveFrame(
              maxWidth: 1500,
              child: Column(
                children: [
                  _Header(
                    title: s.t('music'),
                    count: music.tracks.length,
                    importLabel: s.t('musicImport'),
                    onImport: music.busy ? null : _import,
                    onCreatePlaylist: () => _editPlaylist(context, music, null),
                  ),
                  _Toolbar(
                    search: _search,
                    hint: s.t('musicSearch'),
                    view: _view,
                    newestFirst: _newestFirst,
                    onQuery: (_) => setState(() {}),
                    onView: (value) => setState(() => _view = value),
                    onSort: () => setState(() => _newestFirst = !_newestFirst),
                    sortLabel: _newestFirst ? s.t('musicNewest') : s.t('musicOldest'),
                  ),
                  _PlaylistBar(
                    playlists: music.playlists,
                    selectedId: _playlistId,
                    allLabel: s.t('musicAllTracks'),
                    onSelected: (id) => setState(() => _playlistId = id),
                    onCreate: () => _editPlaylist(context, music, null),
                    onEdit: (playlist) => _editPlaylist(context, music, playlist),
                  ),
                  if (music.error != null)
                    _ErrorBanner(message: music.error!, onClose: () => music.error = null),
                  Expanded(
                    child: visible.isEmpty
                        ? _EmptyMusic(onImport: music.busy ? null : _import, label: s.t('musicEmpty'))
                        : _MusicCollection(
                            tracks: visible,
                            view: _view,
                            selectedId: _selectedId,
                            music: music,
                            onSelected: (id) => setState(() => _selectedId = id),
                            onDelete: _deleteSelected,
                            onEdit: (track) => _editTrack(context, music, track),
                            onPlaylist: (track) => _trackPlaylists(context, music, track),
                            onReorder: (oldIndex, newIndex) => music.reorder(oldIndex, newIndex, visible),
                          ),
                  ),
                  if (music.currentTrack != null) _NowPlaying(music: music),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editTrack(BuildContext context, MusicService music, MusicTrack track) async {
    final s = context.read<SettingsProvider>().strings;
    final title = TextEditingController(text: track.title);
    final artist = TextEditingController(text: track.artist);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.t('musicEditTrack')),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: InputDecoration(labelText: s.t('musicTitle'))),
              const SizedBox(height: 12),
              TextField(controller: artist, decoration: InputDecoration(labelText: s.t('musicArtist'))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(s.t('save'))),
        ],
      ),
    );
    if (result == true) await music.renameTrack(track, title.text, artist.text);
    title.dispose();
    artist.dispose();
  }

  Future<void> _editPlaylist(BuildContext context, MusicService music, MusicPlaylist? playlist) async {
    final s = context.read<SettingsProvider>().strings;
    final name = TextEditingController(text: playlist?.name ?? '');
    var icon = playlist?.icon ?? 'music_note';
    final result = await showDialog<({String name, String icon})>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialogState) => AlertDialog(
          title: Text(playlist == null ? s.t('musicNewPlaylist') : s.t('musicEditPlaylist')),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: s.t('musicPlaylistName'))),
                const SizedBox(height: 16),
                Text(s.t('musicPlaylistIcon'), style: context.palette.secondaryStyle),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in const ['music_note', 'favorite', 'headphones', 'bolt', 'nightlife', 'star'])
                      IconButton.filledTonal(
                        isSelected: icon == value,
                        onPressed: () => setDialogState(() => icon = value),
                        icon: Icon(_playlistIcon(value)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (playlist != null)
              TextButton(
                onPressed: () async {
                  final yes = await _confirm(context, s.t('musicDeletePlaylistTitle'), s.t('musicDeletePlaylistBody'));
                  if (yes == true && dialog.mounted) Navigator.pop(dialog, null);
                  if (yes == true) await music.deletePlaylist(playlist);
                },
                child: Text(s.t('delete'), style: TextStyle(color: context.palette.error)),
              ),
            TextButton(onPressed: () => Navigator.pop(dialog), child: Text(s.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialog, (name: name.text, icon: icon)), child: Text(s.t('save'))),
          ],
        ),
      ),
    );
    if (result == null) return;
    if (playlist == null) {
      await music.createPlaylist(result.name, icon: result.icon);
    } else {
      await music.renamePlaylist(playlist, result.name, result.icon);
    }
    name.dispose();
  }

  Future<void> _trackPlaylists(BuildContext context, MusicService music, MusicTrack track) async {
    final s = context.read<SettingsProvider>().strings;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('musicAddToPlaylist'), style: AppTextStyles.headline),
              const SizedBox(height: 8),
              if (music.playlists.isEmpty) Text(s.t('musicNoPlaylists'), style: context.palette.secondaryStyle),
              for (final playlist in music.playlists)
                CheckboxListTile(
                  value: playlist.trackIds.contains(track.id),
                  title: Text(playlist.name),
                  secondary: Icon(_playlistIcon(playlist.icon)),
                  onChanged: (value) async {
                    await music.setTrackInPlaylist(playlist, track.id, value == true);
                  },
                ),
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(sheet);
                  await _editPlaylist(context, music, null);
                },
                icon: const Icon(Icons.add),
                label: Text(s.t('musicNewPlaylist')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirm(BuildContext context, String title, String body) => showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(context.read<SettingsProvider>().strings.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(context.read<SettingsProvider>().strings.t('delete'))),
          ],
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.count, required this.importLabel, required this.onImport, required this.onCreatePlaylist});
  final String title;
  final int count;
  final String importLabel;
  final VoidCallback? onImport;
  final VoidCallback onCreatePlaylist;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [p.accent, p.accent2]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.library_music_rounded, color: p.isDark ? const Color(0xFF07131A) : Colors.white, size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTextStyles.title),
              const SizedBox(height: 3),
              Text('$count', style: context.palette.secondaryStyle),
            ]),
          ),
          IconButton(tooltip: context.read<SettingsProvider>().strings.t('musicNewPlaylist'), onPressed: onCreatePlaylist, icon: const Icon(Icons.playlist_add_rounded)),
          FilledButton.icon(onPressed: onImport, icon: const Icon(Icons.add_rounded), label: Text(importLabel)),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.search, required this.hint, required this.view, required this.newestFirst, required this.onQuery, required this.onView, required this.onSort, required this.sortLabel});
  final TextEditingController search;
  final String hint;
  final _MusicView view;
  final bool newestFirst;
  final ValueChanged<String> onQuery;
  final ValueChanged<_MusicView> onView;
  final VoidCallback onSort;
  final String sortLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 360,
            child: TextField(
              controller: search,
              onChanged: onQuery,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: hint, isDense: true),
            ),
          ),
          OutlinedButton.icon(onPressed: onSort, icon: Icon(newestFirst ? Icons.south_rounded : Icons.north_rounded, size: 18), label: Text(sortLabel)),
          SegmentedButton<_MusicView>(
            segments: const [
              ButtonSegment(value: _MusicView.list, icon: Icon(Icons.view_list_rounded)),
              ButtonSegment(value: _MusicView.table, icon: Icon(Icons.table_rows_rounded)),
              ButtonSegment(value: _MusicView.grid, icon: Icon(Icons.grid_view_rounded)),
            ],
            selected: {view},
            onSelectionChanged: (value) => onView(value.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              foregroundColor: WidgetStatePropertyAll(p.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistBar extends StatelessWidget {
  const _PlaylistBar({required this.playlists, required this.selectedId, required this.allLabel, required this.onSelected, required this.onCreate, required this.onEdit});
  final List<MusicPlaylist> playlists;
  final String? selectedId;
  final String allLabel;
  final ValueChanged<String?> onSelected;
  final VoidCallback onCreate;
  final ValueChanged<MusicPlaylist> onEdit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        scrollDirection: Axis.horizontal,
        children: [
          _PlaylistChip(label: allLabel, icon: Icons.library_music_rounded, selected: selectedId == null, onTap: () => onSelected(null)),
          for (final playlist in playlists)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _PlaylistChip(label: playlist.name, icon: _playlistIcon(playlist.icon), selected: selectedId == playlist.id, onTap: () => onSelected(playlist.id), onLongPress: () => onEdit(playlist)),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ActionChip(avatar: const Icon(Icons.add, size: 17), label: Text(context.read<SettingsProvider>().strings.t('musicNewPlaylist')), onPressed: onCreate),
          ),
        ],
      ),
    );
  }
}

class _PlaylistChip extends StatelessWidget {
  const _PlaylistChip({required this.label, required this.icon, required this.selected, required this.onTap, this.onLongPress});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? p.accent.withValues(alpha: .14) : p.card,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: selected ? p.accent.withValues(alpha: .55) : p.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 17, color: selected ? p.accent : p.textSecondary), const SizedBox(width: 7), Text(label, style: AppTextStyles.bodySecondary.copyWith(color: selected ? p.text : p.textSecondary, fontWeight: FontWeight.w700))]),
      ),
    );
  }
}

class _MusicCollection extends StatelessWidget {
  const _MusicCollection({required this.tracks, required this.view, required this.selectedId, required this.music, required this.onSelected, required this.onDelete, required this.onEdit, required this.onPlaylist, required this.onReorder});
  final List<MusicTrack> tracks;
  final _MusicView view;
  final String? selectedId;
  final MusicService music;
  final ValueChanged<String?> onSelected;
  final Future<void> Function(MusicService music) onDelete;
  final ValueChanged<MusicTrack> onEdit;
  final ValueChanged<MusicTrack> onPlaylist;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    final padding = const EdgeInsets.fromLTRB(20, 8, 20, 16);
    if (view == _MusicView.grid) {
      return GridView.builder(
        padding: padding,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 330, mainAxisExtent: 186, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: tracks.length,
        itemBuilder: (context, index) => _TrackCard(track: tracks[index], selected: selectedId == tracks[index].id, music: music, onSelected: onSelected, onDelete: onDelete, onEdit: onEdit, onPlaylist: onPlaylist),
      );
    }
    if (view == _MusicView.table) {
      return ListView(
        padding: padding,
        children: [
          _TableHeader(),
          for (var index = 0; index < tracks.length; index++)
            _TrackRow(track: tracks[index], index: index + 1, selected: selectedId == tracks[index].id, music: music, onSelected: onSelected, onDelete: onDelete, onEdit: onEdit, onPlaylist: onPlaylist),
        ],
      );
    }
    return ReorderableListView.builder(
      padding: padding,
      itemCount: tracks.length,
      onReorder: onReorder,
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return _TrackRow(
          key: ValueKey(track.id),
          track: track,
          index: index + 1,
          selected: selectedId == track.id,
          music: music,
          onSelected: onSelected,
          onDelete: onDelete,
          onEdit: onEdit,
          onPlaylist: onPlaylist,
          drag: ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_indicator_rounded)),
        );
      },
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Text(context.read<SettingsProvider>().strings.t('musicTableHint'), style: context.palette.captionStyle),
      );
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({super.key, required this.track, required this.index, required this.selected, required this.music, required this.onSelected, required this.onDelete, required this.onEdit, required this.onPlaylist, this.drag});
  final MusicTrack track;
  final int index;
  final bool selected;
  final MusicService music;
  final ValueChanged<String?> onSelected;
  final Future<void> Function(MusicService music) onDelete;
  final ValueChanged<MusicTrack> onEdit;
  final ValueChanged<MusicTrack> onPlaylist;
  final Widget? drag;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final current = music.currentId == track.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: selected || current ? p.accent.withValues(alpha: .11) : p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: selected || current ? p.accent.withValues(alpha: .45) : p.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            onSelected(track.id);
            music.play(track);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              if (drag != null) ...[drag!, const SizedBox(width: 4)],
              SizedBox(width: 28, child: Text('$index', style: context.palette.captionStyle)),
              _MusicArtwork(track: track, size: 44),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w800)), Text(track.artist.isEmpty ? context.read<SettingsProvider>().strings.t('musicUnknownArtist') : track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.palette.secondaryStyle)])),
              if (MediaQuery.sizeOf(context).width > 900) ...[SizedBox(width: 170, child: Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.palette.secondaryStyle)), SizedBox(width: 90, child: Text(FormatUtils.bytes(track.size), style: context.palette.captionStyle))],
              SizedBox(width: 68, child: Text(_duration(track), textAlign: TextAlign.end, style: context.palette.captionStyle)),
              IconButton(tooltip: context.read<SettingsProvider>().strings.t('musicAddToPlaylist'), onPressed: () => onPlaylist(track), icon: const Icon(Icons.playlist_add_rounded, size: 20)),
              IconButton(tooltip: context.read<SettingsProvider>().strings.t('edit'), onPressed: () => onEdit(track), icon: const Icon(Icons.edit_outlined, size: 18)),
              IconButton(tooltip: context.read<SettingsProvider>().strings.t('delete'), onPressed: () => onDelete(music), icon: Icon(Icons.delete_outline_rounded, color: p.error, size: 20)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({required this.track, required this.selected, required this.music, required this.onSelected, required this.onDelete, required this.onEdit, required this.onPlaylist});
  final MusicTrack track;
  final bool selected;
  final MusicService music;
  final ValueChanged<String?> onSelected;
  final Future<void> Function(MusicService music) onDelete;
  final ValueChanged<MusicTrack> onEdit;
  final ValueChanged<MusicTrack> onPlaylist;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: selected ? p.accent.withValues(alpha: .12) : p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: selected ? p.accent.withValues(alpha: .55) : p.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          onSelected(track.id);
          music.play(track);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            _MusicArtwork(track: track, size: 70),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(track.artist.isEmpty ? context.read<SettingsProvider>().strings.t('musicUnknownArtist') : track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.palette.secondaryStyle), const SizedBox(height: 8), Text('${_duration(track)} · ${FormatUtils.bytes(track.size)}', style: context.palette.captionStyle)])),
            PopupMenuButton<String>(onSelected: (value) { if (value == 'playlist') onPlaylist(track); if (value == 'edit') onEdit(track); if (value == 'delete') onDelete(music); }, itemBuilder: (context) => [PopupMenuItem(value: 'playlist', child: Text(context.read<SettingsProvider>().strings.t('musicAddToPlaylist'))), PopupMenuItem(value: 'edit', child: Text(context.read<SettingsProvider>().strings.t('edit'))), PopupMenuItem(value: 'delete', child: Text(context.read<SettingsProvider>().strings.t('delete')))]),
          ]),
        ),
      ),
    );
  }
}

class _MusicArtwork extends StatelessWidget {
  const _MusicArtwork({required this.track, required this.size});
  final MusicTrack track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.accent.withValues(alpha: .9), p.accent2.withValues(alpha: .9)]),
        borderRadius: BorderRadius.circular(size * .24),
      ),
      child: Icon(Icons.music_note_rounded, color: p.isDark ? const Color(0xFF07131A) : Colors.white, size: size * .47),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.music});
  final MusicService music;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final track = music.currentTrack!;
    final max = music.duration.inMilliseconds <= 0 ? 1.0 : music.duration.inMilliseconds.toDouble();
    final value = music.position.inMilliseconds.clamp(0, max.toInt()).toDouble();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 8),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.accent.withValues(alpha: .45)), boxShadow: [BoxShadow(color: p.accent.withValues(alpha: .08), blurRadius: 20)]),
      child: Column(children: [
        Row(children: [_MusicArtwork(track: track, size: 42), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w800)), Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.palette.secondaryStyle)])), IconButton(onPressed: music.previous, icon: const Icon(Icons.skip_previous_rounded)), IconButton(onPressed: music.toggle, icon: Icon(music.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, size: 32, color: p.accent)), IconButton(onPressed: music.next, icon: const Icon(Icons.skip_next_rounded))]),
        Row(children: [Text(_formatDuration(music.position), style: context.palette.captionStyle), Expanded(child: Slider(value: value, max: max, onChanged: (value) => music.seek(Duration(milliseconds: value.round())))), Text(_formatDuration(music.duration), style: context.palette.captionStyle)]),
      ]),
    );
  }
}

class _EmptyMusic extends StatelessWidget {
  const _EmptyMusic({required this.onImport, required this.label});
  final VoidCallback? onImport;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 90, height: 90, decoration: BoxDecoration(color: p.accent.withValues(alpha: .12), shape: BoxShape.circle), child: Icon(Icons.library_music_outlined, size: 46, color: p.accent)), const SizedBox(height: 18), Text(label, style: AppTextStyles.headline), const SizedBox(height: 14), FilledButton.icon(onPressed: onImport, icon: const Icon(Icons.add), label: Text(context.read<SettingsProvider>().strings.t('musicImport')))]));
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 4), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: context.palette.error.withValues(alpha: .10), borderRadius: BorderRadius.circular(12), border: Border.all(color: context.palette.error.withValues(alpha: .3))), child: Row(children: [Icon(Icons.error_outline_rounded, color: context.palette.error), const SizedBox(width: 8), Expanded(child: Text(message, style: context.palette.secondaryStyle)), IconButton(onPressed: onClose, icon: const Icon(Icons.close, size: 18))])));
}

String _duration(MusicTrack track) => track.durationMs == null ? '—' : _formatDuration(Duration(milliseconds: track.durationMs!));
String _formatDuration(Duration value) => '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';

IconData _playlistIcon(String name) => switch (name) {
      'favorite' => Icons.favorite_rounded,
      'headphones' => Icons.headphones_rounded,
      'bolt' => Icons.bolt_rounded,
      'nightlife' => Icons.nightlife_rounded,
      'star' => Icons.star_rounded,
      _ => Icons.music_note_rounded,
    };
