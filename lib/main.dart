import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import 'app_paths.dart';
import 'image_store.dart';
import 'models.dart';
import 'note_box.dart';
import 'notebook_storage.dart';

// Size of the scrollable page area.
const double kCanvasW = 3000;
const double kCanvasH = 3000;

// Text box colours (body + header), picked with the palette button.
const List<Color> kBoxBody = [
  Color(0xFFFFFFFF),
  Color(0xFFFFF4C2),
  Color(0xFFD9F7E8),
  Color(0xFFDCEBFF),
  Color(0xFFFFE0EA),
  Color(0xFFEBDDFF),
];
const List<Color> kBoxHeader = [
  Color(0xFFE8E8EE),
  Color(0xFFF2DF8C),
  Color(0xFFAEE8CB),
  Color(0xFFB4D2FF),
  Color(0xFFFFB9CF),
  Color(0xFFD0B8FF),
];

// Pen colours. 0 = automatic (black in light mode, white in dark mode).
const List<int> kInkColors = [0, 0xFFE53935, 0xFF1E88E5, 0xFF43A047, 0xFFF9A825];

void main() => runApp(const NotebookApp());

class NotebookApp extends StatefulWidget {
  const NotebookApp({super.key});

  @override
  State<NotebookApp> createState() => _NotebookAppState();
}

class _NotebookAppState extends State<NotebookApp> {
  ThemeMode _mode = ThemeMode.system;

  void _setTheme(ThemeMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pagelark',
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomeScreen(onSetTheme: _setTheme),
    );
  }
}

