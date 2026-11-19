// SmartSumbong — the portal map's own symbols, drawn on the phone.
//
// The admin portal's Spatial Distribution draws its pins, legend and map
// buttons from one icon family (admin/assets/js/sd-icons.js: Lucide, ISC,
// and Tabler Icons, MIT; 24 px, 2 px round outline). The app's map wears
// the same marks (19 Nov 2026, Ace: "replace it with the portal one"), so
// the path data below is copied from that file, and this small reader
// turns it into Flutter paths: M L H V C S Q T A Z, absolute and relative,
// which is all those icons use. Parsed once per glyph and kept.

import 'package:flutter/widgets.dart';

/// One outline icon: 24x24 SVG path data and circles, stroked 2 px round.
class MapGlyph {
  const MapGlyph(this.paths, [this.circles = const []]);

  final List<String> paths;

  /// (cx, cy, r)
  final List<(double, double, double)> circles;

  static final _cache = <MapGlyph, Path>{};

  /// The whole glyph as one path, in its 24x24 box.
  Path get path => _cache[this] ??= () {
        final p = Path();
        for (final d in paths) {
          p.addPath(svgPath(d), Offset.zero);
        }
        for (final (x, y, r) in circles) {
          p.addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
        }
        return p;
      }();

  /// Strokes the glyph centred on [centre], [size] across, in [colour].
  void paint(Canvas canvas, Offset centre, double size, Color colour, {double stroke = 2}) {
    final k = size / 24;
    canvas.save();
    canvas.translate(centre.dx - size / 2, centre.dy - size / 2);
    canvas.scale(k);
    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }
}

/// The portal's PIN_GLYPH: one symbol per built-in category, keyed by the
/// category's icon (a category made in Settings borrows one of these).
const categoryMapGlyphs = <String, MapGlyph>{
  'street_obstruction': MapGlyph([
    'M4 8a1 1 0 0 1 1 -1h14a1 1 0 0 1 1 1v7a1 1 0 0 1 -1 1h-14a1 1 0 0 1 -1 -1l0 -7',
    'M7 16v4', 'M7.5 16l9 -9', 'M13.5 16l6.5 -6.5', 'M4 13.5l6.5 -6.5', 'M17 16v4',
    'M5 20h4', 'M15 20h4', 'M17 7v-2', 'M7 7v-2',
  ]),
  'public_safety_infrastructure': MapGlyph([
    'M6 7h12a2 2 0 0 1 2 2v9a1 1 0 0 1 -1 1h-2a1 1 0 0 1 -1 -1v-2a4 4 0 0 0 -8 0v2a1 1 0 0 1 -1 1h-2a1 1 0 0 1 -1 -1v-9a2 2 0 0 1 2 -2',
  ]),
  'environmental_waste_hazard': MapGlyph([
    'M10 11v6', 'M14 11v6', 'M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6', 'M3 6h18',
    'M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2',
  ]),
  'animal_welfare': MapGlyph([
    'M9 10a5 5 0 0 1 5 5v3.5a3.5 3.5 0 0 1-6.84 1.045Q6.52 17.48 4.46 16.84A3.5 3.5 0 0 1 5.5 10Z',
  ], [(11, 4, 2), (18, 8, 2), (20, 16, 2)]),
  'traffic_violation': MapGlyph([
    'M16.05 10.966a5 2.5 0 0 1-8.1 0',
    'm16.923 14.049 4.48 2.04a1 1 0 0 1 .001 1.831l-8.574 3.9a2 2 0 0 1-1.66 0l-8.574-3.91a1 1 0 0 1 0-1.83l4.484-2.04',
    'M16.949 14.14a5 2.5 0 1 1-9.9 0L10.063 3.5a2 2 0 0 1 3.874 0z',
    'M9.194 6.57a5 2.5 0 0 0 5.61 0',
  ]),
  'barangay_service': MapGlyph([
    'M10 18v-7', 'M11.119 2.205a2 2 0 0 1 1.762 0l7.84 3.846A.5.5 0 0 1 20.5 7h-17a.5.5 0 0 1-.22-.949z',
    'M14 18v-7', 'M18 18v-7', 'M3 22h18', 'M6 18v-7',
  ]),
  'peace_order_nuisance': MapGlyph([
    'M11 6a13 13 0 0 0 8.4-2.8A1 1 0 0 1 21 4v12a1 1 0 0 1-1.6.8A13 13 0 0 0 11 14H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z',
    'M6 14a12 12 0 0 0 2.4 7.2 2 2 0 0 0 3.2-2.4A8 8 0 0 1 10 14',
    'M8 6v8',
  ]),
  'other': MapGlyph([
    'M4 12a1 1 0 1 0 2 0a1 1 0 1 0 -2 0', 'M11 12a1 1 0 1 0 2 0a1 1 0 1 0 -2 0', 'M18 12a1 1 0 1 0 2 0a1 1 0 1 0 -2 0',
  ]),
};

