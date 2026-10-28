"""Writes ha-icons.plm: the add-on's icons in Vitreus's pencil, as stroke tables looked up with pick(k, ...), the way addon-pencil.plm's PIcon is built.
Icons are drawn on Material's 24 grid (0..24, y down) and stored about its middle."""
import math, sys

def arc(cx, cy, r, a0, a1, n):
    pts = [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]
    return [(pts[i], pts[i + 1]) for i in range(n)]

def poly(*pts, close=False):
    pts = list(pts) + ([pts[0]] if close else [])
    return [(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]

def rect(x0, y0, x1, y1, ch=0):
    if ch == 0:
        return poly((x0, y0), (x1, y0), (x1, y1), (x0, y1), close=True)
    return poly((x0 + ch, y0), (x1 - ch, y0), (x1, y0 + ch), (x1, y1 - ch), (x1 - ch, y1), (x0 + ch, y1), (x0, y1 - ch), (x0, y0 + ch), close=True)

def dot(x, y):
    return [((x - 0.15, y), (x + 0.15, y))]

def S(segs, w=1.8):
    return [(a, b, w) for a, b in segs]

def speaker():
    return S(poly((4, 9.5), (7.5, 9.5), (12, 5.5), (12, 18.5), (7.5, 14.5), (4, 14.5), close=True))

def house(right=18.5, rtop=9.5):
    return S(poly((3.5, 11), (12, 4), (20.5, 11))) + S(poly((5.5, 9.5), (5.5, 20), (right, 20), (right, rtop)))

# ── the interface's icons (in place of Material Symbols) ──
UI = {}
UI['edit'] = (S(poly((4, 20), (5, 15.5), (15.5, 5), (19, 8.5), (8.5, 19), (4, 20))) + S(poly((13.5, 7), (17, 10.5)), 1.4), [])
UI['check'] = (S(poly((5, 12.5), (9.5, 17), (19, 7.5)), 2.1), [])
UI['refresh'] = (S(poly((19.2, 4.2), (19.2, 9.8), (13.6, 9.8))), [(12, 12, 7, 8, 1.8)])
UI['settings'] = ([((12 + 7.2 * math.cos(math.radians(a)), 12 + 7.2 * math.sin(math.radians(a))), (12 + 9.6 * math.cos(math.radians(a)), 12 + 9.6 * math.sin(math.radians(a))), 2.4) for a in range(0, 360, 45)],
                  [(12, 12, 7, 0 - 1, 1.8), (12, 12, 2.8, -1, 1.6)])
UI['thermometer'] = (S(poly((10, 13.6), (10, 5.2))) + S(arc(12, 5.2, 2, 180, 360, 3)) + S(poly((14, 5.2), (14, 13.6))) + S(poly((12, 9), (12, 16)), 1.4), [(12, 17, 3.6, 7, 1.8)])
UI['drop'] = (S(arc(12, 14.5, 5.5, -30, 210, 6)) + S(poly((7.24, 11.75), (12, 3.5), (16.76, 11.75))), [])
UI['open_in_full'] = (S(poly((5, 19), (19, 5))) + S(poly((13.5, 5), (19, 5), (19, 10.5))) + S(poly((10.5, 19), (5, 19), (5, 13.5))), [])
UI['cloud_off'] = (S(poly((6.5, 18.5), (17.5, 18.5))) + S(arc(6.8, 15, 3.5, 90, 250, 3)) + S(arc(12, 10.8, 4.8, 200, 340, 4)) + S(arc(17.3, 14.3, 4.2, 280, 450, 3)) + S(poly((3.5, 3.5), (20.5, 20.5)), 2), [])
UI['home_device'] = (house(), [(12, 14.5, 2.2, -1, 1.6)])
UI['add_home'] = (house(18.5, 9.5)[:3] + S(poly((5.5, 9.5), (5.5, 20), (13, 20))) + S(poly((18.5, 9.5), (18.5, 13))) + S(poly((15, 17.5), (23, 17.5))) + S(poly((19, 13.5), (19, 21.5))), [])
UI['close'] = (S(poly((6, 6), (18, 18))) + S(poly((18, 6), (6, 18))), [])
UI['cube'] = (S(poly((12, 3), (20, 7.5), (20, 16.5), (12, 21), (4, 16.5), (4, 7.5), close=True)) + S(poly((4, 7.5), (12, 12), (20, 7.5)), 1.4) + S(poly((12, 12), (12, 21)), 1.4), [])
UI['open_in_new'] = (S(poly((11, 5), (5, 5), (5, 19), (19, 19), (19, 13))) + S(poly((10, 14), (19, 5))) + S(poly((13.5, 5), (19, 5), (19, 10.5))), [])
UI['schedule'] = (S(poly((12, 7), (12, 12), (15.5, 14.2))), [(12, 12, 8.5, -1, 1.8)])
UI['play_circle'] = (S(poly((10, 8.5), (15.5, 12), (10, 15.5), close=True)), [(12, 12, 8.5, -1, 1.8)])
UI['flag'] = (S(poly((6, 21), (6, 3.5))) + S(poly((6, 4.5), (18, 4.5), (15.5, 8.5), (18, 12.5), (6, 12.5))), [])
UI['pause'] = (S(poly((9, 6), (9, 18)), 2.6) + S(poly((15, 6), (15, 18)), 2.6), [])
UI['stop'] = (S(rect(7, 7, 17, 17)), [])
UI['videocam'] = (S(rect(3.5, 7, 15.5, 17)) + S(poly((15.5, 10.5), (20.5, 7.5), (20.5, 16.5), (15.5, 13.5))), [])
UI['play'] = (S(poly((8, 5.5), (19, 12), (8, 18.5), close=True)), [])
UI['power'] = (S(poly((12, 3), (12, 11.5)), 2), [(12, 12.5, 7.5, 7, 1.8)])
UI['remote'] = (S(rect(8.5, 9.5, 15.5, 21, 1.2)) + S(arc(12, 8.5, 4, 220, 320, 2), 1.5) + S(arc(12, 8.5, 7, 225, 315, 3), 1.5), [(12, 13.8, 1.6, -1, 1.5)])
UI['live_tv'] = (S(rect(3, 7, 21, 19, 1)) + S(poly((8, 3), (12, 7), (16, 3)), 1.5) + S(poly((10.5, 10.5), (14.5, 13), (10.5, 15.5), close=True), 1.6), [])
UI['volume_down'] = (speaker() + S(arc(12, 12, 4, -45, 45, 2)), [])
UI['skip_previous'] = (S(poly((6, 6), (6, 18)), 2.2) + S(poly((18, 6), (9, 12), (18, 18), close=True)), [])
UI['skip_next'] = (S(poly((18, 6), (18, 18)), 2.2) + S(poly((6, 6), (15, 12), (6, 18), close=True)), [])
UI['volume_up'] = (speaker() + S(arc(12, 12, 4, -45, 45, 2)) + S(arc(12, 12, 7.5, -50, 50, 3)), [])
UI['chevron_left'] = (S(poly((15, 5), (8, 12), (15, 19)), 2.1), [])
UI['tv'] = (S(rect(3, 5, 21, 17, 1)) + S(poly((8, 20.5), (16, 20.5))), [])
UI['play_pause'] = (S(poly((3, 6), (11, 12), (3, 18), close=True)) + S(poly((15, 6), (15, 18)), 2.2) + S(poly((20, 6), (20, 18)), 2.2), [])
UI['volume_off'] = (speaker() + S(poly((3, 3), (21, 21)), 2), [])
UI['add'] = (S(poly((12, 5), (12, 19)), 2) + S(poly((5, 12), (19, 12)), 2), [])
UI['remove'] = (S(poly((5, 12), (19, 12)), 2), [])

# ── the add-on's own device icons (the .svg files), in pencil ──
DEV = {}
DEV['tira-led'] = (S(poly((5.5, 10), (18.5, 10))) + S(poly((5.5, 16), (18.5, 16))) + S(arc(5.5, 13, 3, 90, 270, 3)) + S(arc(18.5, 13, 3, -90, 90, 3))
                   + S(dot(7, 13) + dot(10.33, 13) + dot(13.67, 13) + dot(17, 13), 2.4) + S(poly((12, 4.5), (12, 6.7)) + poly((7.2, 5.6), (8.2, 7.2)) + poly((16.8, 5.6), (15.8, 7.2)), 1.5), [])
DEV['farol-pared'] = (S(rect(3.5, 8, 6.1, 19)) + S(poly((6.1, 16.5), (12.9, 16.5))) + S(poly((12.2, 8.8), (15.5, 5.6), (18.8, 8.8), close=True)) + S(poly((15.5, 5.6), (15.5, 3.9)), 1.5)
                      + S(poly((12.9, 8.8), (12.9, 16.5)) + poly((18.1, 8.8), (18.1, 16.5))) + S(poly((12, 16.5), (19, 16.5))) + S(poly((15.5, 11.4), (15.5, 13.6)), 1.5), [])
DEV['lampara-pergola'] = (S(poly((12, 2.5), (12, 7.5)), 1.5) + S(arc(12, 13.5, 5.5, 180, 360, 5)) + S(poly((6.5, 13.5), (17.5, 13.5))) + S(arc(12, 13.5, 1.6, 0, 180, 2), 1.5)
                          + S(poly((12, 17.6), (12, 19.9)) + poly((7.4, 16.6), (6.1, 18.3)) + poly((16.6, 16.6), (17.9, 18.3)), 1.5), [])
DEV['lampara-pie'] = (S(poly((8.2, 3.2), (15.8, 3.2), (18, 9.5), (6, 9.5), close=True)) + S(poly((12, 9.5), (12, 19.8))) + S(poly((8.3, 20.6), (15.7, 20.6))) + S(poly((14.6, 9.5), (14.6, 11.3)), 1.4), [])
DEV['impresora-3d'] = (S(rect(3, 3, 21, 21, 1.4)) + S(poly((3, 6.6), (21, 6.6)), 1.5) + S(rect(5.6, 9, 15.2, 18.4)) + S(poly((7.6, 16.4), (13.2, 16.4)), 1.4)
                       + S(poly((9.4, 10.9), (11.4, 10.9), (10.4, 12.1), close=True), 1.3)
                       + S(poly((18.3, 15.4), (16.8, 13.9), (17.5, 12.7), (18.3, 13.4), (19.1, 12.7), (19.8, 13.9), (18.3, 15.4)), 1.3), [])
DEV['reproductor'] = (S(rect(3, 3, 21, 21, 3)) + S(poly((9, 8.4), (9, 14.5), (10.6, 16.1), (11.1, 16.1)), 1.7) + S(poly((7.4, 10.6), (10.7, 10.6)), 1.7) + S(poly((12.6, 10.6), (14.6, 16), (16.6, 10.6)), 1.7), [])
DEV['terrario'] = (S(poly((3.5, 7.2), (20.5, 7.2))) + S(poly((4.5, 7.2), (4.5, 18.8), (6.1, 20.4), (17.9, 20.4), (19.5, 18.8), (19.5, 7.2))) + S(poly((5.8, 4.2), (18.2, 4.2)))
                   + S(poly((4.6, 17), (19.4, 17)), 1.4) + S(poly((10, 17), (10, 12.4)), 1.5) + S(poly((10, 13.6), (11.4, 11.1), (13.6, 10.2), (12.6, 12.6), (10, 13.6)), 1.4)
                   + S(poly((10, 14.8), (8.6, 12.8), (7.4, 12.3), (8.3, 14.2), (10, 14.8)), 1.4) + S(poly((15.2, 17), (15.2, 15.4)), 1.4), [])
DEV['calefactor'] = (S(rect(4, 9, 20, 21, 2)) + [((12, 15), (12 + 3 * math.cos(math.radians(a)), 15 + 3 * math.sin(math.radians(a))), 1.4) for a in (-70, 50, 170)]
                     + S(poly((8.5, 6.8), (8, 5.4), (8.5, 4)) + poly((12, 6.8), (11.5, 5.4), (12, 4)) + poly((15.5, 6.8), (15, 5.4), (15.5, 4)), 1.4), [(12, 15, 3.6, -1, 1.5)])

def fmt(v):
    v = round(v, 2)
    return ("%g" % v) if v != int(v) else str(int(v))

def emit(name, icons, ncirc, doc):
    keys = list(icons)
    nseg = max(len(icons[k][0]) for k in keys)
    out = []
    out.append("    //  " + doc)
    out.append("    //  k: " + " · ".join("%d %s" % (i, k) for i, k in enumerate(keys)))
    out.append("    component %s(k: number, cx: number, cy: number, c: color, a: number, s: number, f: number = fr, z: number = 1) {" % name)
    out.append("        let iu = u * z")
    for j in range(nseg):
        cols = {"ax": [], "ay": [], "bx": [], "by": [], "w": [], "on": []}
        for k in keys:
            segs = icons[k][0]
            if j < len(segs):
                (x1, y1), (x2, y2), w = segs[j]
                cols["ax"].append(x1 - 12); cols["ay"].append(y1 - 12); cols["bx"].append(x2 - 12); cols["by"].append(y2 - 12); cols["w"].append(w); cols["on"].append(1)
            else:
                for c in ("ax", "ay", "bx", "by"): cols[c].append(0)
                cols["w"].append(1); cols["on"].append(0)
        def P(c): return "pick(k, " + ", ".join(fmt(v) for v in cols[c]) + ")"
        on = "a" if all(cols["on"]) else "a * " + P("on")
        out.append("        PLn(ax: cx + %s * iu, ay: cy + %s * iu, bx: cx + %s * iu, by: cy + %s * iu, s: s + %d, wd: %s * iu, c: c, a: %s, f: f)" % (P("ax"), P("ay"), P("bx"), P("by"), j + 1, P("w"), on))
    for j in range(ncirc):
        cols = {"x": [], "y": [], "r": [], "g": [], "w": [], "on": []}
        for k in keys:
            cs = icons[k][1]
            if j < len(cs):
                x, y, r, g, w = cs[j]
                cols["x"].append(x - 12); cols["y"].append(y - 12); cols["r"].append(r); cols["g"].append(g); cols["w"].append(w); cols["on"].append(1)
            else:
                cols["x"].append(0); cols["y"].append(0); cols["r"].append(1); cols["g"].append(-1); cols["w"].append(1); cols["on"].append(0)
        def P(c): return "pick(k, " + ", ".join(fmt(v) for v in cols[c]) + ")"
        out.append("        PCir(cx: cx + %s * iu, cy: cy + %s * iu, rad: %s * iu, s: s + %d, wd: %s * iu, c: c, a: a * %s, gapk: %s, f: f, j: 0.6)" % (P("x"), P("y"), P("r"), 40 + j, P("w"), P("on"), P("g")))
    out.append("    }")
    return "\n".join(out), keys, nseg

ui_src, ui_keys, ui_n = emit("HUi", UI, 2, "The interface's icons, in place of Material Symbols: the buttons, the cards' heads and the remote.")
dev_src, dev_keys, dev_n = emit("HDev", DEV, 1, "The add-on's own device icons (its .svg files: tira-led.svg and the rest), drawn in pencil instead of as pictures, so they boil and tint like the shell's.")
src = '''language 0.1

//  The Home Assistant add-on's icons in Vitreus's pencil (addon-pencil.plm's PLn and PCir): one table of strokes per set, looked up with pick(k, …), as the add-on
//  template's PIcon is built (one drawing per icon would be instantiated for every row of a model). Drawn on Material's 24 grid about (cx, cy), `z` times the
//  panel's unit; `f` is the frame its lines are drawn on (the scene's: they boil; 0: they rest, still crooked). Generated: each set's strokes are listed in the
//  add-on's repository (tools/icons.py), which writes this file.

library HaIcons {
''' + ui_src + "\n\n" + dev_src + "\n}\n"
open(sys.argv[1], "w").write(src)
print("UI", ui_n, "segments;", {k: i for i, k in enumerate(ui_keys)})
print("DEV", dev_n, "segments;", {k: i for i, k in enumerate(dev_keys)})
