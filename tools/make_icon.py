"""Usage:
  python3 tools/make_icon.py <AppIcon.appiconset> [preview.png]
      7 Term's app icon (red), at every macOS size.
  python3 tools/make_icon.py --green <AppIconGreen.imageset>
      The 6 Bits green version, one 1024px image, used as the Dock icon
      while the 6 Bits theme is on.

A 5x7 dot-matrix "7" on tinted black, in the macOS icon shape (824px
rounded rect on a 1024 canvas)."""
import json, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

GLYPH = ["#####", "....#", "...#.", "..#..", "..#..", "..#..", "..#.."]

# accent, gradient top, gradient bottom, edge
RED = ((255, 52, 52), (30, 16, 16), (11, 7, 7), (255, 90, 90))
GREEN = ((52, 255, 104), (14, 26, 17), (6, 10, 7), (90, 255, 130))   # 6 Bits #34FF68 on #090D0A


def master(colors, size=1024):
    accent, top, bottom, edge_color = colors
    S = size
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inset, radius = int(S * 0.098), int(S * 0.18)
    box = (inset, inset, S - inset, S - inset)

    grad = Image.new("RGBA", (S, S))
    draw = ImageDraw.Draw(grad)
    for y in range(S):
        t = y / (S - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        draw.line([(0, y), (S, y)], fill=c + (255,))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    img.paste(grad, (0, 0), mask)

    dot = int(S * 0.082)
    cols, rows = 5, 7
    gx = (S - cols * dot) // 2
    gy = (S - rows * dot) // 2 - int(S * 0.01)
    gap = max(1, int(dot * 0.1))

    unlit = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    du = ImageDraw.Draw(unlit)
    for y in range(-1, rows + 1):
        for x in range(-1, cols + 1):
            x0, y0 = gx + x * dot + gap, gy + y * dot + gap
            du.rectangle([x0, y0, x0 + dot - 2 * gap, y0 + dot - 2 * gap], fill=accent + (18,))
    img.alpha_composite(Image.composite(unlit, Image.new("RGBA", (S, S)), mask))

    lit = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dl = ImageDraw.Draw(lit)
    for y, row in enumerate(GLYPH):
        for x, cell in enumerate(row):
            if cell == "#":
                x0, y0 = gx + x * dot + gap, gy + y * dot + gap
                dl.rectangle([x0, y0, x0 + dot - 2 * gap, y0 + dot - 2 * gap], fill=accent + (255,))
    glow = lit.filter(ImageFilter.GaussianBlur(S * 0.03))
    img.alpha_composite(Image.composite(glow, Image.new("RGBA", (S, S)), mask))
    img.alpha_composite(lit)

    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(box, radius=radius, outline=edge_color + (40,), width=max(1, S // 256))
    img.alpha_composite(edge)
    return img


def write_appiconset(out, preview=None):
    out.mkdir(parents=True, exist_ok=True)
    big = master(RED)
    if preview:
        big.save(preview)
    entries = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            big.resize((px, px), Image.LANCZOS).save(out / name)
            entries.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})
    (out / "Contents.json").write_text(json.dumps({"images": entries, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def write_green_imageset(out):
    out.mkdir(parents=True, exist_ok=True)
    master(GREEN).save(out / "icon.png")
    contents = {"images": [{"idiom": "mac", "filename": "icon.png"}], "info": {"author": "xcode", "version": 1}}
    (out / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


if __name__ == "__main__":
    if sys.argv[1] == "--green":
        write_green_imageset(Path(sys.argv[2]))
    else:
        write_appiconset(Path(sys.argv[1]), sys.argv[2] if len(sys.argv) > 2 else None)
