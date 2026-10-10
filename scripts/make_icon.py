import sys, os
from PIL import Image, ImageDraw, ImageFilter

out_dir = sys.argv[1]
S = 4096  # draw at 4x of 1024 then downscale
def sc(v): return int(v * S / 1024)

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# soft drop shadow
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([sc(100), sc(118), sc(924), sc(942)], radius=sc(186), fill=(0, 0, 0, 110))
shadow = shadow.filter(ImageFilter.GaussianBlur(sc(18)))
img.alpha_composite(shadow)

# background: vertical gradient inside rounded square
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
top, bot = (52, 57, 70), (17, 19, 25)
for y in range(S):
    t = y / S
    gd.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([sc(100), sc(100), sc(924), sc(924)], radius=sc(186), fill=255)
img.paste(grad, (0, 0), mask)

class Blend:
    """Draw each shape on its own layer and alpha-composite, so translucent fills blend."""
    def rounded_rectangle(self, box, **kw):
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle(box, **kw)
        img.alpha_composite(layer)
d = Blend()
# hairline top highlight
d.rounded_rectangle([sc(100), sc(100), sc(924), sc(924)], radius=sc(186), outline=(255, 255, 255, 22), width=sc(4))

# "touch bar" strip
d.rounded_rectangle([sc(196), sc(668), sc(828), sc(748)], radius=sc(24), fill=(0, 0, 0, 200), outline=(255, 255, 255, 30), width=sc(3))
for i, w in enumerate([90, 60, 120, 70, 110]):
    x0 = 230 + sum([90, 60, 120, 70, 110][:i]) + i * 22
    d.rounded_rectangle([sc(x0), sc(694), sc(x0 + w), sc(722)], radius=sc(8), fill=(255, 255, 255, 34))

# three gauges: track + fill (green / orange / Claude coral)
bars = [
    ((79, 199, 106), 0.42),
    ((247, 160, 62), 0.68),
    ((217, 125, 77), 0.90),
]
bw, gap = 118, 62
total = 3 * bw + 2 * gap
x = (1024 - total) // 2
ytop, ybot = 236, 598
for color, frac in bars:
    d.rounded_rectangle([sc(x), sc(ytop), sc(x + bw), sc(ybot)], radius=sc(bw // 2), fill=color + (60,))
    fill_top = ybot - (ybot - ytop) * frac
    d.rounded_rectangle([sc(x), sc(fill_top), sc(x + bw), sc(ybot)], radius=sc(bw // 2), fill=color + (255,))
    x += bw + gap

base = img.resize((1024, 1024), Image.LANCZOS)
os.makedirs(out_dir, exist_ok=True)
for size in [16, 32, 128, 256, 512]:
    base.resize((size, size), Image.LANCZOS).save(os.path.join(out_dir, f"icon_{size}x{size}.png"))
    base.resize((size * 2, size * 2), Image.LANCZOS).save(os.path.join(out_dir, f"icon_{size}x{size}@2x.png"))
print("done")
