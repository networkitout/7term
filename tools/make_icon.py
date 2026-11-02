"""Usage: python3 tools/make_icon.py <AppIcon.appiconset> [preview.png]

Generates 7 Term's app icon: a red 5x7 dot-matrix "7" on red-tinted black,
in the macOS icon shape (824px rounded rect on a 1024 canvas)."""
import json, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
RED = (255, 52, 52)
GLYPH = ["#####", "....#", "...#.", "..#..", "..#..", "..#..", "..#.."]

def master(size=1024):
    S = size
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inset, radius = int(S * 0.098), int(S * 0.18)
    box = (inset, inset, S - inset, S - inset)

    # Background: vertical gradient, red-tinted near-black.
    grad = Image.new("RGBA", (S, S))
    top, bottom = (30, 16, 16), (11, 7, 7)
    for y in range(S):
        t = y / (S - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        ImageDraw.Draw(grad).line([(0, y), (S, y)], fill=c + (255,))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    img.paste(grad, (0, 0), mask)

    # Faint dot grid behind the glyph, like an unlit LED panel.
    dot = int(S * 0.082)
    cols, rows = 5, 7
    gx = (S - cols * dot) // 2
    gy = (S - rows * dot) // 2 - int(S * 0.01)
    unlit = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    du = ImageDraw.Draw(unlit)
    gap = max(1, int(dot * 0.1))
    for y in range(-1, rows + 1):
        for x in range(-1, cols + 1):
            x0, y0 = gx + x * dot + gap, gy + y * dot + gap
            du.rectangle([x0, y0, x0 + dot - 2 * gap, y0 + dot - 2 * gap], fill=(255, 52, 52, 18))
    img.alpha_composite(Image.composite(unlit, Image.new("RGBA", (S, S)), mask))

    # Lit dots, with a glow underneath.
    lit = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dl = ImageDraw.Draw(lit)
    for y, row in enumerate(GLYPH):
        for x, cell in enumerate(row):
            if cell == "#":
                x0, y0 = gx + x * dot + gap, gy + y * dot + gap
                dl.rectangle([x0, y0, x0 + dot - 2 * gap, y0 + dot - 2 * gap], fill=RED + (255,))
    glow = lit.filter(ImageFilter.GaussianBlur(S * 0.03))
    img.alpha_composite(Image.composite(glow, Image.new("RGBA", (S, S)), mask))
    img.alpha_composite(lit)

    # Thin inner edge so the icon reads on dark Docks.
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(box, radius=radius, outline=(255, 90, 90, 40), width=max(1, S // 256))
    img.alpha_composite(edge)
    return img

big = master(1024)
if len(sys.argv) > 2:
    big.save(sys.argv[2])  # optional full-size preview, kept out of the asset catalog

entries = []
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = points * scale
        name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        big.resize((px, px), Image.LANCZOS).save(OUT / name)
        entries.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})
(OUT / "Contents.json").write_text(json.dumps({"images": entries, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
