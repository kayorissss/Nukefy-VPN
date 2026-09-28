import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/music_service.dart';
import '../../core/theme/app_colors.dart';
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
  bool _customOrder = false;
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
    if (!_customOrder) {
      source.sort((a, b) => _newestFirst
          ? b.addedAt.compareTo(a.addedAt)
          : a.addedAt.compareTo(b.addedAt));
    } else {
      final order = <String, int>{
        for (var index = 0; index < music.tracks.length; index++) music.tracks[index].id: index,
      };
      source.sort((a, b) => (order[a.id] ?? 0).compareTo(order[b.id] ?? 0));
    }
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
        content: Text('${s.t('musicDeleteBody')}\n\n${_trackTitle(track, s)}'),
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
                    onSort: () => setState(() {
                      _newestFirst = !_newestFirst;
                      _customOrder = false;
                    }),
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
                    _ErrorBanner(message: _musicErrorText(music.error!, s), onClose: () => music.error = null),
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
                            onReorder: (oldIndex, newIndex) {
                              music.reorder(oldIndex, newIndex, visible);
                              if (mounted) setState(() => _customOrder = true);
                            },
                          ),
                  ),
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
    if (result == null) {
      name.dispose();
      return;
    }
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
                  title: Text(_playlistName(playlist, s)),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final heading = Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [p.accent, p.accent2]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.library_music_rounded, color: p.isDark ? Colors.black : Colors.white, size: 25),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.title),
                  const SizedBox(height: 3),
                  Text('$count', style: context.palette.secondaryStyle),
                ],
              ),
            ),
            IconButton(
              tooltip: context.read<SettingsProvider>().strings.t('musicNewPlaylist'),
              onPressed: onCreatePlaylist,
              icon: const Icon(Icons.playlist_add_rounded),
            ),
          ],
        );
        final import = SizedBox(
          width: compact ? double.infinity : null,
          child: FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add_rounded),
            label: Text(importLabel),
          ),
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(20, compact ? 12 : 18, 20, 10),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [heading, const SizedBox(height: 10), import],
                )
              : Row(children: [Expanded(child: heading), const SizedBox(width: 12), import]),
        );
      },
    );
  }
}

class _Toolbar extends StatefulWidget {
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
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  late bool _searchOpen = widget.search.text.isNotEmpty;

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (!_searchOpen && widget.search.text.isNotEmpty) {
      widget.search.clear();
      widget.onQuery('');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarIcon(
              tooltip: widget.hint,
              icon: Icons.search_rounded,
              selected: _searchOpen,
              onPressed: _toggleSearch,
            ),
            const SizedBox(width: 6),
            _ToolbarIcon(
              tooltip: widget.sortLabel,
              icon: widget.newestFirst ? Icons.south_rounded : Icons.north_rounded,
              onPressed: widget.onSort,
            ),
            const SizedBox(width: 8),
            SegmentedButton<_MusicView>(
              segments: const [
                ButtonSegment(value: _MusicView.list, icon: Icon(Icons.view_list_rounded)),
                ButtonSegment(value: _MusicView.table, icon: Icon(Icons.table_rows_rounded)),
                ButtonSegment(value: _MusicView.grid, icon: Icon(Icons.grid_view_rounded)),
              ],
              selected: {widget.view},
              onSelectionChanged: (value) => widget.onView(value.first),
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 5)),
                foregroundColor: WidgetStatePropertyAll(p.text),
                side: WidgetStatePropertyAll(BorderSide(color: p.border)),
              ),
            ),
          ],
        );
        final searchField = TextField(
          controller: widget.search,
          autofocus: _searchOpen,
          onChanged: widget.onQuery,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(onPressed: _toggleSearch, icon: const Icon(Icons.close_rounded)),
            hintText: widget.hint,
            isDense: true,
          ),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(alignment: AlignmentDirectional.centerEnd, child: controls),
                    if (_searchOpen) ...[const SizedBox(height: 7), searchField],
                  ],
                )
              : Row(
                  children: [
                    if (_searchOpen) Expanded(child: searchField) else const Spacer(),
                    if (_searchOpen) const SizedBox(width: 8),
                    controls,
                  ],
                ),
        );
      },
    );
  }
}