class _Hit {
  _Hit(this.section, this.page, this.snippet);
  final Section section;
  final NotePage page;
  final String snippet;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onSetTheme});

  final void Function(ThemeMode mode) onSetTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final NotebookStorage _storage = NotebookStorage();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  Notebook _nb = Notebook.starter();
  int? _sectionId;
  int? _pageId;
  bool _loaded = false;
  Timer? _saveTimer;
  Timer? _pollTimer;
  DateTime? _lastModified;
  int _reloadCount = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _query = '';

  Section? get _section {
    for (final s in _nb.sections) {
      if (s.id == _sectionId) return s;
    }
    return null;
  }

  NotePage? get _page {
    final s = _section;
    if (s == null) return null;
    for (final p in s.pages) {
      if (p.id == _pageId) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _load();
    // Every 15 seconds, look for changes made by another computer (via a synced folder).
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkExternalChange(),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _pollTimer?.cancel();
    _saveNow();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // Ctrl/Cmd+N = new page, Ctrl/Cmd+F = search
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final hw = HardwareKeyboard.instance;
    if (!(hw.isControlPressed || hw.isMetaPressed)) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyN) {
      _addPage();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _searchFocus.requestFocus();
      return true;
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveTimer?.cancel();
      _saveNow();
    }
    if (state == AppLifecycleState.resumed) {
      _checkExternalChange();
    }
  }

  Future<void> _load() async {
    final loaded = await _storage.load();
    final modified = await _storage.modified();
    if (!mounted) return;
    setState(() {
      if (loaded != null && loaded.sections.isNotEmpty) _nb = loaded;
      final first = _nb.sections.first;
      _sectionId = first.id;
      _pageId = first.pages.isEmpty ? null : first.pages.first.id;
      _lastModified = modified;
      _loaded = true;
    });
    _applyTheme();
  }

  // The chosen theme is part of the notebook file, so it is remembered.
  void _applyTheme() {
    final mode = _nb.theme == 'dark'
        ? ThemeMode.dark
        : (_nb.theme == 'light' ? ThemeMode.light : ThemeMode.system);
    widget.onSetTheme(mode);
  }

  /// Switch to a notebook loaded from disk, keeping the open page if it still exists.
  void _adopt(Notebook nb) {
    setState(() {
      final oldSection = _sectionId;
      final oldPage = _pageId;
      _nb = nb;
      Section? found;
      for (final x in nb.sections) {
        if (x.id == oldSection) found = x;
      }
      final section = found ?? nb.sections.first;
      _sectionId = section.id;
      NotePage? foundPage;
      for (final x in section.pages) {
        if (x.id == oldPage) foundPage = x;
      }
      final page =
          foundPage ?? (section.pages.isEmpty ? null : section.pages.first);
      _pageId = page?.id;
      _reloadCount++; // rebuilds the page so it shows the new content
    });
    _applyTheme();
  }

  Future<void> _checkExternalChange() async {
    if (!_loaded) return;
    if (_saveTimer?.isActive ?? false) return; // unsaved edits here win
    final modified = await _storage.modified();
    final last = _lastModified;
    if (modified == null || last == null || !modified.isAfter(last)) return;
    final loaded = await _storage.load();
    if (!mounted || loaded == null || loaded.sections.isEmpty) return;
    _lastModified = modified;
    _adopt(loaded);
    _toast('Notes updated from another computer');
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  Future<void> _saveNow() async {
    if (!_loaded) return; // never overwrite the file before it was read
    await _storage.save(_nb);
    _lastModified = await _storage.modified();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- selection ----------

  void _selectSection(Section s) {
    setState(() {
      _sectionId = s.id;
      _pageId = s.pages.isEmpty ? null : s.pages.first.id;
    });
  }

  void _selectPage(NotePage p) {
    setState(() => _pageId = p.id);
    _scaffoldKey.currentState?.closeDrawer();
  }

  // ---------- add / rename / delete ----------

  void _addSection() {
    final s = Section(id: _nb.newId(), name: 'New section');
    s.pages.add(NotePage(id: _nb.newId(), title: 'Untitled page'));
    setState(() {
      _nb.sections.add(s);
      _sectionId = s.id;
      _pageId = s.pages.first.id;
    });
    _scheduleSave();
  }

  void _addPage() {
    final s = _section;
    if (s == null) return;
    final p = NotePage(id: _nb.newId(), title: 'Untitled page');
    setState(() {
      s.pages.add(p);
      _pageId = p.id;
    });
    _scheduleSave();
  }

  Future<void> _renameSection(Section s) async {
    final name = await _askText('Rename section', s.name);
    if (name == null) return;
    setState(() => s.name = name);
    _scheduleSave();
  }

  Future<void> _renamePage(NotePage p) async {
    final title = await _askText('Rename page', p.title);
    if (title == null) return;
    setState(() => p.title = title);
    _scheduleSave();
  }

  Future<void> _deleteSection(Section s) async {
    if (_nb.sections.length <= 1) return;
    final ok = await _confirm('Delete section "${s.name}" and all its pages?');
    if (!ok) return;
    setState(() {
      _nb.sections.remove(s);
      if (_sectionId == s.id) {
        final first = _nb.sections.first;
        _sectionId = first.id;
        _pageId = first.pages.isEmpty ? null : first.pages.first.id;
      }
    });
    _scheduleSave();
  }

  Future<void> _deletePage(NotePage p) async {
    final s = _section;
    if (s == null) return;
    final ok = await _confirm('Delete page "${p.title}"?');
    if (!ok) return;
    setState(() {
      s.pages.remove(p);
      if (_pageId == p.id) {
        _pageId = s.pages.isEmpty ? null : s.pages.first.id;
      }
    });
    _scheduleSave();
  }

  // ---------- search ----------

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _query = '');
  }

  List<_Hit> _search(String q) {
    final needle = q.trim().toLowerCase();
    final hits = <_Hit>[];
    if (needle.isEmpty) return hits;
    for (final s in _nb.sections) {
      for (final p in s.pages) {
        var match = p.title.toLowerCase().contains(needle);
        var snippet = '';
        for (final b in p.boxes) {
          final t = b.text;
          final i = t.toLowerCase().indexOf(needle);
          if (i >= 0) {
            match = true;
            final start = (i - 20).clamp(0, t.length).toInt();
            final end = (i + needle.length + 40).clamp(0, t.length).toInt();
            snippet = t.substring(start, end).replaceAll('\n', ' ');
            break;
          }
        }
        if (match) hits.add(_Hit(s, p, snippet));
      }
    }
    return hits;
  }

  void _openHit(_Hit h) {
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _sectionId = h.section.id;
      _pageId = h.page.id;
    });
    _scaffoldKey.currentState?.closeDrawer();
  }

  // ---------- export / backup ----------

  String _pageToMarkdown(NotePage p) {
    final boxes = [...p.boxes]..sort((a, b) {
        final c = a.y.compareTo(b.y);
        return c != 0 ? c : a.x.compareTo(b.x);
      });
    final buf = StringBuffer('# ${p.title}\n\n');
    for (final b in boxes) {
      final t = b.text.trim();
      if (t.isNotEmpty) buf.write('$t\n\n');
    }
    return buf.toString();
  }

  Future<void> _copyMarkdown() async {
    final p = _page;
    if (p == null) return;
    await Clipboard.setData(ClipboardData(text: _pageToMarkdown(p)));
    _toast('Page copied as Markdown');
  }

  Future<void> _copyBackup() async {
    final data = _nb.toJson();
    final images = <String, String>{};
    for (final s in _nb.sections) {
      for (final p in s.pages) {
        for (final img in p.images) {
          if (images.containsKey(img.file)) continue;
          final bytes = await imageStore.get(img.file);
          if (bytes != null) images[img.file] = base64Encode(bytes);
        }
      }
    }
    if (images.isNotEmpty) data['images'] = images;
    await Clipboard.setData(ClipboardData(text: jsonEncode(data)));
    _toast('Notebook backup copied. Paste it into a text file to keep it.');
  }

  Future<void> _restoreBackup() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from backup'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Paste a notebook backup below. This replaces everything in the current notebook.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Paste backup here',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      final nb = Notebook.fromJson(map);
      if (nb.sections.isEmpty) throw const FormatException('empty');
      final imgs = map['images'];
      if (imgs is Map) {
        for (final e in imgs.entries) {
          try {
            await imageStore.putRaw(
              e.key as String,
              base64Decode(e.value as String),
            );
          } catch (_) {}
        }
      }
      if (!mounted) return;
      setState(() {
        _nb = nb;
        final first = nb.sections.first;
        _sectionId = first.id;
        _pageId = first.pages.isEmpty ? null : first.pages.first.id;
      });
      _scheduleSave();
      _applyTheme();
      _toast('Backup restored');
    } catch (_) {
      _toast('That does not look like a valid backup');
    }
  }

  // ---------- sync folder ----------

  Future<void> _syncFolderDialog() async {
    final desktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (!desktop) {
      _toast('Sync folders work in the Windows, macOS and Linux apps');
      return;
    }
    final current = await AppPaths.customFolder();
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync folder'),
        content: SizedBox(
          width: 460,
          child: Text(
            'Pagelark keeps your notes in one folder. Pick a folder inside '
            'OneDrive, Dropbox, Google Drive, iCloud Drive or Syncthing, and '
            'that service will keep your notes in sync between your computers '
            'using the account you already have.\n\n'
            'Do not edit on two computers at the same moment.\n\n'
            'Current folder: ${current ?? 'default (Documents/Pagelark)'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (current != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'default'),
              child: const Text('Use default folder'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'choose'),
            child: const Text('Choose folder...'),
          ),
        ],
      ),
    );
    if (choice == 'choose') {
      final dir = await getDirectoryPath();
      if (dir != null) await _switchFolder(dir);
    } else if (choice == 'default') {
      await _switchFolder(null);
    }
  }

  Future<void> _switchFolder(String? path) async {
    try {
      _saveTimer?.cancel();
      await _saveNow(); // finish saving into the old folder first
      final from = await AppPaths.resolve(await AppPaths.customFolder());
      final to = await AppPaths.resolve(path);
      if (from.path == to.path) return;
      if (await AppPaths.hasNotebook(to)) {
        if (!mounted) return;
        final use = await _confirm(
          'That folder already contains Pagelark notes. Switch to those notes? '
          'Your current notes stay in the old folder.',
          action: 'Switch',
        );
        if (!use) return;
      } else {
        await AppPaths.copyData(from, to);
      }
      await AppPaths.setCustomFolder(path);
      imageStore.clearCache();
      final loaded = await _storage.load();
      if (!mounted) return;
      if (loaded != null && loaded.sections.isNotEmpty) {
        _lastModified = await _storage.modified();
        _adopt(loaded);
      }
      _toast('Notes folder changed');
    } catch (_) {
      _toast('Could not use that folder');
    }
  }

  // ---------- small dialogs ----------

  Future<String?> _askText(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) =>
              Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              Navigator.pop(ctx, v.isEmpty ? null : v);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String message, {String action = 'Delete'}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ---------- sidebar ----------

  Widget _sidebarHeader(String label, VoidCallback onAdd) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Add',
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required String title,
    required bool selected,
    required VoidCallback onTap,
    required VoidCallback onRename,
    required VoidCallback onDelete,
    bool canDelete = true,
  }) {
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        iconSize: 18,
        padding: EdgeInsets.zero,
        onSelected: (v) {
          if (v == 'rename') onRename();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(
            value: 'delete',
            enabled: canDelete,
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _browseColumn() {
    final section = _section;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sidebarHeader('SECTIONS', _addSection),
        Expanded(
          flex: 2,
          child: ListView(
            children: [
              for (final s in _nb.sections)
                _tile(
                  title: s.name,
                  selected: s.id == _sectionId,
                  onTap: () => _selectSection(s),
                  onRename: () => _renameSection(s),
                  onDelete: () => _deleteSection(s),
                  canDelete: _nb.sections.length > 1,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        _sidebarHeader('PAGES', _addPage),
        Expanded(
          flex: 3,
          child: section == null
              ? const SizedBox()
              : ListView(
                  children: [
                    for (final p in section.pages)
                      _tile(
                        title: p.title,
                        selected: p.id == _pageId,
                        onTap: () => _selectPage(p),
                        onRename: () => _renamePage(p),
                        onDelete: () => _deletePage(p),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _resultsList() {
    final hits = _search(_query);
    if (hits.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No pages found'),
      );
    }
    return ListView(
      children: [
        for (final h in hits)
          ListTile(
            dense: true,
            title: Text(h.page.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              h.snippet.isEmpty ? h.section.name : '${h.section.name} · ${h.snippet}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _openHit(h),
          ),
      ],
    );
  }

  Widget _buildSidebar({bool fill = false}) {
    return Container(
      width: fill ? null : 270,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Pagelark',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search all pages',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: _clearSearch,
                      ),
              ),
            ),
          ),
          Expanded(
            child: _query.trim().isEmpty ? _browseColumn() : _resultsList(),
          ),
        ],
      ),
    );
  }

  // ---------- main layout ----------

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final section = _section;
    final page = _page;
    final title = section == null
        ? 'Pagelark'
        : (page == null ? section.name : '${section.name}  ›  ${page.title}');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Widget pageArea = page == null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('This section has no pages yet'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _addPage,
                  icon: const Icon(Icons.add),
                  label: const Text('Add page'),
                ),
              ],
            ),
          )
        : PageCanvas(
            key: ValueKey('${page.id}-$_reloadCount'),
            page: page,
            onChanged: _scheduleSave,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 760;
        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Light / dark',
                icon: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                ),
                onPressed: () {
                  final next = isDark ? ThemeMode.light : ThemeMode.dark;
                  setState(() {
                    _nb.theme = next == ThemeMode.dark ? 'dark' : 'light';
                  });
                  widget.onSetTheme(next);
                  _scheduleSave();
                },
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) {
                  if (v == 'md') _copyMarkdown();
                  if (v == 'backup') _copyBackup();
                  if (v == 'restore') _restoreBackup();
                  if (v == 'sync') _syncFolderDialog();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'md', child: Text('Copy page as Markdown')),
                  PopupMenuItem(value: 'backup', child: Text('Copy notebook backup')),
                  PopupMenuItem(value: 'restore', child: Text('Restore from backup...')),
                  PopupMenuItem(value: 'sync', child: Text('Sync folder...')),
                ],
              ),
            ],
          ),
          drawer: narrow
              ? Drawer(child: SafeArea(child: _buildSidebar(fill: true)))
              : null,
          body: narrow
              ? pageArea
              : Row(
                  children: [
                    _buildSidebar(),
                    const VerticalDivider(width: 1),
                    Expanded(child: pageArea),
                  ],
                ),
        );
      },
    );
  }
}