MapGlyph categoryMapGlyph(String? icon) => categoryMapGlyphs[icon] ?? categoryMapGlyphs['other']!;

/// The portal's map buttons (sd-icons.js and spatial.php's dock).
abstract final class MapIcons {
  static const focus = MapGlyph(['M12 3l0 2', 'M3 12l2 0', 'M12 19l0 2', 'M19 12l2 0'], [(12, 12, 7), (12, 12, .5)]);
  static const layers = MapGlyph([
    'M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z',
    'M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12',
    'M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17',
  ]);
  static const list = MapGlyph(['M3 5h.01', 'M3 12h.01', 'M3 19h.01', 'M8 5h13', 'M8 12h13', 'M8 19h13']);
  static const plus = MapGlyph(['M5 12h14', 'M12 5v14']);
  static const minus = MapGlyph(['M5 12h14']);
  static const close = MapGlyph(['M18 6 6 18', 'm6 6 12 12']);
  static const pin = MapGlyph(['M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0'], [(12, 10, 3)]);
  static const calendar = MapGlyph(['M8 2v3', 'M16 2v3', 'M3 5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z', 'M3 9h18']);
  static const handler = MapGlyph([
    'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z',
    'm9 12 2 2 4-4',
  ]);
  static const photo = MapGlyph(['M3 5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z', 'm21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21'], [(9, 9, 2)]);
  static const send = MapGlyph(['M10 14l11 -11', 'M21 3l-6.5 18a.55 .55 0 0 1 -1 0l-3.5 -7l-7 -3.5a.55 .55 0 0 1 0 -1l18 -6.5']);
  static const safepoints = MapGlyph([
    'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z',
    'M9 12h6', 'M12 9v6',
  ]);
  static const check = MapGlyph(['M5 12.5l5 5 9-10']);
  static const arrow = MapGlyph(['M5 12h14', 'M13 6l6 6-6 6']);
  static const dim = MapGlyph(['M12 3a9 9 0 0 0 0 18z'], [(12, 12, 9)]);
  static const places = MapGlyph(['M4 20h16M5 20V10.5M9.5 20V10.5M14.5 20V10.5M19 20V10.5M3 10.5 12 5l9 5.5z', 'M12 5V2.2l3 1-3 1']);
}

/// A [MapGlyph] as a widget, the size of an [Icon].
class MapGlyphIcon extends StatelessWidget {
  const MapGlyphIcon(this.glyph, {super.key, this.size = 18, required this.colour, this.stroke = 2});

  final MapGlyph glyph;
  final double size;
  final Color colour;
  final double stroke;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _GlyphPainter(glyph, colour, stroke)),
      );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.colour, this.stroke);

  final MapGlyph glyph;
  final Color colour;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) => glyph.paint(canvas, size.center(Offset.zero), size.shortestSide, colour, stroke: stroke);

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.colour != colour || old.stroke != stroke;
}

