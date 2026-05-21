import Toybox.Graphics;
import Toybox.Lang;

// Utility functions for RTL Hebrew text on Garmin watches.
//
// All Hebrew characters in source strings must be Private Use Area (U+E000+)
// code points so Garmin's BiDi engine never fires on them.  Use
// tools/gen_font.py to produce PUA-normalised .mc files and the matching
// hebrew.fnt + hebrew.png sprite sheet.
//
// RTL rendering works by manually reversing character order within each word
// and word order across each display line before passing the string to
// dc.drawText(), which renders strictly left-to-right.
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

    // Reverse characters within one word.
    function reverseStr(word as String) as String {
        var len = word.length();
        var s   = "";
        for (var i = len - 1; i >= 0; i--) {
            s = s + word.substring(i, i + 1);
        }
        return s;
    }

    // Reverse word order on a line AND character order within each word so
    // that a plain LTR drawText call produces correct RTL Hebrew output.
    function reverseJoin(words as Array<String>) as String {
        var s = "";
        for (var i = words.size() - 1; i >= 0; i--) {
            if (s.length() > 0) { s = s + " "; }
            s = s + reverseStr(words[i]);
        }
        return s;
    }

    // Word-wrap one text block into display-ready RTL lines.
    //
    // Format rules:
    //   "\n\n"  paragraph break — blank line inserted between paragraphs
    //   "\n"    soft break      — treated as a space by the word-wrapper
    //   "|..."  section header  — returned as one reversed line, "|" prefix
    //                             kept intact so callers can style it differently
    //
    // Every returned line is already reversed; pass directly to dc.drawText().
    function layoutLines(dc as Graphics.Dc, text as String,
                         font as Graphics.FontDefinition,
                         maxWidth as Number) as Array<String> {
        var usable = maxWidth - 40;
        var result = [] as Array<String>;

        if (text.length() > 0 && text.substring(0, 1).equals("|")) {
            var words = strSplit(text.substring(1, text.length()), " ");
            result.add("|" + reverseJoin(words));
            return result;
        }

        var paragraphs = strSplit(text, "\n\n");
        for (var p = 0; p < paragraphs.size(); p++) {
            if (p > 0) { result.add(""); }

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
                var word  = words[wi];
                if (word.length() == 0) { continue; }
                var wordW  = dc.getTextWidthInPixels(word, font);
                var spaceW = lineWords.size() > 0
                    ? dc.getTextWidthInPixels(" ", font) : 0;

                if (lineWords.size() > 0 && lineWidth + spaceW + wordW > usable) {
                    result.add(reverseJoin(lineWords));
                    lineWords = [word] as Array<String>;
                    lineWidth = wordW;
                } else {
                    lineWords.add(word);
                    lineWidth += spaceW + wordW;
                }
            }
            if (lineWords.size() > 0) {
                result.add(reverseJoin(lineWords));
            }
        }
        return result;
    }
}
