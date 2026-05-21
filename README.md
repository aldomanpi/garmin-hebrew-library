# garmin-hebrew-library

A Garmin ConnectIQ barrel (shareable library) for displaying Hebrew text
on Garmin watches.  Provides smooth-scrolling RTL rendering with full
nikkud (vowel-mark) support, touch drag with momentum, and button
navigation — on any watch from fēnix 6 to vívoactive 6.

## How it works

Garmin's BiDi engine and font system have two problems with Hebrew:

1. **Combining characters (nikkud)** — `drawText` renders each Unicode
   code point at successive cursor positions, so vowel marks appear as
   separate boxes beside their base letters instead of above/below them.
2. **RTL reversal** — Garmin's BiDi engine only fires on real Unicode RTL
   code points.  If you work around problem 1 by pre-composing glyphs,
   the PUA code points used have BiDi class L and are *not* reversed.

**Solution (same approach as watch-siddur):**

- `tools/gen_font.py` scans your Hebrew source text, pre-renders every
  unique (letter + nikkud) combination as a single glyph using
  PIL/FreeType, and maps each combination to a Private Use Area code
  point (U+E000+).  Bare Hebrew consonants are also mapped to PUA so the
  *entire* prayer text consists of PUA code points — BiDi never fires.
- The tool rewrites your `.mc` source files, replacing Hebrew Unicode
  sequences with their PUA counterparts, and outputs `hebrew.fnt` +
  `hebrew.png` (AngelCode BMFont format) which the ConnectIQ compiler
  embeds in your app.
- `HebrewText.View` manually reverses character order within each word
  and word order on each display line before calling `dc.drawText()`,
  which renders strictly LTR — producing correct RTL Hebrew output.

## Repository layout

```
garmin-hebrew-library/
├── manifest.xml                 # Barrel manifest (module="HebrewText")
├── monkey.jungle                # Build config
├── source/
│   ├── HebrewText.mc            # module HebrewText — utility functions
│   ├── HebrewTextView.mc        # module HebrewText — class View
│   └── HebrewTextDelegate.mc   # module HebrewText — class Delegate
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

All font assets are included in the repository — no external files are
needed to build or use the library.

The pre-built `hebrew.fnt` / `hebrew.png` cover **all 27 Hebrew consonants
× every nikkud mark** (835 combining sequences + bare consonant aliases =
991 total glyphs), so most Hebrew text works out of the box.

### 1. PUA-encode your source text

Your `.mc` source files must contain PUA-encoded Hebrew (the output of
`gen_font.py`), not raw Unicode Hebrew.  Run the tool once on your text:

```bash
pip install Pillow   # one-time dependency

python tools/gen_font.py \
    --text-files source/MyPrayer.mc source/OtherText.mc \
    --mc-files   source/MyPrayer.mc source/OtherText.mc
```

`--text-files` — which files to scan for Hebrew combining sequences.  
`--mc-files` — which `.mc` files to rewrite with PUA-encoded strings.

The tool rewrites the listed `.mc` files in-place (replacing Hebrew Unicode
with PUA code points) and, if any new glyph combinations are found,
regenerates `resources/fonts/hebrew.fnt` and `resources/fonts/hebrew.png`.
Keep the original Unicode source in git; commit only the PUA-encoded version.

Optional flags:
```
--font PATH       Path to TTF file (default: resources/fonts/Alef-Garmin.ttf)
--out-dir PATH    Output directory for .fnt/.png (default: resources/fonts)
--font-size N     Glyph render size in pixels (default: 22)
```

## Adding the barrel to your app

### 1. Compile the barrel

Open the barrel project in the ConnectIQ SDK (Eclipse or VS Code plugin)
and build it.  This produces `HebrewText.barrel` and `HebrewText.jungle`
in your SDK output directory.

Alternatively, build from the command line:
```bash
monkeyc -f monkey.jungle -o HebrewText.barrel -y developer_key.der
```

### 2. Declare the dependency in your app's `manifest.xml`

```xml
<iq:application ...>
    ...
    <iq:barrels>
        <iq:depends name="HebrewText" version="1.0.0"/>
    </iq:barrels>
</iq:application>
```

### 3. Reference the barrel in your app's `monkey.jungle`

```
project.manifest = manifest.xml

