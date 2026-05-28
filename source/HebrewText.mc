import Toybox.Graphics;
import Toybox.Lang;

module HebrewText {

    // CIQ 3.2-compatible split (String.split() unavailable before CIQ 4).
    function strSplit(str as String, delim as String) as Array<String> {
        var result = [] as Array<String>;
        var dlen   = delim.length();
        var rem    = str;
        var idx    = rem.find(delim);
        while (idx != null) {
            result.add(rem.substring(0, idx));
            rem = rem.substring(idx + dlen, rem.length());
            idx = rem.find(delim);
        }
        result.add(rem);
        return result;
    }

    // Reverse characters within one word (works on PUA-encoded strings where
    // each code point is a single glyph, including combined letter+nikkud).
    function reverseStr(word as String) as String {
        var len = word.length();
        var s   = "";
        for (var i = len - 1; i >= 0; i--) {
            s = s + word.substring(i, i + 1);
        }
        return s;
    }

    // Reverse word order AND character order within each word so that a
    // left-to-right drawText call produces correct RTL Hebrew output.
    function reverseJoin(words as Array<String>) as String {
        var s = "";
        for (var i = words.size() - 1; i >= 0; i--) {
            if (s.length() > 0) { s = s + " "; }
            s = s + reverseStr(words[i]);
        }
        return s;
    }

    // Per-character advance reduction to prevent Garmin's per-glyph xadvance
    // clipping from cutting off the right edge of each letter.
    const CHAR_SPACING_ADJUST = 3;

    // Draw one line of Hebrew text with automatic RTL reversal.
    //
    // Drop-in replacement for dc.drawText() for PUA-encoded Hebrew strings.
    // Text may contain multiple space-separated words; word order and character
    // order within each word are both reversed so the string renders RTL.
    // Characters are drawn one at a time so each has its own clip window,
    // preventing xadvance-based clipping from cutting the right edge of glyphs.
    //
    // For standard right-aligned Hebrew text:
    //   HebrewText.drawText(dc, dc.getWidth() - 8, y, font, text,
    //                       Graphics.TEXT_JUSTIFY_RIGHT);
    function drawText(
        dc            as Graphics.Dc,
        x             as Number,
        y             as Number,
        font          as Graphics.FontDefinition,
        text          as String,
        justification as Number
    ) as Void {
        var reversed = reverseJoin(strSplit(text, " "));
        var len = reversed.length();
        if (len == 0) { return; }

        // Compute total rendered width using adjusted advances.
        var totalW = 0;
        for (var i = 0; i < len; i++) {
            var ch = reversed.substring(i, i + 1);
            var cw = dc.getTextWidthInPixels(ch, font);
            totalW += ch.equals(" ") ? cw : (cw - CHAR_SPACING_ADJUST);
        }

        var cx;
        if (justification == Graphics.TEXT_JUSTIFY_CENTER) {
            cx = x - totalW / 2;
        } else if (justification == Graphics.TEXT_JUSTIFY_RIGHT) {
            cx = x - totalW;
        } else {
            cx = x;
        }

        for (var i = 0; i < len; i++) {
            var ch = reversed.substring(i, i + 1);
            var cw = dc.getTextWidthInPixels(ch, font);
            dc.drawText(cx, y, font, ch, Graphics.TEXT_JUSTIFY_LEFT);
            cx += ch.equals(" ") ? cw : (cw - CHAR_SPACING_ADJUST);
        }
    }

    // Pre-reverse a logical Hebrew string for LTR display rendering.
    // Call once at layout time and cache the result; pass it to
    // drawTextPreprocessed() to avoid repeating this work every frame.
    function reverseForDisplay(text as String) as String {
        return reverseJoin(strSplit(text, " "));
    }

    // Compute per-character advance widths for a display-ready (pre-reversed) string.
    // Call once at layout time alongside reverseForDisplay(); pass the result to
    // drawTextPreprocessed() so getTextWidthInPixels is never called per-frame.
    function computeLineAdvances(
        dc   as Graphics.Dc,
        text as String,
        font as Graphics.FontDefinition
    ) as Array<Number> {
        var len      = text.length();
        var advances = [] as Array<Number>;
        for (var i = 0; i < len; i++) {
            var ch = text.substring(i, i + 1);
            var cw = dc.getTextWidthInPixels(ch, font);
            advances.add(ch.equals(" ") ? cw : (cw - CHAR_SPACING_ADJUST));
        }
        return advances;
    }