class _ToolbarIcon extends StatelessWidget {
  const _ToolbarIcon({required this.tooltip, required this.icon, required this.onPressed, this.selected = false});
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? p.accent.withValues(alpha: .14) : p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: selected ? p.accent.withValues(alpha: .55) : p.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 19, color: selected ? p.accent : p.textSecondary)),
        ),
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
              child: _PlaylistChip(label: _playlistName(playlist, context.read<SettingsProvider>().strings), icon: _playlistIcon(playlist.icon), selected: selectedId == playlist.id, onTap: () => onSelected(playlist.id), onLongPress: () => onEdit(playlist)),
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

  void _playOrPause() {
    onSelected(track.id);
    if (music.currentId == track.id) {
      music.toggle();
    } else {
      music.play(track);
    }
  }

  Widget _menu(BuildContext context) {
    final s = context.read<SettingsProvider>().strings;
    final p = context.palette;
    return PopupMenuButton<String>(
      tooltip: s.t('more'),
      onSelected: (value) {
        if (value == 'playlist') onPlaylist(track);
        if (value == 'edit') onEdit(track);
        if (value == 'delete') {
          onSelected(track.id);
          onDelete(music);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'playlist', child: Text(s.t('musicAddToPlaylist'))),
        PopupMenuItem(value: 'edit', child: Text(s.t('edit'))),
        PopupMenuItem(value: 'delete', child: Text(s.t('delete'), style: TextStyle(color: p.error))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = context.read<SettingsProvider>().strings;
    final title = _trackTitle(track, s);
    final current = music.currentId == track.id;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected || current ? p.accent.withValues(alpha: .11) : p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17), side: BorderSide(color: selected || current ? p.accent.withValues(alpha: .45) : p.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: _playOrPause,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 7 : 8),
            child: compact
                ? Row(
                    children: [
                      if (drag != null) ...[drag!, const SizedBox(width: 2)],
                      SizedBox(width: 22, child: Text('$index', style: context.palette.captionStyle)),
                      _MusicArtwork(track: track, size: 46),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(track.artist.isEmpty ? s.t('musicUnknownArtist') : track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.palette.secondaryStyle),
                            const SizedBox(height: 2),
                            Text(_duration(track), style: context.palette.captionStyle),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: current && music.isPlaying ? s.t('musicPause') : s.t('musicPlay'),
                        onPressed: _playOrPause,
                        icon: Icon(current && music.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: p.accent, size: 29),
                      ),
                      _menu(context),
                    ],
                  )
                : Row(
                    children: [
                      if (drag != null) ...[drag!, const SizedBox(width: 4)],
                      SizedBox(width: 28, child: Text('$index', style: context.palette.captionStyle)),
                      _MusicArtwork(track: track, size: 44),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w800)), Text(track.artist.isEmpty ? s.t('musicUnknownArtist') : track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.palette.secondaryStyle)])),
                      if (MediaQuery.sizeOf(context).width > 900) ...[SizedBox(width: 170, child: Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.palette.secondaryStyle)), SizedBox(width: 90, child: Text(FormatUtils.bytes(track.size), style: context.palette.captionStyle))],
                      SizedBox(width: 68, child: Text(_duration(track), textAlign: TextAlign.end, style: context.palette.captionStyle)),
                      IconButton(tooltip: s.t('musicAddToPlaylist'), onPressed: () => onPlaylist(track), icon: const Icon(Icons.playlist_add_rounded, size: 20)),
                      IconButton(tooltip: s.t('edit'), onPressed: () => onEdit(track), icon: const Icon(Icons.edit_outlined, size: 18)),
                      IconButton(tooltip: s.t('delete'), onPressed: () { onSelected(track.id); onDelete(music); }, icon: Icon(Icons.delete_outline_rounded, color: p.error, size: 20)),
                    ],
                  ),
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
    final s = context.read<SettingsProvider>().strings;
    final title = _trackTitle(track, s);
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
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(track.artist.isEmpty ? s.t('musicUnknownArtist') : track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.palette.secondaryStyle), const SizedBox(height: 8), Text('${_duration(track)} · ${FormatUtils.bytes(track.size)}', style: context.palette.captionStyle)])),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'playlist') onPlaylist(track);
                if (value == 'edit') onEdit(track);
                if (value == 'delete') {
                  onSelected(track.id);
                  onDelete(music);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'playlist', child: Text(context.read<SettingsProvider>().strings.t('musicAddToPlaylist'))),
                PopupMenuItem(value: 'edit', child: Text(context.read<SettingsProvider>().strings.t('edit'))),
                PopupMenuItem(value: 'delete', child: Text(context.read<SettingsProvider>().strings.t('delete'))),
              ],
            ),
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
    final artwork = track.artworkPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .24),
      child: artwork == null
          ? Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.accent.withValues(alpha: .9), p.accent2.withValues(alpha: .9)]),
              ),
              child: Icon(Icons.music_note_rounded, color: p.isDark ? Colors.black : Colors.white, size: size * .47),
            )
          : Image.file(
              File(artwork),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: size,
                height: size,
                color: p.surface,
                child: Icon(Icons.broken_image_outlined, color: p.textSecondary, size: size * .42),
              ),
            ),
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

String _trackTitle(MusicTrack track, S s) => track.title.trim().isEmpty ? s.t('musicUntitled') : track.title;
String _playlistName(MusicPlaylist playlist, S s) => playlist.name.trim().isEmpty ? s.t('musicPlaylistDefault') : playlist.name;
String _musicErrorText(String raw, S s) => raw == 'musicFileMissing' ? s.t(raw) : raw;

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
