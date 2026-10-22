# アプリアイコン（1024x1024）を作る：玉ボケの背景に、くっきりした人物のシルエット
# 使い方: python scripts/make-icon.py
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT = Path(__file__).resolve().parent.parent / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

# 背景：夕方のような紺〜紫のグラデーション
bg = Image.new("RGB", (SIZE, SIZE))
top, bottom = (28, 30, 70), (120, 60, 110)
draw = ImageDraw.Draw(bg)
for y in range(SIZE):
    t = y / (SIZE - 1)
    draw.line([(0, y), (SIZE, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))

# 玉ボケ：半透明の光の円を重ねてからぼかす
bokeh = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
bd = ImageDraw.Draw(bokeh)
rng = random.Random(7)
colors = [(255, 210, 140), (255, 170, 190), (170, 200, 255), (255, 240, 200)]
for _ in range(26):
    r = rng.randint(50, 130)
    x, y = rng.randint(-40, SIZE + 40), rng.randint(-40, SIZE + 40)
    c = rng.choice(colors)
    bd.ellipse([x - r, y - r, x + r, y + r], fill=c + (rng.randint(70, 140),))
bokeh = bokeh.filter(ImageFilter.GaussianBlur(10))
bg = Image.alpha_composite(bg.convert("RGBA"), bokeh)

# 人物のシルエット（くっきり）
person = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
pd = ImageDraw.Draw(person)
white = (255, 255, 255, 255)
cx = SIZE // 2
pd.ellipse([cx - 135, 250, cx + 135, 520], fill=white)                   # 頭
pd.rounded_rectangle([cx - 270, 580, cx + 270, 1100], radius=240, fill=white)  # 肩と胴
bg = Image.alpha_composite(bg, person)

# フォーカス枠（四隅のかぎ括弧）
fd = ImageDraw.Draw(bg)
m, L, w = 110, 150, 34
for (x, y, dx, dy) in [(m, m, 1, 1), (SIZE - m, m, -1, 1), (m, SIZE - m, 1, -1), (SIZE - m, SIZE - m, -1, -1)]:
    for x2, y2 in [(x + dx * L, y + dy * w), (x + dx * w, y + dy * L)]:
        fd.rectangle([min(x, x2), min(y, y2), max(x, x2), max(y, y2)], fill=(255, 214, 90))

OUT.parent.mkdir(parents=True, exist_ok=True)
bg.convert("RGB").save(OUT)
print(OUT)
