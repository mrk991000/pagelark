import 'note_box.dart';

/// One page: a title plus the text boxes placed on it.
class NotePage {
  NotePage({
    required this.id,
    required this.title,
    List<NoteBox>? boxes,
    this.nextBoxId = 1,
  }) : boxes = boxes ?? <NoteBox>[];

  final int id;
  String title;
  final List<NoteBox> boxes;
  int nextBoxId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'nextBoxId': nextBoxId,
        'boxes': boxes.map((b) => b.toJson()).toList(),
      };

  factory NotePage.fromJson(Map<String, dynamic> j) => NotePage(
        id: j['id'] as int,
        title: j['title'] as String,
        nextBoxId: j['nextBoxId'] as int,
        boxes: (j['boxes'] as List)
            .map((e) => NoteBox.fromJson(e as Map<String, dynamic>))
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
  }) : sections = sections ?? <Section>[];

  String name;
  final List<Section> sections;
  int nextId; // one counter used for both section ids and page ids

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
        'version': 2,
        'name': name,
        'nextId': nextId,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  factory Notebook.fromJson(Map<String, dynamic> j) => Notebook(
        name: j['name'] as String,
        nextId: j['nextId'] as int,
        sections: (j['sections'] as List)
            .map((e) => Section.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