    // Draw a pre-reversed Hebrew line using pre-computed per-character advances.
    // Eliminates string reversal and the double getTextWidthInPixels pass of
    // drawText(). Prepare inputs once with reverseForDisplay() + computeLineAdvances().
    function drawTextPreprocessed(
        dc       as Graphics.Dc,
        x        as Number,
        y        as Number,
        font     as Graphics.FontDefinition,
        reversed as String,
        advances as Array<Number>,
        totalW   as Number,
        justif   as Number
    ) as Void {
        var len = reversed.length();
        if (len == 0) { return; }
        var cx;
        if (justif == Graphics.TEXT_JUSTIFY_CENTER)     { cx = x - totalW / 2; }
        else if (justif == Graphics.TEXT_JUSTIFY_RIGHT) { cx = x - totalW; }
        else                                             { cx = x; }
        for (var i = 0; i < len; i++) {
            dc.drawText(cx, y, font, reversed.substring(i, i + 1), Graphics.TEXT_JUSTIFY_LEFT);
            cx += advances[i];
        }
    }

    // Word-wrap one text block into lines sized to fit maxWidth.
    //
    // Returns an Array<String> of lines in logical order (not yet reversed).
    // Always draw the returned lines with HebrewText.drawText(), not dc.drawText(),
    // so the RTL reversal is applied at draw time.
    //
    // Format rules:
    //   "\n\n"  paragraph break — blank line inserted between paragraphs
    //   "\n"    soft break      — treated as a space by the word-wrapper
    //   "|..."  section header  — returned as-is with the "|" prefix; strip "|"
    //                             before passing the text body to drawText()
    function layoutLines(
        dc       as Graphics.Dc,
        text     as String,
        font     as Graphics.FontDefinition,
        maxWidth as Number
    ) as Array<String> {
        var usable = maxWidth - 40;
        var result = [] as Array<String>;

        // Section header: one line, no word-wrap, "|" prefix kept for styling.
        if (text.length() > 0 && text.substring(0, 1).equals("|")) {
            result.add(text);
            return result;
        }

        var paragraphs = strSplit(text, "\n\n");
        for (var p = 0; p < paragraphs.size(); p++) {
            if (p > 0) { result.add(""); }

            // Flatten soft breaks into spaces.
            var srcLines = strSplit(paragraphs[p], "\n");
            var paraText = "";
            for (var sl = 0; sl < srcLines.size(); sl++) {
                if (sl > 0 && srcLines[sl].length() > 0) { paraText = paraText + " "; }
                paraText = paraText + srcLines[sl];
            }

            var words     = strSplit(paraText, " ");
            var lineWords = [] as Array<String>;
            var lineWidth = 0;

            for (var wi = 0; wi < words.size(); wi++) {
                var word = words[wi];
                if (word.length() == 0) { continue; }
                var wordW  = dc.getTextWidthInPixels(word, font)
                           - CHAR_SPACING_ADJUST * word.length();
                var spaceW = lineWords.size() > 0
                    ? dc.getTextWidthInPixels(" ", font) : 0;

                if (lineWords.size() > 0 && lineWidth + spaceW + wordW > usable) {
                    result.add(_joinWords(lineWords));
                    lineWords = [word] as Array<String>;
                    lineWidth = wordW;
                } else {
                    lineWords.add(word);
                    lineWidth += spaceW + wordW;
                }
            }
            if (lineWords.size() > 0) {
                result.add(_joinWords(lineWords));
            }
        }
        return result;
    }

    // Join words into a space-separated string in logical (forward) order.
    function _joinWords(words as Array<String>) as String {
        var s = "";
        for (var i = 0; i < words.size(); i++) {
            if (i > 0) { s = s + " "; }
            s = s + words[i];
        }
        return s;
    }
}
