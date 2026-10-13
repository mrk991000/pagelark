/// One text box on the page.
class NoteBox {
  NoteBox({
    required this.id,
    required this.x,
    required this.y,
    this.width = 220,
    this.text = '',
    this.color = 0,
    this.autofocus = false,
  });

  final int id;
  double x;
  double y;
  double width;
  String text;
  int color; // index into the colour palette in main.dart
  bool autofocus; // not saved; only used when a box is first created

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'width': width,
        'text': text,
        'color': color,
      };

  factory NoteBox.fromJson(Map<String, dynamic> j) => NoteBox(
        id: j['id'] as int,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        text: j['text'] as String,
        color: (j['color'] as int?) ?? 0, // older saves have no colour
      );
}
