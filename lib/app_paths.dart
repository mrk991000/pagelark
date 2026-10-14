import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Decides which folder holds notebook.json and the images folder.
/// By default that is <Documents>/Pagelark. On desktop the user can pick any
/// folder instead (for example one inside OneDrive, Dropbox or Google Drive),
/// which makes the cloud service sync the notes between computers.
/// The choice itself is remembered in a small settings.json file that always
/// stays in the app's own folder.
class AppPaths {
  static String? _custom;
  static bool _loaded = false;

  static Future<File> _settingsFile() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}pagelark_settings.json');
  }

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    if (kIsWeb) return;
    try {
      final f = await _settingsFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final p = j['dataFolder'] as String?;
        if (p != null && p.isNotEmpty) _custom = p;
      }
    } catch (_) {}
  }

  /// The folder the user picked, or null when using the default.
  static Future<String?> customFolder() async {
    await _ensureLoaded();
    return _custom;
  }

  static Future<void> setCustomFolder(String? path) async {
    _loaded = true;
    _custom = (path == null || path.isEmpty) ? null : path;
    final f = await _settingsFile();
    await f.writeAsString(jsonEncode({'dataFolder': _custom ?? ''}), flush: true);
  }

  /// Turns a chosen path (or null for the default) into a folder.
  static Future<Directory> resolve(String? custom) async {
    if (custom != null && custom.isNotEmpty) return Directory(custom);
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}Pagelark');
  }

  /// The folder currently in use (created if needed). Null on the web.
  static Future<Directory?> dataDir() async {
    if (kIsWeb) return null;
    await _ensureLoaded();
    final d = await resolve(_custom);
    await d.create(recursive: true);
    return d;
  }

  static Future<bool> hasNotebook(Directory d) {
    return File('${d.path}${Platform.pathSeparator}notebook.json').exists();
  }

  /// Copies the notebook file and its images from one folder to another.
  static Future<void> copyData(Directory from, Directory to) async {
    final sep = Platform.pathSeparator;
    await to.create(recursive: true);
    final nb = File('${from.path}${sep}notebook.json');
    if (await nb.exists()) await nb.copy('${to.path}${sep}notebook.json');
    final imgs = Directory('${from.path}${sep}images');
    if (await imgs.exists()) {
      final target = Directory('${to.path}${sep}images');
      await target.create(recursive: true);
      await for (final e in imgs.list()) {
        if (e is File) {
          await e.copy('${target.path}$sep${e.uri.pathSegments.last}');
        }
      }
    }
  }
}
