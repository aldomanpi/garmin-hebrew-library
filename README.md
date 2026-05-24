# garmin-hebrew-library

A Garmin ConnectIQ barrel for displaying Hebrew text on Garmin watches.
Handles right-to-left rendering and nikkud (vowel marks) automatically,
with an API that mirrors the native `dc.drawText()` call.

## Quick start

**Single line** — mirrors `dc.drawText()`:
```monkey-c
HebrewText.drawText(dc, dc.getWidth() - 8, y,
                    Rez.Fonts.hebrewFont, myText,
                    Graphics.TEXT_JUSTIFY_RIGHT);
```

**Word-wrapped area** — mirrors `WatchUi.TextArea`:
```monkey-c
var area = new HebrewText.TextArea({
    :text   => myText,
    :color  => Graphics.COLOR_WHITE,
    :font   => Rez.Fonts.hebrewFont,
    :locX   => 10,  :locY    => 40,
    :width  => 220, :height  => 180,
});
area.draw(dc);
```

Both handle RTL reversal and nikkud automatically.

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

### Single line — `HebrewText.drawText()`

Mirrors `dc.drawText()` exactly.  Use anywhere you'd normally call `dc.drawText()`:

```monkey-c
function onUpdate(dc as Graphics.Dc) as Void {
    var font = WatchUi.loadResource(Rez.Fonts.hebrewFont) as Graphics.FontDefinition;
    HebrewText.drawText(dc, dc.getWidth() - 8, 40, font,
                        myText, Graphics.TEXT_JUSTIFY_RIGHT);
}
```

### Word-wrapped area — `HebrewText.TextArea`

Mirrors `WatchUi.TextArea`.  Drop it into any existing `onUpdate()` the same way:

```monkey-c
// Create once (e.g. in initialize() or onLayout())
mArea = new HebrewText.TextArea({
    :text          => myText,
    :color         => Graphics.COLOR_WHITE,
    :font          => Rez.Fonts.hebrewFont,
    :justification => Graphics.TEXT_JUSTIFY_RIGHT,
    :locX          => 10,
    :locY          => 40,
    :width         => dc.getWidth() - 20,
    :height        => dc.getHeight() - 50,
});

// In onUpdate():
mArea.draw(dc);
```

Update content at any time with the same setters as `WatchUi.TextArea`:
```monkey-c
mArea.setText(newText);
mArea.setColor(Graphics.COLOR_YELLOW);
mArea.setFont(Rez.Fonts.hebrewFont);
mArea.setJustification(Graphics.TEXT_JUSTIFY_CENTER);
mArea.setBackgroundColor(Graphics.COLOR_DK_GRAY);
```

### Full-page scrollable viewer — `HebrewText.View`

For long texts that need touch/button scrolling (no built-in Garmin equivalent).
Same options as `TextArea`, plus `:title` for an optional top bar:

```monkey-c
var view = new HebrewText.View({
    :text          => myText,
    :title         => "Shacharit",
    :color         => Graphics.COLOR_WHITE,
    :font          => Rez.Fonts.hebrewFont,
    :justification => Graphics.TEXT_JUSTIFY_RIGHT,
});
WatchUi.pushView(view, new HebrewText.Delegate(view), WatchUi.SLIDE_LEFT);
```

Omit `:title` (or pass `""`) to hide the title bar.  All the same setters
work at runtime: `setText()`, `setColor()`, `setBackgroundColor()`,
`setFont()`, `setJustification()`.

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

### `HebrewText.drawText()` — mirrors `dc.drawText()`

```monkey-c
function drawText(dc, x, y, font, text, justification) as Void
```

### `HebrewText.TextArea` — mirrors `WatchUi.TextArea`

```monkey-c
function initialize(options as {
    :text          as String,
    :color         as Graphics.ColorType,         // default COLOR_WHITE
    :backgroundColor as Graphics.ColorType,        // default COLOR_TRANSPARENT
    :font          as Graphics.FontDefinition,    // default FONT_MEDIUM
    :justification as Number,                     // default TEXT_JUSTIFY_RIGHT
    :locX          as Numeric,                    // default 0
    :locY          as Numeric,                    // default 0
    :width         as Numeric,                    // default dc.getWidth() - locX
    :height        as Numeric,                    // default unconstrained
    :visible       as Boolean,                    // default true
})
function draw(dc as Graphics.Dc) as Void
function setText(text as String) as Void
function setColor(color as Graphics.ColorType) as Void
function setBackgroundColor(color as Graphics.ColorType) as Void
function setFont(font as Graphics.FontDefinition) as Void
function setJustification(j as Number) as Void
```

### `HebrewText.View` — full-page scrollable viewer

```monkey-c
function initialize(options as {
    :text          as String,
    :title         as String,                     // top bar label (omit to hide)
    :color         as Graphics.ColorType,         // default COLOR_WHITE
    :backgroundColor as Graphics.ColorType,        // default COLOR_BLACK
    :font          as Graphics.FontDefinition,    // default hebrewFont resource
    :justification as Number,                     // default TEXT_JUSTIFY_RIGHT
})
function draw(dc as Graphics.Dc) as Void         // called automatically by the framework
function setText(text as String) as Void
function setColor(color as Graphics.ColorType) as Void
function setBackgroundColor(color as Graphics.ColorType) as Void
function setFont(font as Graphics.FontDefinition) as Void
function setJustification(j as Number) as Void
function scrollDown() as Boolean                 // false = already at bottom
function scrollUp()   as Boolean                 // false = already at top
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

### `HebrewText.layoutLines()` — low-level word-wrap

```monkey-c
function layoutLines(dc, text, font, maxWidth) as Array<String>
```

Returns lines in logical order.  Always draw the results with
`HebrewText.drawText()`, not `dc.drawText()` — the RTL reversal is applied
at draw time.

## Supported devices

fēnix 6/7/8, epix, Enduro, MARQ Gen 2, D2, Instinct 2/3,
Forerunner 165–970, Venu, vívoactive 3–6.  Minimum ConnectIQ API: **3.2.0**.

## License

MIT.  The Alef font (`Alef-Garmin.ttf`) is derived from the
[Alef typeface](https://github.com/HassoPlattnerInstitute/Alef) and is
licensed under the SIL Open Font License 1.1.
