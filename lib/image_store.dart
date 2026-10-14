import 'dart:io';
import 'dart:typed_data';

import 'app_paths.dart';

/// Keeps pasted and added pictures as files:
///   <data folder>/images/img_<number>.img
/// On the web (testing only) pictures stay in memory and are lost on refresh.
class ImageStore {
  final Map<String, Uint8List> _cache = {};
  int _counter = DateTime.now().millisecondsSinceEpoch;

  // Only names we created ourselves are allowed (blocks "../" tricks in backups).
  static final RegExp _valid = RegExp(r'^img_\d+\.img$');

  Future<Directory?> _dir() async {
    final base = await AppPaths.dataDir();
    if (base == null) return null; // web
    final d = Directory('${base.path}${Platform.pathSeparator}images');
    await d.create(recursive: true);
    return d;
  }

  /// Forget everything held in memory (used when the notes folder changes).
  void clearCache() => _cache.clear();

  Future<void> _write(String name, Uint8List bytes) async {
    try {
      final d = await _dir();
      if (d == null) return;
      await File('${d.path}${Platform.pathSeparator}$name')
          .writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  /// Saves a new picture and returns the file name that refers to it.
  Future<String> add(Uint8List bytes) async {
    final name = 'img_${_counter++}.img';
    _cache[name] = bytes;
    await _write(name, bytes);
    return name;
  }

  /// Used when restoring a backup.
  Future<void> putRaw(String name, Uint8List bytes) async {
    if (!_valid.hasMatch(name)) return;
    _cache[name] = bytes;
    await _write(name, bytes);
  }

  Uint8List? peek(String name) => _cache[name];

  Future<Uint8List?> get(String name) async {
    if (!_valid.hasMatch(name)) return null;
    final cached = _cache[name];
    if (cached != null) return cached;
    try {
      final d = await _dir();
      if (d == null) return null;
      final f = File('${d.path}${Platform.pathSeparator}$name');
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      _cache[name] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String name) async {
    if (!_valid.hasMatch(name)) return;
    _cache.remove(name);
    try {
      final d = await _dir();
      if (d == null) return;
      final f = File('${d.path}${Platform.pathSeparator}$name');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// One shared store for the whole app.
final ImageStore imageStore = ImageStore();