/// SVG path data to a [Path]. Enough of the grammar for the icons above.
Path svgPath(String d) {
  final path = Path();
  final t = _Tokens(d);
  var cmd = '';
  var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
  // the last control point, for S and T
  double? cx, cy;
  var lastCmd = '';
  while (t.more) {
    if (t.isCommand) {
      cmd = t.command();
    } else if (cmd.isEmpty) {
      break;
    }
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + t.number();
        y = oy + t.number();
        path.moveTo(x, y);
        sx = x;
        sy = y;
        // further pairs after a move are lines
        cmd = rel ? 'l' : 'L';
        cx = null;
      case 'L':
        x = ox + t.number();
        y = oy + t.number();
        path.lineTo(x, y);
        cx = null;
      case 'H':
        x = ox + t.number();
        path.lineTo(x, y);
        cx = null;
      case 'V':
        y = oy + t.number();
        path.lineTo(x, y);
        cx = null;
      case 'C':
        final x1 = ox + t.number(), y1 = oy + t.number();
        final x2 = ox + t.number(), y2 = oy + t.number();
        x = ox + t.number();
        y = oy + t.number();
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
      case 'S':
        final smooth = 'CS'.contains(lastCmd.toUpperCase()) && cx != null;
        final x1 = smooth ? 2 * x - cx : x, y1 = smooth ? 2 * y - cy! : y;
        final x2 = ox + t.number(), y2 = oy + t.number();
        x = ox + t.number();
        y = oy + t.number();
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
      case 'Q':
        final x1 = ox + t.number(), y1 = oy + t.number();
        x = ox + t.number();
        y = oy + t.number();
        path.quadraticBezierTo(x1, y1, x, y);
        cx = x1;
        cy = y1;
      case 'T':
        final smooth = 'QT'.contains(lastCmd.toUpperCase()) && cx != null;
        final x1 = smooth ? 2 * x - cx : x, y1 = smooth ? 2 * y - cy! : y;
        x = ox + t.number();
        y = oy + t.number();
        path.quadraticBezierTo(x1, y1, x, y);
        cx = x1;
        cy = y1;
      case 'A':
        final rx = t.number(), ry = t.number(), rot = t.number();
        final large = t.flag(), sweep = t.flag();
        x = ox + t.number();
        y = oy + t.number();
        path.arcToPoint(Offset(x, y),
            radius: Radius.elliptical(rx, ry), rotation: rot, largeArc: large, clockwise: sweep);
        cx = null;
      case 'Z':
        path.close();
        x = sx;
        y = sy;
        cx = null;
        cmd = '';
      default:
        return path;
    }
    lastCmd = cmd.isEmpty ? 'Z' : cmd;
  }
  return path;
}

class _Tokens {
  _Tokens(this.s);

  final String s;
  int i = 0;

  void _skip() {
    while (i < s.length && (s[i] == ' ' || s[i] == ',' || s[i] == '\n' || s[i] == '\t')) {
      i++;
    }
  }

  bool get more {
    _skip();
    return i < s.length;
  }

  bool get isCommand {
    _skip();
    return i < s.length && RegExp('[MmLlHhVvCcSsQqTtAaZz]').hasMatch(s[i]);
  }

  String command() {
    _skip();
    return s[i++];
  }

  bool flag() {
    _skip();
    return s[i++] == '1';
  }

  double number() {
    _skip();
    final start = i;
    if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
    var dot = false;
    while (i < s.length) {
      final c = s[i];
      if (c == '.') {
        if (dot) break;
        dot = true;
      } else if (c == 'e' || c == 'E') {
        i++;
        if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
        continue;
      } else if (c.codeUnitAt(0) < 48 || c.codeUnitAt(0) > 57) {
        break;
      }
      i++;
    }
    return double.tryParse(s.substring(start, i)) ?? 0;
  }
}

