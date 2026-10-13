import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

void main() => runApp(const NotebookApp());

class NotebookApp extends StatefulWidget {
  const NotebookApp({super.key});

  @override
  State<NotebookApp> createState() => _NotebookAppState();
}

class _NotebookAppState extends State<NotebookApp> {
  ThemeMode _mode = ThemeMode.system;

  void _toggleTheme(Brightness current) {
    setState(() {
      _mode = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    });
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
      home: HomeScreen(onToggleTheme: _toggleTheme),
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
  const HomeScreen({super.key, required this.onToggleTheme});

  final void Function(Brightness current) onToggleTheme;

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
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
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
  }

  Future<void> _load() async {
    final loaded = await _storage.load();
    if (!mounted) return;
    setState(() {
      if (loaded != null && loaded.sections.isNotEmpty) _nb = loaded;
      final first = _nb.sections.first;
      _sectionId = first.id;
      _pageId = first.pages.isEmpty ? null : first.pages.first.id;
      _loaded = true;
    });
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  Future<void> _saveNow() async {
    if (!_loaded) return; // never overwrite the file before it was read
    await _storage.save(_nb);
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

  void _selectPage(NotePage p) => setState(() => _pageId = p.id);

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
  }

  // ---------- export / backup ----------

  String _pageToMarkdown(NotePage p) {
    final boxes = [...p.boxes]
      ..sort((a, b) {
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
    await Clipboard.setData(ClipboardData(text: jsonEncode(_nb.toJson())));
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
      final nb = Notebook.fromJson(jsonDecode(text) as Map<String, dynamic>);
      if (nb.sections.isEmpty) throw const FormatException('empty');
      setState(() {
        _nb = nb;
        final first = nb.sections.first;
        _sectionId = first.id;
        _pageId = first.pages.isEmpty ? null : first.pages.first.id;
      });
      _scheduleSave();
      _toast('Backup restored');
    } catch (_) {
      _toast('That does not look like a valid backup');
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

  Future<bool> _confirm(String message) async {
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
            child: const Text('Delete'),
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
            title: Text(
              h.page.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              h.snippet.isEmpty
                  ? h.section.name
                  : '${h.section.name} · ${h.snippet}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _openHit(h),
          ),
      ],
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 270,
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Light / dark',
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
            onPressed: () => widget.onToggleTheme(Theme.of(context).brightness),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'md') _copyMarkdown();
              if (v == 'backup') _copyBackup();
              if (v == 'restore') _restoreBackup();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'md', child: Text('Copy page as Markdown')),
              PopupMenuItem(
                value: 'backup',
                child: Text('Copy notebook backup'),
              ),
              PopupMenuItem(
                value: 'restore',
                child: Text('Restore from backup...'),
              ),
            ],
          ),
        ],
      ),
      body: Row(
        children: [
          _buildSidebar(),
          const VerticalDivider(width: 1),
          Expanded(
            child: page == null
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
                    key: ValueKey(page.id),
                    page: page,
                    onChanged: _scheduleSave,
                  ),
          ),
        ],
      ),
    );
  }
}

/// The freeform page: double-click to add a text box, drag to move, etc.
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

  List<NoteBox> get _boxes => widget.page.boxes;

  @override
  void dispose() {
    // Drop empty boxes when leaving the page.
    widget.page.boxes.removeWhere((b) => b.text.trim().isEmpty);
    _vCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    return Scrollbar(
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
                      if (_boxes.isEmpty)
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
  late final TextEditingController _controller = TextEditingController(
    text: widget.box.text,
  );

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
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.drag_indicator,
                    size: 16,
                    color: Colors.black54,
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: _nextColor,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.palette_outlined,
                        size: 16,
                        color: Colors.black54,
                      ),
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