enum PageTool { select, pen, eraser }

/// The freeform page: double-click to add a text box, drag to move, etc.
/// Images can be added or pasted, and a pen draws ink on top.
/// The page area is bigger than the window and scrolls in both directions.
class PageCanvas extends StatefulWidget {
  const PageCanvas({super.key, required this.page, required this.onChanged});

  final NotePage page;
  final VoidCallback onChanged;

  @override
  State<PageCanvas> createState() => _PageCanvasState();
}

class _PageCanvasState extends State<PageCanvas> {
  final ScrollController _vCtrl = ScrollController();
  final ScrollController _hCtrl = ScrollController();
  Offset? _doubleTapPos;
  PageTool _tool = PageTool.select;
  int _penColor = 0;
  Stroke? _current;

  List<NoteBox> get _boxes => widget.page.boxes;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    // Drop empty boxes when leaving the page.
    widget.page.boxes.removeWhere((b) => b.text.trim().isEmpty);
    _vCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // Ctrl/Cmd+V pastes an image when you are not typing in a text box.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final hw = HardwareKeyboard.instance;
    if (!(hw.isControlPressed || hw.isMetaPressed)) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyV) return false;
    final focus = FocusManager.instance.primaryFocus;
    final typing =
        focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (typing) return false;
    _pasteImage(quiet: true);
    return false;
  }

  // ---------- text boxes ----------

  void _addBox(Offset p) {
    setState(() {
      _boxes.add(
        NoteBox(id: widget.page.nextBoxId++, x: p.dx, y: p.dy, autofocus: true),
      );
    });
    widget.onChanged();
  }

  void _clearFocusAndEmptyBoxes() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _boxes.removeWhere((b) => b.text.trim().isEmpty);
    });
    widget.onChanged();
  }

  void _moveBox(NoteBox box, Offset delta) {
    setState(() {
      box.x = (box.x + delta.dx).clamp(0.0, kCanvasW - box.width).toDouble();
      box.y = (box.y + delta.dy).clamp(0.0, kCanvasH - 60).toDouble();
    });
    widget.onChanged();
  }

  void _resizeBox(NoteBox box, double dx) {
    setState(() {
      box.width = (box.width + dx).clamp(120.0, 900.0).toDouble();
    });
    widget.onChanged();
  }

  void _deleteBox(NoteBox box) {
    setState(() => _boxes.remove(box));
    widget.onChanged();
  }

  // ---------- images ----------

  Offset _viewportTopLeft() {
    final x = _hCtrl.hasClients ? _hCtrl.offset : 0.0;
    final y = _vCtrl.hasClients ? _vCtrl.offset : 0.0;
    return Offset(x, y);
  }

  Future<void> _addImageBytes(Uint8List bytes) async {
    try {
      final decoded = await decodeImageFromList(bytes); // also checks it is an image
      final natural = decoded.width.toDouble();
      decoded.dispose();
      final name = await imageStore.add(bytes);
      if (!mounted) return;
      final origin = _viewportTopLeft();
      final step = (widget.page.images.length % 8) * 24.0;
      setState(() {
        widget.page.images.add(ImageItem(
          id: widget.page.nextBoxId++,
          x: origin.dx + 60 + step,
          y: origin.dy + 80 + step,
          width: natural.clamp(80.0, 360.0).toDouble(),
          file: name,
        ));
      });
      widget.onChanged();
    } catch (_) {
      _toast("That file isn't an image Pagelark can open");
    }
  }

  Future<void> _pickImage() async {
    try {
      const group = XTypeGroup(
        label: 'Images',
        extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
      );
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
      if (file == null) return;
      await _addImageBytes(await file.readAsBytes());
    } catch (_) {
      _toast('Could not open that file');
    }
  }

  Future<void> _pasteImage({bool quiet = false}) async {
    try {
      final bytes = await Pasteboard.image;
      if (bytes == null || bytes.isEmpty) {
        if (!quiet) _toast('There is no image on the clipboard');
        return;
      }
      await _addImageBytes(bytes);
    } catch (_) {
      if (!quiet) {
        _toast('Pasting images does not work here. Use Add image instead.');
      }
    }
  }

  void _moveImage(ImageItem it, Offset delta) {
    setState(() {
      it.x = (it.x + delta.dx).clamp(0.0, kCanvasW - it.width).toDouble();
      it.y = (it.y + delta.dy).clamp(0.0, kCanvasH - 60).toDouble();
    });
    widget.onChanged();
  }

  void _resizeImage(ImageItem it, double dx) {
    setState(() {
      it.width = (it.width + dx).clamp(80.0, 2000.0).toDouble();
    });
    widget.onChanged();
  }

  void _deleteImage(ImageItem it) {
    setState(() => widget.page.images.remove(it));
    imageStore.delete(it.file);
    widget.onChanged();
  }

  // ---------- pen and eraser ----------

  void _undoStroke() {
    if (widget.page.strokes.isEmpty) return;
    setState(() => widget.page.strokes.removeLast());
    widget.onChanged();
  }

  void _eraseAt(Offset pos) {
    final before = widget.page.strokes.length;
    widget.page.strokes.removeWhere((s) {
      final p = s.points;
      for (var i = 0; i + 1 < p.length; i += 2) {
        final dx = p[i] - pos.dx;
        final dy = p[i + 1] - pos.dy;
        if (dx * dx + dy * dy < 14 * 14) return true;
      }
      return false;
    });
    if (widget.page.strokes.length != before) {
      setState(() {});
      widget.onChanged();
    }
  }

  Widget _penLayer() {
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          if (_tool == PageTool.pen) {
            setState(() {
              _current = Stroke(
                color: _penColor,
                width: 3,
                points: [d.localPosition.dx, d.localPosition.dy],
              );
            });
          } else {
            _eraseAt(d.localPosition);
          }
        },
        onPanUpdate: (d) {
          if (_tool == PageTool.pen) {
            final c = _current;
            if (c == null) return;
            setState(() {
              c.points.add(d.localPosition.dx);
              c.points.add(d.localPosition.dy);
            });
          } else {
            _eraseAt(d.localPosition);
          }
        },
        onPanEnd: (_) {
          final c = _current;
          if (c == null) return;
          c.points = [for (final v in c.points) (v * 10).round() / 10];
          setState(() {
            widget.page.strokes.add(c);
            _current = null;
          });
          widget.onChanged();
        },
        onPanCancel: () => setState(() => _current = null),
        onTapUp: (d) {
          if (_tool == PageTool.pen) {
            setState(() {
              widget.page.strokes.add(Stroke(
                color: _penColor,
                width: 3,
                points: [d.localPosition.dx, d.localPosition.dy],
              ));
            });
            widget.onChanged();
          } else {
            _eraseAt(d.localPosition);
          }
        },
      ),
    );
  }

  Widget _inkDot(int c) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shown = c == 0 ? (dark ? Colors.white : Colors.black) : Color(c);
    final selected = _penColor == c;
    return InkWell(
      onTap: () => setState(() => _penColor = c),
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: shown,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? cs.primary : Colors.grey,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Add image',
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _pickImage,
            ),
            IconButton(
              tooltip: 'Paste image (Ctrl+V)',
              icon: const Icon(Icons.content_paste),
              onPressed: () => _pasteImage(),
            ),
            const SizedBox(height: 24, child: VerticalDivider(width: 12)),
            IconButton(
              tooltip: 'Pen',
              isSelected: _tool == PageTool.pen,
              icon: const Icon(Icons.edit_outlined),
              selectedIcon: const Icon(Icons.edit),
              onPressed: () => setState(() {
                _tool = _tool == PageTool.pen ? PageTool.select : PageTool.pen;
              }),
            ),
            IconButton(
              tooltip: 'Eraser',
              isSelected: _tool == PageTool.eraser,
              icon: const Icon(Icons.cleaning_services_outlined),
              selectedIcon: const Icon(Icons.cleaning_services),
              onPressed: () => setState(() {
                _tool =
                    _tool == PageTool.eraser ? PageTool.select : PageTool.eraser;
              }),
            ),
            if (_tool == PageTool.pen)
              for (final c in kInkColors) _inkDot(c),
            if (_tool != PageTool.select)
              IconButton(
                tooltip: 'Undo last stroke',
                icon: const Icon(Icons.undo),
                onPressed: _undoStroke,
              ),
          ],
        ),
      ),
    );
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final narrow = MediaQuery.of(context).size.width < 760;
    final page = widget.page;
    final empty = _boxes.isEmpty && page.images.isEmpty && page.strokes.isEmpty;

    return Stack(
      children: [
        Scrollbar(
          controller: _vCtrl,
          thumbVisibility: true,
          child: Scrollbar(
            controller: _hCtrl,
            thumbVisibility: true,
            notificationPredicate: (n) => n.depth == 1,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            child: SingleChildScrollView(
              controller: _vCtrl,
              child: SingleChildScrollView(
                controller: _hCtrl,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: kCanvasW,
                  height: kCanvasH,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _clearFocusAndEmptyBoxes,
                    onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
                    onDoubleTap: () {
                      if (_doubleTapPos != null) _addBox(_doubleTapPos!);
                    },
                    child: Container(
                      color: bg,
                      child: Stack(
                        children: [
                          if (empty)
                            Positioned(
                              left: 24,
                              top: 24,
                              child: Text(
                                'Double-click anywhere to add a text box',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          for (final img in page.images)
                            Positioned(
                              key: ValueKey('img${img.id}'),
                              left: img.x,
                              top: img.y,
                              width: img.width,
                              child: ImageItemView(
                                item: img,
                                onMove: (delta) => _moveImage(img, delta),
                                onResize: (dx) => _resizeImage(img, dx),
                                onDelete: () => _deleteImage(img),
                              ),
                            ),
                          for (final box in _boxes)
                            Positioned(
                              key: ValueKey(box.id),
                              left: box.x,
                              top: box.y,
                              width: box.width,
                              child: NoteBoxView(
                                box: box,
                                onMove: (delta) => _moveBox(box, delta),
                                onResize: (dx) => _resizeBox(box, dx),
                                onDelete: () => _deleteBox(box),
                                onEdited: widget.onChanged,
                              ),
                            ),
                          // ink on top of everything
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: InkPainter(
                                  page.strokes,
                                  _current,
                                  dark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                          // while the pen or eraser is on, this layer catches the mouse
                          if (_tool != PageTool.select)
                            Positioned.fill(child: _penLayer()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: narrow ? 8 : null,
          right: narrow ? 12 : 24,
          top: 12,
          child: narrow
              ? Align(
                  heightFactor: 1,
                  alignment: Alignment.topRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: _buildToolbar(),
                  ),
                )
              : _buildToolbar(),
        ),
      ],
    );
  }
}

class NoteBoxView extends StatefulWidget {
  const NoteBoxView({
    super.key,
    required this.box,
    required this.onMove,
    required this.onResize,
    required this.onDelete,
    required this.onEdited,
  });

  final NoteBox box;
  final void Function(Offset delta) onMove;
  final void Function(double dx) onResize;
  final VoidCallback onDelete;
  final VoidCallback onEdited;

  @override
  State<NoteBoxView> createState() => _NoteBoxViewState();
}

class _NoteBoxViewState extends State<NoteBoxView> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.box.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _nextColor() {
    setState(() {
      widget.box.color = (widget.box.color + 1) % kBoxBody.length;
    });
    widget.onEdited();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.box.color.clamp(0, kBoxBody.length - 1).toInt();
    return Container(
      decoration: BoxDecoration(
        color: kBoxBody[i],
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle (move the box) + colour + delete
          GestureDetector(
            onTap: () {}, // stops the tap from reaching the page behind
            onPanUpdate: (d) => widget.onMove(d.delta),
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                color: kBoxHeader[i],
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(6)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  const Icon(Icons.drag_indicator, size: 16, color: Colors.black54),
                  const Spacer(),
                  InkWell(
                    onTap: _nextColor,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.palette_outlined, size: 16, color: Colors.black54),
                    ),
                  ),
                  InkWell(
                    onTap: widget.onDelete,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.close, size: 16, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Text area
          TextField(
            controller: _controller,
            autofocus: widget.box.autofocus,
            maxLines: null,
            cursorColor: Colors.black87,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.all(8),
            ),
            onChanged: (value) {
              widget.box.text = value;
              widget.onEdited();
            },
          ),
          // Resize handle (change the width)
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {},
              onPanUpdate: (d) => widget.onResize(d.delta.dx),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.south_east, size: 14, color: Colors.black45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An image on the page, with a drag bar on top and a resize handle below.
class ImageItemView extends StatefulWidget {
  const ImageItemView({
    super.key,
    required this.item,
    required this.onMove,
    required this.onResize,
    required this.onDelete,
  });

  final ImageItem item;
  final void Function(Offset delta) onMove;
  final void Function(double dx) onResize;
  final VoidCallback onDelete;

  @override
  State<ImageItemView> createState() => _ImageItemViewState();
}

class _ImageItemViewState extends State<ImageItemView> {
  Uint8List? _bytes;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _bytes = imageStore.peek(widget.item.file);
    if (_bytes == null) {
      imageStore.get(widget.item.file).then((b) {
        if (!mounted) return;
        setState(() {
          _bytes = b;
          _missing = b == null;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {},
              onPanUpdate: (d) => widget.onMove(d.delta),
              child: Container(
                height: 24,
                color: const Color(0xFFE8E8EE),
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    const Icon(Icons.drag_indicator, size: 16, color: Colors.black54),
                    const Spacer(),
                    InkWell(
                      onTap: widget.onDelete,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.close, size: 16, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (bytes != null)
              SizedBox(
                width: double.infinity,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.fitWidth,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              )
            else
              SizedBox(
                height: 80,
                child: Center(
                  child: _missing
                      ? const Text(
                          'Image file not found',
                          style: TextStyle(color: Colors.black54),
                        )
                      : const CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Container(
              color: Colors.white,
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () {},
                onPanUpdate: (d) => widget.onResize(d.delta.dx),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.south_east, size: 14, color: Colors.black45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the pen strokes.
class InkPainter extends CustomPainter {
  InkPainter(this.strokes, this.current, this.autoColor);

  final List<Stroke> strokes;
  final Stroke? current;
  final Color autoColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _draw(canvas, s);
    }
    final c = current;
    if (c != null) _draw(canvas, c);
  }

  void _draw(Canvas canvas, Stroke s) {
    final p = s.points;
    if (p.length < 2) return;
    final paint = Paint()
      ..color = s.color == 0 ? autoColor : Color(s.color)
      ..strokeWidth = s.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    if (p.length == 2) {
      canvas.drawCircle(
        Offset(p[0], p[1]),
        s.width / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(p[0], p[1]);
    for (var i = 2; i + 3 < p.length; i += 2) {
      final mx = (p[i] + p[i + 2]) / 2;
      final my = (p[i + 1] + p[i + 3]) / 2;
      path.quadraticBezierTo(p[i], p[i + 1], mx, my);
    }
    path.lineTo(p[p.length - 2], p[p.length - 1]);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant InkPainter oldDelegate) => true;
}
