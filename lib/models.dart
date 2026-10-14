import 'note_box.dart';

/// An image placed on a page. The picture itself lives in the images folder
/// (see image_store.dart); the page only remembers the file name.
class ImageItem {
  ImageItem({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.file,
  });

  final int id;
  double x;
  double y;
  double width;
  final String file;

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'width': width,
        'file': file,
      };

  factory ImageItem.fromJson(Map<String, dynamic> j) => ImageItem(
        id: j['id'] as int,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        file: j['file'] as String,
      );
}

/// One pen stroke. points = [x0, y0, x1, y1, ...]
/// color 0 means "automatic" (black in light mode, white in dark mode).
class Stroke {
  Stroke({required this.color, required this.width, required this.points});

  final int color;
  final double width;
  List<double> points;

  Map<String, dynamic> toJson() => {'c': color, 'w': width, 'p': points};

  factory Stroke.fromJson(Map<String, dynamic> j) => Stroke(
        color: j['c'] as int,
        width: (j['w'] as num).toDouble(),
        points: (j['p'] as List).map((e) => (e as num).toDouble()).toList(),
      );
}

/// One page: a title plus the text boxes, images and ink placed on it.
class NotePage {
  NotePage({
    required this.id,
    required this.title,
    List<NoteBox>? boxes,
    List<ImageItem>? images,
    List<Stroke>? strokes,
    this.nextBoxId = 1,
  })  : boxes = boxes ?? <NoteBox>[],
        images = images ?? <ImageItem>[],
        strokes = strokes ?? <Stroke>[];

  final int id;
  String title;
  final List<NoteBox> boxes;
  final List<ImageItem> images;
  final List<Stroke> strokes;
  int nextBoxId; // shared counter for text boxes and images

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'nextBoxId': nextBoxId,
        'boxes': boxes.map((b) => b.toJson()).toList(),
        'images': images.map((i) => i.toJson()).toList(),
        'strokes': strokes.map((s) => s.toJson()).toList(),
      };

  factory NotePage.fromJson(Map<String, dynamic> j) => NotePage(
        id: j['id'] as int,
        title: j['title'] as String,
        nextBoxId: j['nextBoxId'] as int,
        boxes: (j['boxes'] as List)
            .map((e) => NoteBox.fromJson(e as Map<String, dynamic>))
            .toList(),
        // older saves have no images or ink
        images: (j['images'] as List?)
            ?.map((e) => ImageItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        strokes: (j['strokes'] as List?)
            ?.map((e) => Stroke.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A section groups pages (like a tab in a paper notebook).
class Section {
  Section({
    required this.id,
    required this.name,
    List<NotePage>? pages,
  }) : pages = pages ?? <NotePage>[];

  final int id;
  String name;
  final List<NotePage> pages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pages': pages.map((p) => p.toJson()).toList(),
      };

  factory Section.fromJson(Map<String, dynamic> j) => Section(
        id: j['id'] as int,
        name: j['name'] as String,
        pages: (j['pages'] as List)
            .map((e) => NotePage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// The whole notebook: sections, which contain pages, which contain boxes.
class Notebook {
  Notebook({
    required this.name,
    List<Section>? sections,
    this.nextId = 1,
    this.theme = 'system',
  }) : sections = sections ?? <Section>[];

  String name;
  final List<Section> sections;
  int nextId; // one counter used for both section ids and page ids
  String theme; // 'system', 'light' or 'dark'

  int newId() => nextId++;

  /// A fresh notebook with one section and one page.
  factory Notebook.starter() {
    final nb = Notebook(name: 'My Notebook');
    final section = Section(id: nb.newId(), name: 'General');
    section.pages.add(NotePage(id: nb.newId(), title: 'Page 1'));
    nb.sections.add(section);
    return nb;
  }

  Map<String, dynamic> toJson() => {
        'version': 3,
        'name': name,
        'nextId': nextId,
        'theme': theme,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  factory Notebook.fromJson(Map<String, dynamic> j) => Notebook(
        name: j['name'] as String,
        nextId: j['nextId'] as int,
        theme: (j['theme'] as String?) ?? 'system',
        sections: (j['sections'] as List)
            .map((e) => Section.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
