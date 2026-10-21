// AbhiShare animated splash screen: pure Flutter code, no video, no extra packages.
//
// This is the same animation as the splash video, drawn live with a CustomPainter:
// sky + sun + drifting clouds, skyline and hills rising, the blue and green dots
// flying in along curves, the "A" mark drawing in, "abhishare" rising letter by
// letter, the tagline wiping in, a shine sweep, then a gentle hold. (~4.4 s)
//
// Setup
//   1. Copy abhishare_logo.png (transparent PNG) to assets/images/abhishare_logo.png
//      and register it in pubspec.yaml:
//        flutter:
//          assets:
//            - assets/images/abhishare_logo.png
//   2. Add this file to your project and use it as your first screen:
//
//        home: AbhiShareSplash(
//          waitFor: yourExistingStartupFuture,   // optional: auth/token check etc.
//          onFinished: (context) => fadeReplace(context, const YourExistingGate()),
//        )
//
//   3. (Recommended) make the native launch screen plain white
//      (flutter_native_splash: color: "#FFFFFF") so it blends into the first frame.
//
// Sizing: everything is computed from the available width/height each frame, so it
// adapts to any phone, tablet, orientation or split-screen window. Your startup
// logic is never blocked: the animation is finite, `waitFor` errors are ignored
// here, and `maxWait` is a hard safety timeout.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ───────────────────────── Widget ─────────────────────────
class AbhiShareSplash extends StatefulWidget {
  const AbhiShareSplash({
    super.key,
    required this.onFinished,
    this.waitFor,
    this.logoAsset = 'assets/images/abhishare_logo.png',
    this.tagline = 'Share more. Save more.',
    this.fontFamily,
    this.duration = const Duration(milliseconds: 4400),
    this.maxWait = const Duration(seconds: 10),
  });

  /// Called once, after the animation has finished AND [waitFor] has completed.
  final void Function(BuildContext context) onFinished;

  /// Optional existing startup work (auth check, remote config...).
  final Future<void>? waitFor;

  final String logoAsset;
  final String tagline;
  final String? fontFamily;
  final Duration duration;
  final Duration maxWait;

  @override
  State<AbhiShareSplash> createState() => _AbhiShareSplashState();
}

class _AbhiShareSplashState extends State<AbhiShareSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  ui.Image? _logo;
  Timer? _guard;
  bool _reduce = false, _started = false, _finished = false, _animDone = false, _waitDone = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          _animDone = true;
          _check();
        }
      });
    (widget.waitFor ?? Future<void>.value()).catchError((_) {}).then((_) {
      _waitDone = true;
      _check();
    });
    _guard = Timer(widget.maxWait, _finish);
    _begin();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    if (_reduce && _c.value == 0) {
      _c.value = 1;
      Timer(const Duration(milliseconds: 700), () {
        _animDone = true;
        _check();
      });
    }
  }

  Future<void> _load() async {
    try {
      final data = await rootBundle.load(widget.logoAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _logo = frame.image);
    } catch (_) {
      // In case of asset failure, ensure animation continues gracefully
    }
  }

  void _begin() {
    if (_started) return;
    _started = true;
    if (_reduce) {
      _c.value = 1; // show the finished logo frame, then continue
      Timer(const Duration(milliseconds: 700), () {
        _animDone = true;
        _check();
      });
    } else {
      _c.forward();
    }
  }

  void _check() {
    if (_animDone && _waitDone) _finish();
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    _guard?.cancel();
    widget.onFinished(context);
  }

  @override
  void dispose() {
    _guard?.cancel();
    _c.dispose();
    _logo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _SplashPainter(_c, _logo, widget.tagline, widget.fontFamily),
          ),
        ),
      ),
    );
  }
}

