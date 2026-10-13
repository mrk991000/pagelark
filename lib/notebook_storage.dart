import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Stores the whole notebook as one plain JSON file:
///   <Documents>/Pagelark/notebook.json
/// On the web there is no file access, so nothing is saved there
/// (fine for quick testing in Chrome).
class NotebookStorage {
  Future<File?> _file() async {
    if (kIsWeb) return null;
    final sep = Platform.pathSeparator;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${sep}Pagelark');
    await dir.create(recursive: true);
    return File('${dir.path}${sep}notebook.json');
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
      await file.writeAsString(jsonEncode(notebook.toJson()), flush: true);
    } catch (_) {
      // Ignore for now; we'll show a proper error message later.
    }
  }
}