base.sourcePath   = source
base.resourcePath = resources
base.barrelPath   = $(base.barrelPath);path/to/HebrewText.barrel
```

The `$(base.barrelPath)` expansion preserves any other barrels already
declared (e.g. from the IDE-generated `barrels.jungle`).

## Usage

### Minimal example

```monkey-c
import Toybox.WatchUi;

// Push a scrollable Hebrew text view.
function showPrayer(text as String) as Void {
    var view = new HebrewText.View("Shema", [text]);
    WatchUi.pushView(view, new HebrewText.Delegate(view), WatchUi.SLIDE_LEFT);
}
```

`text` must be PUA-encoded (produced by `gen_font.py`).  See
[Text format](#text-format) below.

### Multiple sections

Pass an array of text blocks; each block is word-wrapped independently
with a blank separator line between them:

```monkey-c
var view = new HebrewText.View("Shacharit", [
    "|שחרית",   // section header (shown in gray)
    firstParagraphText,
    secondParagraphText,
]);
```

(Replace `\uXXXX` with the actual PUA code points output by `gen_font.py`.)

### Custom font

To use a different font instead of the built-in `hebrewFont` resource:

```monkey-c
var view = new HebrewText.View("", [text]);
view.setFont(WatchUi.loadResource(Rez.Fonts.myFont) as Graphics.FontDefinition);
```

### Navigation callbacks

The default `HebrewText.Delegate` pops the view when the user scrolls
past the last line.  Subclass it to override that behaviour:

```monkey-c
class MyDelegate extends HebrewText.Delegate {
    function onNextPage() as Boolean {
        if (mView.isAtEnd()) {
            // custom end-of-text action
            return true;
        }
        return HebrewText.Delegate.onNextPage();
    }
}
```

## Text format

All strings passed to `HebrewText.View` must be PUA-encoded.  In your
original `.mc` source (before running `gen_font.py`) write normal Unicode
Hebrew:

```monkey-c
// BEFORE gen_font.py  (keep this version in git, do not commit generated output)
var text = "שמע ישראל";
```

After running `gen_font.py --mc-files source/MyText.mc` the file is
rewritten with PUA code points that the Garmin font resolves to the
correct composed glyphs.

**Paragraph and line breaks:**

| Sequence | Effect |
|----------|--------|
| `"\n\n"` | Paragraph break — blank line inserted |
| `"\n"` | Soft break — treated as a space by the word-wrapper |
| `"\|..."` | Section header — displayed in `COLOR_LT_GRAY` |

## API reference

### `HebrewText.View`

```monkey-c
function initialize(title as String, lines as Array<String>)
```
Create a new view.  `title` is shown in a top bar (`""` hides it).  
`lines` is an array of text blocks (each PUA-encoded).

```monkey-c
function setFont(font as Graphics.FontDefinition) as Void
```
Override the default `hebrewFont` resource.  Call before first draw.

```monkey-c
function scrollDown() as Boolean   // scroll one line toward end; false = already at end
function scrollUp()   as Boolean   // scroll one line toward top; false = already at top
function isAtEnd()    as Boolean
function isAtStart()  as Boolean
```

Touch input methods (called by `HebrewText.Delegate`):
```monkey-c
function touchDown(y as Number) as Void
function touchMove(y as Number) as Void
function touchUp(y as Number)   as Void
function cancelDrag()           as Void
```

### `HebrewText.Delegate`

```monkey-c
function initialize(view as HebrewText.View)
```

Handles: `onNextPage`, `onPreviousPage`, `onBack`, `onSelect`, `onSwipe`,
`onDrag`.  Works on button-only and touchscreen watches.

### `HebrewText` module functions

```monkey-c
function strSplit(str as String, delim as String) as Array<String>
function reverseStr(word as String) as String
function reverseJoin(words as Array<String>) as String
function layoutLines(dc, text, font, maxWidth) as Array<String>
```

These are available as standalone utilities if you need lower-level
access to the RTL layout engine.

## Supported devices

All devices listed in `manifest.xml`: fēnix 6/7/8, epix, Enduro, MARQ
Gen 2, D2, Instinct 2/3, Forerunner 165–970, Venu, vívoactive 3–6.

Minimum ConnectIQ API: **3.2.0**.

## License

MIT.  The Alef font (`Alef-Garmin.ttf`) is derived from the
[Alef typeface](https://github.com/HassoPlattnerInstitute/Alef) and is
licensed under the SIL Open Font License 1.1.
