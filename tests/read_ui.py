"""
Baca UI dari screenshot: OCR teks + analisis warna & layout.
Output: teks yang terlihat + palet warna + posisi elemen.
"""
import sys
import json
from collections import Counter
from PIL import Image


def analyze(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    out = {"file": path, "size": [w, h]}

    # --- palet warna ---
    small = im.resize((80, 80))
    counts = Counter(small.getdata())
    total = sum(counts.values())
    palette = []
    for col, cnt in counts.most_common(12):
        palette.append({
            "rgb": list(col),
            "hex": "#%02x%02x%02x" % col,
            "pct": round(100 * cnt / total, 1),
        })
    out["palette"] = palette

    # --- deteksi panel: cari region warna seragam yang besar ---
    px = im.load()
    panels = []
    if palette:
        target = tuple(palette[0]["rgb"])
        step = 6
        pts = []
        for y in range(0, h, step):
            for x in range(0, w, step):
                r, g, b = px[x, y]
                if abs(r - target[0]) <= 12 and abs(g - target[1]) <= 12 and abs(b - target[2]) <= 12:
                    pts.append((x, y))
        if pts:
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            panels.append({
                "x": min(xs), "y": min(ys),
                "w": max(xs) - min(xs), "h": max(ys) - min(ys),
                "color": "#%02x%02x%02x" % target,
            })
    out["background_panel"] = panels

    return out


def ocr(path):
    try:
        from rapidocr_onnxruntime import RapidOCR
    except ImportError:
        return {"error": "rapidocr tidak terpasang"}
    engine = RapidOCR()
    result, _ = engine(path)
    if not result:
        return {"texts": []}
    items = []
    for box, text, conf in result:
        xs = [p[0] for p in box]
        ys = [p[1] for p in box]
        items.append({
            "text": text,
            "conf": round(float(conf), 2),
            "x": int(min(xs)), "y": int(min(ys)),
            "cx": int(sum(xs) / len(xs)), "cy": int(sum(ys) / len(ys)),
        })
    items.sort(key=lambda i: (i["y"], i["x"]))
    return {"texts": items}


if __name__ == "__main__":
    path = sys.argv[1]
    print("=== ANALISA ===")
    print(json.dumps(analyze(path), indent=2, ensure_ascii=False))
    print()
    print("=== OCR ===")
    print(json.dumps(ocr(path), indent=2, ensure_ascii=False))
