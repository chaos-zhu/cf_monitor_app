"""Compose the four actual Flutter captures into the README's promotional PNG.

Requires Pillow. Fonts are read from the local Flutter SDK, not redistributed.
"""
from pathlib import Path
import argparse
import os
import shutil
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--font-dir", type=Path, help="Flutter bin/cache/artifacts/material_fonts")
args = parser.parse_args()
flutter = shutil.which("flutter")
sdk = os.environ.get("FLUTTER_ROOT")
font_dir = args.font_dir or (
    Path(sdk) / "bin/cache/artifacts/material_fonts" if sdk else
    Path(flutter).resolve().parents[1] / "bin/cache/artifacts/material_fonts" if flutter else None
)
if font_dir is None or not (font_dir / "Roboto-Regular.ttf").is_file():
    parser.error("Pass --font-dir pointing to Flutter's material_fonts directory.")


def font(size, bold=False):
    return ImageFont.truetype(str(font_dir / f"Roboto-{'Bold' if bold else 'Regular'}.ttf"), size)


WIDTH, HEIGHT = 2400, 1680
canvas = Image.new("RGB", (WIDTH, HEIGHT))
draw = ImageDraw.Draw(canvas)
for y in range(HEIGHT):
    t = y / HEIGHT
    draw.line((0, y, WIDTH, y), fill=(int(34 - t * 14), int(28 - t * 8), int(25 - t * 7)))

# A restrained gold glow ties the layout to the mobile brand.
glow = Image.new("RGBA", canvas.size)
ImageDraw.Draw(glow).ellipse((1350, -650, 2800, 750), fill=(243, 128, 32, 32))
glow = glow.filter(ImageFilter.GaussianBlur(180))
canvas = Image.alpha_composite(canvas.convert("RGBA"), glow)
draw = ImageDraw.Draw(canvas)

logo = Image.open(ROOT / "assets/branding/logo.png").convert("RGBA").resize((104, 104), Image.Resampling.LANCZOS)
mask = Image.new("L", logo.size)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, 103, 103), radius=25, fill=255)
canvas.paste(logo, (100, 75), mask)
draw.text((230, 80), "CF Monitor", font=font(46, True), fill="#ffffff")
draw.text((232, 141), "FLUTTER  /  iOS + ANDROID", font=font(22), fill="#c4b6a9")
draw.rounded_rectangle((1900, 95, 2300, 157), radius=31, outline="#806349", width=2)
text = "OPEN SOURCE  /  MIT"
draw.text((2100, 127), text, font=font(22, True), fill="#ffc879", anchor="mm")

draw.text((100, 217), "Your servers. Always in view.", font=font(88, True), fill="#fff8f0")
draw.text((104, 325), "Multiple sites. Live metrics. A clearer view of your infrastructure.",
          font=font(31), fill="#baaea2")

screens = [
    ("01-sites", "01", "All your sites", "Separate connections. One app."),
    ("02-dashboard", "02", "Your fleet, live", "Status and resources at a glance."),
    ("03-resources", "03", "Explore every trend", "Resource history you can inspect."),
    ("04-network", "04", "Know your network", "Latency and packet loss over time."),
]
phone_width, screen_width, top = 502, 478, 520
screen_height = round(screen_width * 844 / 390)
phone_height = screen_height + 24
for i, (name, number, title, subtitle) in enumerate(screens):
    x = 100 + i * 566
    draw.text((x, 425), number, font=font(25, True), fill="#faae40")
    draw.text((x + 54, 420), title, font=font(33, True), fill="#fff8f0")
    draw.text((x, 471), subtitle, font=font(22), fill="#b4a79c")
    shadow = Image.new("RGBA", canvas.size)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x - 8, top + 16, x + phone_width + 8, top + phone_height + 18),
        radius=53, fill=(0, 0, 0, 130))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(20)))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((x, top, x + phone_width, top + phone_height),
                           radius=49, fill="#171717", outline="#5f544c", width=2)
    screenshot = Image.open(ROOT / f"docs/images/screenshots/{name}.png").convert("RGBA")
    if screenshot.size != (1170, 2532):
        raise ValueError(f"Unexpected screenshot dimensions for {name}: {screenshot.size}")
    screenshot = screenshot.resize((screen_width, screen_height), Image.Resampling.LANCZOS)
    screen_mask = Image.new("L", screenshot.size)
    ImageDraw.Draw(screen_mask).rounded_rectangle((0, 0, screen_width - 1, screen_height - 1), radius=37, fill=255)
    canvas.paste(screenshot, (x + 12, top + 12), screen_mask)

draw = ImageDraw.Draw(canvas)
draw.line((100, 1615, 2300, 1615), fill="#4b3c31", width=1)
draw.text((100, 1642), "CF MONITOR  /  MOBILE", font=font(20, True), fill="#faae40")
draw.text((2300, 1642), "Flutter UI captures · Demo data · Light & dark", font=font(20), fill="#aa9d91", anchor="ra")
target = ROOT / "docs/images/showcase.png"
canvas.convert("RGB").save(target, optimize=True)
print(f"Saved {target} ({WIDTH} × {HEIGHT})")
