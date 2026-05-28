"""
Generate resources/fonts/hebrew.fnt + hebrew.png from a Hebrew-capable .ttf.

Hebrew rendering strategy
--------------------------
Garmin's drawText renders each Unicode code point as a separate glyph at
successive cursor positions, so combining characters (nikud) appear as
standalone boxes next to base letters rather than overlaid on them.

Fix: every (letter + combining-marks) sequence found in the input text is
rendered as ONE pre-composed glyph by PIL/FreeType, then mapped to a Private
Use Area (PUA) code point (U+E000+).  Your source .mc files use those PUA
code points in string literals; the Garmin font maps them back to the correct
composed glyphs.

RTL rendering
-------------
PUA code points have BiDi class "L" (left-to-right), so Garmin's BiDi engine
would NOT reverse them.  To ensure correct RTL output, all bare Hebrew
consonants are ALSO remapped to PUA.  HebrewText.View then manually reverses
character order within each word and word order on each line.

Usage
-----
    pip install Pillow
    python tools/gen_font.py \\
        --text-files source/MyText.mc source/OtherText.mc \\
        --mc-files   source/MyText.mc source/OtherText.mc

Arguments
---------
--text-files   Files to scan for Hebrew combining sequences (reads quoted
               string literals from .mc files, or plain text from others).
--mc-files     MonkeyC source files to rewrite: Hebrew chars -> PUA codes.
--font         TTF font to use (default: resources/fonts/Alef-Garmin.ttf).
--out-dir      Output directory for hebrew.fnt and hebrew.png
               (default: resources/fonts).
--font-size    Glyph render size in pixels (default: 22).
"""

import argparse, math, os, re, unicodedata
from PIL import Image, ImageFont, ImageDraw


def parse_args():
    p = argparse.ArgumentParser(
        description="Generate Garmin BMFont + PUA-normalised source for Hebrew text"
    )
    p.add_argument("--text-files", nargs="*", default=[],
                   metavar="FILE",
                   help="Files to scan for Hebrew combining sequences")
    p.add_argument("--mc-files", nargs="*", default=[],
                   metavar="FILE",
                   help="MonkeyC source files to normalise (Hebrew -> PUA)")
    p.add_argument("--font", default=None,
                   help="Path to TTF font (default: resources/fonts/Alef-Garmin.ttf)")
    p.add_argument("--out-dir", default=None,
                   help="Output directory (default: resources/fonts)")
    p.add_argument("--font-size", type=int, default=22)
    return p.parse_args()


# ── Constants ─────────────────────────────────────────────────────────────────

ROOT      = os.path.join(os.path.dirname(__file__), "..")
PUA_START = 0xE000