/// Smooth hand-off from the splash to the next screen.
void fadeReplace(BuildContext context, Widget page) {
  Navigator.of(context).pushReplacement(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, anim, secondaryAnim, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

// ───────────────────────── Math helpers ─────────────────────────
double _cl(double x, [double a = 0, double b = 1]) => x < a ? a : (x > b ? b : x);
double _pr(double t, double a, double b) => _cl((t - a) / (b - a));
double _lerp(double a, double b, double k) => a + (b - a) * k;
double _eo(double x) {
  final v = 1 - x;
  return 1 - v * v * v;
}

double _eio(double x) {
  if (x < .5) return 4 * x * x * x;
  final v = -2 * x + 2;
  return 1 - v * v * v / 2;
}

Color _wa(double a) => Color.fromRGBO(255, 255, 255, _cl(a));
Color _rgba(int r, int g, int b, double a) => Color.fromRGBO(r, g, b, _cl(a));

// ───────────────────────── Logo geometry ─────────────────────────
// Measured on the logo PNG as fractions of its width/height, so it works at any
// resolution of the same artwork.
const _box = [0.0659, 0.16251, 0.9469, 0.89827]; // whole logo: l, t, r, b
const _mark = [0.15675, 0.16187, 0.84069, 0.73385]; // "A" mark: l, t, r, b
const _word = [0.7556, 0.89955]; // wordmark rows: top, bottom
const _dots = [
  [0.21049, 0.42418, 0.05886], // blue dot: cx, cy, r
  [0.77031, 0.30934, 0.05566], // green dot
];
const _letters = [
  [0.0659, 0.18106], [0.19322, 0.30646], [0.30966, 0.41267], [0.42099, 0.45234], [0.46001, 0.54575],
  [0.55022, 0.65259], [0.65579, 0.76967], [0.77671, 0.82853], [0.82853, 0.9469],
];
const _cloudList = [
  [250.0, 200.0, 1.5], [800.0, 520.0, 1.2], [1300.0, 160.0, 1.4], [450.0, 900.0, 1.1], [1150.0, 1000.0, 1.3],
];
const _blobs = [
  [0.0, 0.0, 90.0, 50.0], [110.0, -25.0, 110.0, 70.0], [230.0, 0.0, 95.0, 52.0],
  [60.0, 25.0, 70.0, 38.0], [170.0, 28.0, 80.0, 38.0],
];
const double _th = 24 * math.pi / 180; // mark wipe direction
const double _ph = 22 * math.pi / 180; // shine direction
final List<Color> _shineColors = [
  _wa(0),
  _wa(.6 * .108),
  _wa(.6 * .37),
  _wa(.6 * .78),
  _wa(.6),
  _wa(.6 * .78),
  _wa(.6 * .37),
  _wa(.6 * .108),
  _wa(0),
];
final List<double> _shineStops = List.generate(9, (i) => i / 8);

class _C {
  _C(this.cv, this.w, this.h, this.k, this.tt);
  final Canvas cv;
  final double w, h, k, tt; // k: design-px -> screen-px scale (design is 1080 wide)
  double fy(double ref) => ref * h / 2340; // vertical design coordinate -> screen
}

// ───────────────────────── Painter ─────────────────────────
class _SplashPainter extends CustomPainter {
  _SplashPainter(this.anim, this.logo, this.tagline, this.font) : super(repaint: anim);
  final Animation<double> anim;
  final ui.Image? logo;
  final String tagline;
  final String? font;
  TextPainter? _tp;
  double _tpK = -1;

  @override
  bool shouldRepaint(_SplashPainter old) => old.logo != logo || old.tagline != tagline;

  @override
  void paint(Canvas cv, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final tt = anim.value * 8.0; // internal timeline: 0..8
    final k = math.min(w / 1080, h / 1700);
    final c = _C(cv, w, h, k, tt);
    cv.save();
    cv.clipRect(Offset.zero & size);
    _sky(c);
    _clouds(c);
    _skyline(c);
    final par = 14 * math.sin(2 * math.pi * tt / 8);
    _hill(c, base: 2000, amp: 30, f1: .0035, f2: .009, ph: 1, par: par * .6, c0: const [168, 230, 193], c1: const [127, 214, 164], slide: 300, p: _eo(_pr(tt, .2, 1.4)));
    _hill(c, base: 2180, amp: 28, f1: .003, f2: .008, ph: 3, par: -par, c0: const [88, 200, 134], c1: const [46, 155, 92], slide: 360, p: _eo(_pr(tt, .35, 1.6)));
    final img = logo;
    if (img != null) {
      _logoLayers(c, img);
    }
    final veil = .95 * (1 - _eo(_pr(tt, 0, .9)));
    if (veil > .004) cv.drawRect(Offset.zero & size, Paint()..color = _wa(veil));
    cv.restore();
  }

  // ── sky, sun, clouds ──
  void _sky(_C c) {
    final r = Offset.zero & Size(c.w, c.h);
    c.cv.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, c.h),
          const [Color(0xFFAAD4FF), Color(0xFFD4ECFF), Color(0xFFF5FBFF)],
          const [0, .55, 1],
        ),
    );
    final sc = Offset(c.w * .8333, c.h * .1282), sg = 300 * c.k;
    c.cv.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          sc,
          sg * 2.2,
          [_rgba(255, 246, 205, .7), _rgba(255, 246, 205, .43), _rgba(255, 246, 205, .1), _rgba(255, 246, 205, 0)],
          const [0, .45, .9, 1],
        ),
    );
    c.cv.drawCircle(sc, 60 * c.k, Paint()..color = const Color(0xFFFFFAE1));
  }

  void _clouds(_C c) {
    const per = 1700.0;
    final off = (c.tt * 60) % per;
    final n = (c.w / (per * c.k)).ceil() + 2;
    final p = Paint()
      ..color = _wa(.88)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 9 * c.k);
    for (final cl in _cloudList) {
      for (var j = 0; j < n; j++) {
        final ox = cl[0] + j * per - off;
        if (ox * c.k < -450 * c.k || ox * c.k > c.w + 100) continue;
        final path = Path();
        for (final b in _blobs) {
          path.addOval(Rect.fromCenter(
            center: Offset((ox + b[0] * cl[2]) * c.k, c.fy(cl[1] + 40 + b[1] * cl[2])),
            width: b[2] * cl[2] * 2 * c.k,
            height: b[3] * cl[2] * 2 * c.k,
          ));
        }
        c.cv.drawPath(path, p);
      }
    }
  }

  // ── skyline and hills ──
  void _skyline(_C c) {
    final base = c.fy(2010);
    var x = -10.0;
    var i = 0;
    while (x * c.k < c.w) {
      final bw = 80 + (i * 37) % 60, bh = 50 + (i * 53) % 110;
      final p = _eo(_pr(c.tt, .4 + i * .025, 1.5 + i * .025));
      if (p > 0) {
        final left = x * c.k, top = base - bh * c.k + (1 - p) * bh * c.k;
        final r = Rect.fromLTWH(left, top, bw * c.k, bh * c.k);
        c.cv.drawRect(
          r,
          Paint()..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [_rgba(188, 210, 246, p), _rgba(225, 237, 253, p)]),
        );
        final wp = Paint()..color = _wa(.78 * p), lp = Paint()..color = _rgba(255, 231, 160, p);
        for (var wy = 10; wy < bh - 6; wy += 20) {
          for (var wx = 8; wx < bw - 8; wx += 16) {
            c.cv.drawRect(
              Rect.fromLTWH(left + wx * c.k, top + wy * c.k, 7 * c.k, 9 * c.k),
              (i + wx + wy) % 5 == 0 ? lp : wp,
            );
          }
        }
      }
      x += bw + 6 + (i * 11) % 9;
      i++;
    }
  }

  void _hill(_C c,
      {required double base,
      required double amp,
      required double f1,
      required double f2,
      required double ph,
      required double par,
      required List<int> c0,
      required List<int> c1,
      required double slide,
      required double p}) {
    if (p <= 0) return;
    final yb = c.fy(base) + (1 - p) * slide * c.h / 2340;
    final path = Path()..moveTo(0, c.h + 4);
    for (var x = 0.0; x <= c.w + 16; x += 12) {
      final xr = x / c.k + 120 - par;
      path.lineTo(x, yb + (amp * math.sin(xr * f1 + ph) + amp * .45 * math.sin(xr * f2 + ph * 2)) * c.k);
    }
    path
      ..lineTo(c.w + 16, c.h + 4)
      ..close();
    final top = yb - amp * c.k;
    c.cv.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, top),
          Offset(0, top + 220 * c.k),
          [_rgba(c0[0], c0[1], c0[2], p), _rgba(c1[0], c1[1], c1[2], p)],
        ),
    );
  }

  // ── logo: mark, dots, letters, tagline, shine ──
  Paint _ip(double a) => Paint()
    ..filterQuality = FilterQuality.high
    ..color = _wa(a);

  void _logoLayers(_C c, ui.Image logo) {
    final cv = c.cv, k = c.k, tt = c.tt;
    final iw = logo.width.toDouble(), ih = logo.height.toDouble();
    final bx0 = _box[0] * iw, by0 = _box[1] * ih, bx1 = _box[2] * iw, by1 = _box[3] * ih;
    final srcW = bx1 - bx0, srcH = by1 - by0;
    final logoW = math.min(c.w * .64, c.h * .26 * srcW / srcH), sc = logoW / srcW, logoH = srcH * sc;
    final cx0 = c.w / 2 - logoW / 2, cy0 = c.h * (1000 / 2340) - logoH / 2;
    Rect m(Rect r) => Rect.fromLTRB(cx0 + (r.left - bx0) * sc, cy0 + (r.top - by0) * sc, cx0 + (r.right - bx0) * sc, cy0 + (r.bottom - by0) * sc);
    Offset mp(double x, double y) => Offset(cx0 + (x - bx0) * sc, cy0 + (y - by0) * sc);
    final amp = _eo(_pr(tt, 5.6, 6.4)), fy = 3 * k * amp * math.sin(2 * math.pi * (tt - 5.6) / 3.2);
    const white = Color(0xFFFFFFFF), clear = Color(0x00FFFFFF);

    // "A" mark: diagonal wipe along the swoosh, dots cut out (they fly in separately)
    final pm = _eio(_pr(tt, 1.5, 3.0));
    if (pm > 0) {
      final src = Rect.fromLTRB(_mark[0] * iw, _mark[1] * ih, _mark[2] * iw, _mark[3] * ih), dst = m(src);
      final circ = Path();
      for (final d in _dots) {
        circ.addOval(Rect.fromCircle(center: mp(d[0] * iw, d[1] * ih), radius: (d[2] * iw + 4) * sc));
      }
      final clip = Path.combine(PathOperation.difference, Path()..addRect(dst), circ);
      final e = _eo(_pr(tt, 1.5, 3.2));
      final ctr = dst.center, lb = dst.inflate(4);
      cv.save();
      cv.translate(ctr.dx, ctr.dy + fy + (1 - e) * 22 * k);
      cv.scale(.94 + .06 * e);
      cv.translate(-ctr.dx, -ctr.dy);
      cv.saveLayer(lb, Paint());
      cv.save();
      cv.clipPath(clip);
      cv.drawImageRect(logo, src, dst, _ip(1));
      cv.restore();
      final R = dst.width / 2 * math.cos(_th) + dst.height / 2 * math.sin(_th), soft = 220 * k;
      final th = _lerp(-R - soft, R + soft, pm), d = Offset(math.cos(_th), -math.sin(_th));
      cv.drawRect(
        lb,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(ctr + d * (th - soft), ctr + d * th, [white, clear]),
      );
      cv.restore();
      cv.restore();
    }

    // Blue and green dots: curved flights with soft trails, landing pop and ripple
    for (var i = 0; i < 2; i++) {
      final d = _dots[i];
      final E = mp(d[0] * iw, d[1] * ih), dr = d[2] * iw, rD = (dr + 4) * sc;
      final t0 = i == 0 ? .4 : .7, t1 = i == 0 ? 1.9 : 2.2;
      final al = _pr(tt, t0, t0 + .2);
      if (al <= 0) continue;
      final p0 = i == 0 ? Offset(-.1852 * c.w, .7479 * c.h) : Offset(1.2037 * c.w, -.0855 * c.h);
      final mid = (p0 + E) / 2, dx = E.dx - p0.dx, dy = E.dy - p0.dy, len = math.sqrt(dx * dx + dy * dy);
      final cc = i == 0
          ? Offset(mid.dx - dy / len * 420 * k, mid.dy + dx / len * 420 * k)
          : Offset(mid.dx + dy / len * 420 * k, mid.dy - dx / len * 420 * k);
      Offset bez(double u) {
        final v = 1 - u;
        return Offset(v * v * p0.dx + 2 * v * u * cc.dx + u * u * E.dx, v * v * p0.dy + 2 * v * u * cc.dy + u * u * E.dy);
      }

      final u = _eo(_pr(tt, t0, t1));
      final s = (.35 + .65 * _eo(_pr(tt, t0, t0 + .6))) * (1 + .14 * math.sin(math.pi * _pr(tt, t1, t1 + .45)));
      final bob = 5 * k * amp * math.sin(2 * math.pi * (tt - 5.6) / 3.2 + (i == 0 ? 0 : math.pi));
      final pos = bez(u) + Offset(0, fy + bob);
      final col = i == 0 ? const [30, 100, 255] : const [60, 200, 110];
      if (u < .999) {
        final tp = Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * k);
        for (var j = 0; j < 14; j++) {
          final uu = math.max(0.0, u - .30 * (1 - u) * j / 13);
          tp.color = _rgba(col[0], col[1], col[2], .30 * (1 - j / 14) * al);
          cv.drawCircle(bez(uu) + Offset(0, fy), rD * s * (1 - j / 14) * .85, tp);
        }
      }
      final tr = _pr(tt, t1, t1 + .7);
      if (tr > 0 && tr < 1) {
        cv.drawCircle(
          E + Offset(0, fy),
          rD * (1 + 1.4 * _eo(tr)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5 * k
            ..color = _rgba(col[0], col[1], col[2], .5 * (1 - tr)),
        );
      }
      final half = dr + 5;
      cv.save();
      cv.translate(pos.dx, pos.dy);
      cv.scale(s);
      cv.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: rD)));
      cv.drawImageRect(
        logo,
        Rect.fromCenter(center: Offset(d[0] * iw, d[1] * ih), width: 2 * half, height: 2 * half),
        Rect.fromCenter(center: Offset.zero, width: 2 * half * sc, height: 2 * half * sc),
        _ip(al),
      );
      cv.restore();
    }

    // "abhishare": letters rise in one by one
    final wy0 = _word[0] * ih, wy1 = _word[1] * ih;
    for (var i = 0; i < _letters.length; i++) {
      final p = _eo(_pr(tt, 2.7 + i * .07, 3.5 + i * .07));
      if (p <= 0) continue;
      final src = Rect.fromLTRB(_letters[i][0] * iw, wy0, _letters[i][1] * iw, wy1), dst = m(src);
      cv.save();
      cv.translate(dst.center.dx, dst.center.dy + fy + (1 - p) * 60 * k);
      cv.scale(.85 + .15 * p);
      cv.drawImageRect(logo, src, dst.shift(-dst.center), _ip(p));
      cv.restore();
    }

    // Tagline: soft left-to-right wipe
    final pt = _eo(_pr(tt, 3.9, 4.8));
    if (pt > 0) {
      if (_tp == null || _tpK != k) {
        _tp = TextPainter(
          text: TextSpan(
            text: tagline,
            style: TextStyle(fontFamily: font, fontSize: 54 * k, fontWeight: FontWeight.w600, letterSpacing: 4 * k, color: const Color(0xFF0F3A8F)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        _tpK = k;
      }
      final tp = _tp!;
      final pos = Offset(c.w / 2 - tp.width / 2, cy0 + logoH + 125 * k - tp.height / 2 + fy + (1 - pt) * 16 * k);
      final th = _lerp(-70 * k, tp.width + 70 * k, pt), lb = Rect.fromLTWH(pos.dx - 10, pos.dy - 10, tp.width + 20, tp.height + 20);
      cv.saveLayer(lb, Paint());
      tp.paint(cv, pos);
      cv.drawRect(
        lb,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(Offset(pos.dx + th - 70 * k, 0), Offset(pos.dx + th, 0), [white, clear]),
      );
      cv.restore();
    }

    // Shine sweep clipped to the logo's own shape
    final ps = _pr(tt, 4.7, 5.8);
    if (ps > 0 && ps < 1) {
      final dst = Rect.fromLTWH(cx0, cy0 + fy, logoW, logoH), ctr = dst.center, d2 = Offset(math.cos(_ph), math.sin(_ph));
      final r2 = dst.width / 2 * math.cos(_ph) + dst.height / 2 * math.sin(_ph);
      final pos = _lerp(-r2 - 120 * k, r2 + 120 * k, _eio(ps));
      cv.saveLayer(dst.inflate(4), Paint());
      cv.drawImageRect(logo, Rect.fromLTRB(bx0, by0, bx1, by1), dst, Paint()..filterQuality = FilterQuality.high);
      cv.drawRect(
        dst.inflate(4),
        Paint()
          ..blendMode = BlendMode.srcIn
          ..shader = ui.Gradient.linear(ctr + d2 * (pos - 110 * k), ctr + d2 * (pos + 110 * k), _shineColors, _shineStops),
      );
      cv.restore();
    }

    // Glints on the dots
    for (var i = 0; i < 2; i++) {
      final t0 = i == 0 ? 5.0 : 5.25, kk = math.sin(math.pi * _pr(tt, t0, t0 + .7));
      if (kk <= .02) continue;
      final d = _dots[i], e = mp(d[0] * iw, d[1] * ih), r = (d[2] * iw + 4) * sc;
      final sx = e.dx + r * .45, sy = e.dy - r * .5 + fy, z = 40 * k * kk, q = z * .16;
      cv.drawPath(
        Path()
          ..moveTo(sx, sy - z)
          ..lineTo(sx + q, sy - q)
          ..lineTo(sx + z, sy)
          ..lineTo(sx + q, sy + q)
          ..lineTo(sx, sy + z)
          ..lineTo(sx - q, sy + q)
          ..lineTo(sx - z, sy)
          ..lineTo(sx - q, sy - q)
          ..close(),
        Paint()..color = _wa(.92 * kk),
      );
    }
  }
}
