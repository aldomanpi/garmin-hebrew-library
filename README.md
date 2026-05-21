# garmin-hebrew-library

A Garmin ConnectIQ barrel for displaying Hebrew text on Garmin watches.
Handles right-to-left rendering and nikkud (vowel marks) automatically,
with an API that mirrors the native `dc.drawText()` call.

## Quick start

```monkey-c
// Draw a line of Hebrew text — same signature as dc.drawText()
HebrewText.drawText(dc, dc.getWidth() - 8, y,
                    Rez.Fonts.hebrewFont, myText,
                    Graphics.TEXT_JUSTIFY_RIGHT);
```

That's it. Word order and character order are reversed automatically for RTL
display.  For multi-line / word-wrapped text see [Multi-line text](#multi-line-text).

## How it works

Garmin's BiDi engine and font system have two problems with Hebrew:

1. **Combining characters (nikkud)** — `drawText` renders each Unicode code
   point at successive cursor positions, so vowel marks appear as separate
   boxes rather than above or below their base letters.
2. **RTL reversal** — Garmin's BiDi engine only fires on real Unicode RTL
   code points.  Fixing problem 1 requires remapping to Private Use Area
   (PUA) code points, which have BiDi class L and are *not* reversed.

**Solution:**

- `tools/gen_font.py` scans your Hebrew source files, pre-renders every
  unique letter+nikkud combination as a single glyph, and maps each
  combination to a PUA code point (U+E000+).  It rewrites your `.mc` files
  with these PUA strings and outputs `hebrew.fnt` + `hebrew.png`
  (AngelCode BMFont format), which the ConnectIQ compiler embeds as a font.
- `HebrewText.drawText()` reverses character order within each word and
  word order across the line, then calls `dc.drawText()` — producing
  correct RTL output from a strictly LTR rendering engine.

The pre-built font covers **all 27 consonants × every nikkud mark**
(835 combining sequences + bare consonant aliases = 991 total glyphs),
so most Hebrew text works without regenerating the font.

## Repository layout

```
garmin-hebrew-library/
├── manifest.xml                 # Barrel manifest (module="HebrewText")
├── monkey.jungle                # Build config
├── source/
│   ├── HebrewText.mc            # drawText(), layoutLines(), utilities
│   ├── HebrewTextView.mc        # HebrewText.View  — full-page scrollable viewer
│   └── HebrewTextDelegate.mc    # HebrewText.Delegate — input handler for View
├── resources/
│   └── fonts/
│       ├── fonts.xml            # Declares the hebrewFont resource
│       ├── Alef-Garmin.ttf      # Hebrew TrueType font (SIL OFL 1.1)
│       ├── hebrew.fnt           # BMFont descriptor — all consonants × nikkud
│       └── hebrew.png           # Glyph sprite sheet (1024×2048)
└── tools/
    ├── gen_font.py              # Font + PUA-normalisation tool
    └── pua_map.json             # PUA code-point mapping used by gen_font.py
```

## Setup

### 1. PUA-encode your source text

Your `.mc` source files must contain PUA-encoded Hebrew strings (produced by
`gen_font.py`), not raw Unicode Hebrew.  Run the tool once on your source:

```bash
pip install Pillow   # one-time dependency

python tools/gen_font.py \
    --text-files source/MyText.mc \
    --mc-files   source/MyText.mc
```

`--text-files` — files to scan for Hebrew character combinations.  
`--mc-files` — files to rewrite in-place with PUA-encoded strings.

The tool replaces Hebrew Unicode sequences with PUA code points in the
listed files.  Keep the original Unicode source in git; commit only the
PUA-encoded version.

Optional flags:
```
--font PATH       Path to TTF file (default: resources/fonts/Alef-Garmin.ttf)
--out-dir PATH    Output directory for .fnt/.png (default: resources/fonts)
--font-size N     Glyph render size in pixels (default: 22)
```

### 2. Add the barrel to your app

Compile the barrel with the ConnectIQ SDK:
```bash
monkeyc -f monkey.jungle -o HebrewText.barrel -y developer_key.der
```

Declare the dependency in your app's `manifest.xml`:
```xml
<iq:application ...>
    <iq:barrels>
        <iq:depends name="HebrewText" version="1.0.0"/>
    </iq:barrels>
</iq:application>
```

Reference it in your app's `monkey.jungle`:
```
base.barrelPath = $(base.barrelPath);path/to/HebrewText.barrel
```

## Usage

### Drawing a single line

```monkey-c
import Toybox.Graphics;

function onUpdate(dc as Graphics.Dc) as Void {
    var font = WatchUi.loadResource(Rez.Fonts.hebrewFont) as Graphics.FontDefinition;
    var w    = dc.getWidth();

    // Right-aligned (standard for Hebrew)
    HebrewText.drawText(dc, w - 8, 40, font, myText, Graphics.TEXT_JUSTIFY_RIGHT);

    // Centered
    HebrewText.drawText(dc, w / 2, 40, font, myText, Graphics.TEXT_JUSTIFY_CENTER);
}
```

### Multi-line text

Use `layoutLines()` to word-wrap, then draw each line:

```monkey-c
var font   = WatchUi.loadResource(Rez.Fonts.hebrewFont) as Graphics.FontDefinition;
var w      = dc.getWidth();
var lineH  = dc.getFontHeight(font) + 2;
var lines  = HebrewText.layoutLines(dc, myText, font, w);

for (var i = 0; i < lines.size(); i++) {
    HebrewText.drawText(dc, w - 8, 10 + i * lineH, font,
                        lines[i], Graphics.TEXT_JUSTIFY_RIGHT);
}
```

`layoutLines()` returns lines in logical order; `drawText()` applies the
RTL reversal when drawing.  Do **not** pass `layoutLines()` output to
`dc.drawText()` directly — the reversal would be skipped.

### Section headers in multi-line text

Lines starting with `"|"` are section headers.  Strip the prefix and
style them separately:

```monkey-c
for (var i = 0; i < lines.size(); i++) {
    var line = lines[i];
    if (line.length() > 0 && line.substring(0, 1).equals("|")) {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        HebrewText.drawText(dc, w - 8, y, font,
                            line.substring(1, line.length()),
                            Graphics.TEXT_JUSTIFY_RIGHT);
    } else {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        HebrewText.drawText(dc, w - 8, y, font, line, Graphics.TEXT_JUSTIFY_RIGHT);
    }
    y += lineH;
}
```

### Full-page scrollable viewer

For long texts that need touch/button scrolling, use the built-in view:

```monkey-c
var view = new HebrewText.View("Shacharit", [
    "|שחרית",          // section header (gray)
    firstParagraph,
    secondParagraph,
]);
WatchUi.pushView(view, new HebrewText.Delegate(view), WatchUi.SLIDE_LEFT);
```

Pass `""` as the title to hide the title bar.  Each element of the array
is word-wrapped independently with a blank separator line between them.

## Text format

Before running `gen_font.py`, write normal Unicode Hebrew in your source:

```monkey-c
var text = "שְׁמַע יִשְׂרָאֵל";   // normal Unicode with nikkud
```

After `gen_font.py --mc-files source/MyText.mc` the file is rewritten with
PUA code points.  Keep the Unicode version in git; commit only the
PUA-encoded output.

**Special sequences in text strings:**

| Sequence | Effect |
|----------|--------|
| `"\n\n"` | Paragraph break — blank line between paragraphs |
| `"\n"` | Soft break — treated as a space by the word-wrapper |
| `"|..."` | Section header — `layoutLines()` returns it with `"|"` prefix |

## API reference

### `HebrewText.drawText()`

```monkey-c
function drawText(
    dc            as Graphics.Dc,
    x             as Number,
    y             as Number,
    font          as Graphics.FontDefinition,
    text          as String,
    justification as Number
) as Void
```

Draw a PUA-encoded Hebrew string with automatic RTL reversal.
Same signature as `dc.drawText()`.

### `HebrewText.layoutLines()`

```monkey-c
function layoutLines(
    dc       as Graphics.Dc,
    text     as String,
    font     as Graphics.FontDefinition,
    maxWidth as Number
) as Array<String>
```

Word-wrap `text` into lines that fit within `maxWidth`.  Returns lines in
logical order; always draw with `HebrewText.drawText()`, not `dc.drawText()`.

### `HebrewText.View`

```monkey-c
function initialize(title as String, lines as Array<String>)
function setFont(font as Graphics.FontDefinition) as Void
function scrollDown() as Boolean   // false = already at bottom
function scrollUp()   as Boolean   // false = already at top
function isAtEnd()    as Boolean
function isAtStart()  as Boolean
```

### `HebrewText.Delegate`

```monkey-c
function initialize(view as HebrewText.View)
```

Handles `onNextPage`, `onPreviousPage`, `onBack`, `onSelect`, `onSwipe`,
`onDrag`.  Works on button-only and touchscreen watches.  Pops the view
automatically when the user scrolls past the first or last line.

## Supported devices

fēnix 6/7/8, epix, Enduro, MARQ Gen 2, D2, Instinct 2/3,
Forerunner 165–970, Venu, vívoactive 3–6.  Minimum ConnectIQ API: **3.2.0**.

## License

MIT.  The Alef font (`Alef-Garmin.ttf`) is derived from the
[Alef typeface](https://github.com/HassoPlattnerInstitute/Alef) and is
licensed under the SIL Open Font License 1.1.