BASE_CHARS = (
    " !\"#$%&'()*+,-./0123456789:;<=>?@"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\\\]^_`"
    "abcdefghijklmnopqrstuvwxyz{|}~"
    "אבגדהוזחטי"
    "כךלמםנןסעפ"
    "ףצץקרשת"
    "־׀׃׳״’"
)

# All 27 Hebrew consonants that get bare-PUA aliases so the full prayer text
# uses only PUA code points and Garmin's BiDi engine never fires.
BARE_HEBREW = (
    "אבגדהוזחטי"
    "כךלמםנןסעפ"
    "ףצץקרשת"
    "׳"
)


# ── Helpers ───────────────────────────────────────────────────────────────────

def is_combining(c):
    return unicodedata.combining(c) > 0


def extract_combining_seqs(text):
    """Return every unique (base_char, *combining_marks) tuple in text."""
    seqs = set()
    i = 0
    while i < len(text):
        ch = text[i]
        if not is_combining(ch):
            seq = [ch]
            j = i + 1
            while j < len(text) and is_combining(text[j]):
                seq.append(text[j])
                j += 1
            if len(seq) > 1:
                seqs.add(tuple(seq))
        i += 1
    return seqs


def read_text_from_file(path):
    """Extract Hebrew text: from quoted string literals in .mc files, or
    plain text otherwise."""
    with open(path, encoding="utf-8") as f:
        src = f.read()
    if path.endswith(".mc"):
        parts = re.findall(r'"((?:[^"\\]|\\.)*)"', src)
        return "\n".join(parts)
    return src


def render_glyph(text, font, padding=3):
    bbox  = font.getbbox(text)
    w     = max(bbox[2] - bbox[0], 1) + padding * 2
    h     = max(bbox[3] - bbox[1], 1) + padding * 2
    img   = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw  = ImageDraw.Draw(img)
    draw.text((-bbox[0] + padding, -bbox[1] + padding),
              text, font=font, fill=(255, 255, 255, 255))
    xoff = -padding
    yoff = bbox[1] - padding
    xadv = int(font.getlength(text)) - 5
    return img, xoff, yoff, xadv


def next_pow2(n):
    p = 1
    while p < n:
        p <<= 1
    return p


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    args = parse_args()

    font_path = args.font or os.path.join(ROOT, "resources", "fonts", "Alef-Garmin.ttf")
    out_dir   = args.out_dir or os.path.join(ROOT, "resources", "fonts")
    out_fnt   = os.path.join(out_dir, "hebrew.fnt")
    out_png   = os.path.join(out_dir, "hebrew.png")

    if not os.path.exists(font_path):
        raise FileNotFoundError(
            f"Font not found: {font_path}\n"
            "Copy Alef-Garmin.ttf from watch-siddur/resources/fonts/ or "
            "supply another Hebrew TTF via --font."
        )

    # Collect all Hebrew text from the input files.
    all_text = ""
    for path in (args.text_files or []):
        all_text += read_text_from_file(path) + "\n"
    if not all_text.strip():
        print("Warning: no --text-files provided; font will cover only base "
              "characters and bare Hebrew consonants (no nikud combinations).")

    # Build PUA map for combining sequences.
    combining_seqs = sorted(extract_combining_seqs(all_text),
                            key=lambda s: (-len(s), s))
    pua_map = {}
    for i, seq in enumerate(combining_seqs):
        pua_map["".join(seq)] = chr(PUA_START + i)

    print(f"  {len(combining_seqs)} combining sequences -> "
          f"PUA U+{PUA_START:04X}...U+{PUA_START + len(combining_seqs) - 1:04X}")

    # Build PUA aliases for bare Hebrew consonants.
    pua_base_start = PUA_START + len(combining_seqs)
    pua_base_map = {}
    for i, ch in enumerate(BARE_HEBREW):
        pua_base_map[ch] = chr(pua_base_start + i)

    print(f"  {len(pua_base_map)} bare-Hebrew chars -> "
          f"PUA U+{pua_base_start:04X}...U+{pua_base_start + len(pua_base_map) - 1:04X}")

    # Assemble full glyph list.
    glyph_list = [(ch, ord(ch)) for ch in BASE_CHARS]
    for seq_str, pua_ch in pua_map.items():
        glyph_list.append((seq_str, ord(pua_ch)))
    for ch, pua_ch in pua_base_map.items():
        glyph_list.append((ch, ord(pua_ch)))
    print(f"  Total glyphs: {len(glyph_list)}")

    # Render sprite sheet.
    pil_font       = ImageFont.truetype(font_path, args.font_size)
    ascent, descent = pil_font.getmetrics()
    line_height    = ascent + descent + 2
    PADDING        = 3
    COLS           = 24
    ROWS           = math.ceil(len(glyph_list) / COLS)
    CELL_W         = args.font_size + PADDING * 4
    CELL_H         = args.font_size + PADDING * 4
    IMG_W          = next_pow2(COLS * CELL_W)
    IMG_H          = next_pow2(ROWS * CELL_H)

    img  = Image.new("RGBA", (IMG_W, IMG_H), (0, 0, 0, 0))
    char_data = []
    for idx, (display_str, code_point) in enumerate(glyph_list):
        col, row = idx % COLS, idx // COLS
        px, py   = col * CELL_W, row * CELL_H
        glyph_img, xoff, yoff, xadv = render_glyph(display_str, pil_font, PADDING)
        img.paste(glyph_img, (px, py), glyph_img)
        gw, gh = glyph_img.size
        char_data.append((code_point, px, py, gw, gh, xoff, yoff, xadv))

    os.makedirs(out_dir, exist_ok=True)
    img.save(out_png)
    print(f"Sprite sheet: {IMG_W}x{IMG_H} -> {out_png}")

    with open(out_fnt, "w", encoding="utf-8") as f:
        f.write(f'info face="AlefGarmin" size={args.font_size} bold=0 italic=0 '
                f'charset="" unicode=1 stretchH=100 smooth=1 aa=1 '
                f'padding={PADDING},{PADDING},{PADDING},{PADDING} spacing=1,1\n')
        f.write(f'common lineHeight={line_height} base={ascent} '
                f'scaleW={IMG_W} scaleH={IMG_H} pages=1 packed=0\n')
        f.write(f'page id=0 file="hebrew.png"\n')
        f.write(f'chars count={len(char_data)}\n')
        for cid, x, y, w, h, xoff, yoff, xadv in char_data:
            f.write(f'char id={cid} x={x} y={y} width={w} height={h} '
                    f'xoffset={xoff} yoffset={yoff} xadvance={xadv} '
                    f'page=0 chnl=15\n')
    print(f"Font descriptor -> {out_fnt}")

    # Normalise .mc source files: replace Hebrew chars with PUA code points.
    def normalise_str(s):
        for seq_str, pua_ch in sorted(pua_map.items(), key=lambda kv: -len(kv[0])):
            s = s.replace(seq_str, pua_ch)
        for ch, pua_ch in pua_base_map.items():
            s = s.replace(ch, pua_ch)
        return s

    def normalise_mc(source):
        result = []
        i = 0
        while i < len(source):
            if source[i] == '"':
                j = i + 1
                while j < len(source):
                    if source[j] == '\\':
                        j += 2; continue
                    if source[j] == '"': break
                    j += 1
                result.append('"' + normalise_str(source[i+1:j]) + '"')
                i = j + 1
            else:
                result.append(source[i])
                i += 1
        return "".join(result)

    header = (
        "// GENERATED FILE - DO NOT EDIT DIRECTLY\n"
        "// Edit your original Hebrew source then re-run:\n"
        "//   python tools/gen_font.py --text-files <src> --mc-files <src>\n"
        "//\n"
        "// Hebrew strings use Private Use Area (U+E000+) code points for\n"
        "// pre-composed letter+nikud glyphs; see tools/gen_font.py.\n\n"
    )
    for path in (args.mc_files or []):
        with open(path, encoding="utf-8") as f:
            src = f.read()
        out = normalise_mc(src)
        with open(path, "w", encoding="utf-8") as f:
            f.write(header + out)
        print(f"Normalised -> {path}")

    print("Done.")


if __name__ == "__main__":
    main()
