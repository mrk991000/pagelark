import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';
import 'models.dart';

/// Stores the whole notebook as one plain JSON file: <data folder>/notebook.json
/// A copy is also kept once a day in <data folder>/backups (newest 14 kept),
/// so a mistake or a sync accident never costs you more than a day.
/// On the web there is no file access, so nothing is saved there
/// (fine for quick testing in Chrome).
class NotebookStorage {
  Future<File?> _file() async {
    final dir = await AppPaths.dataDir();
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}notebook.json');
  }

  /// When notebook.json was last changed (by us or by a sync service).
  Future<DateTime?> modified() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return null;
      return await f.lastModified();
    } catch (_) {
      return null;
    }
  }

  Future<Notebook?> load() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return Notebook.fromJson(json);
    } catch (_) {
      return null; // missing or damaged file: start with a fresh notebook
    }
  }

  Future<void> save(Notebook notebook) async {
    try {
      final file = await _file();
      if (file == null) return;
      await _dailyBackup(file);
      await file.writeAsString(jsonEncode(notebook.toJson()), flush: true);
    } catch (_) {
      // Ignore for now; we'll show a proper error message later.
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _dailyBackup(File file) async {
    try {
      if (!await file.exists()) return;
      final now = DateTime.now();
      final stamp = '${now.year}-${_two(now.month)}-${_two(now.day)}';
      final sep = Platform.pathSeparator;
      final dir = Directory('${file.parent.path}${sep}backups');
      final target = File('${dir.path}${sep}notebook-$stamp.json');
      if (await target.exists()) return;
      await dir.create(recursive: true);
      await file.copy(target.path);
      final files = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      while (files.length > 14) {
        await files.removeAt(0).delete();
      }
    } catch (_) {}
  }
}
