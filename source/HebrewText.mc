import Toybox.Graphics;
import Toybox.Lang;

// Utility functions for right-to-left Hebrew text rendering on Garmin watches.
//
// All Hebrew characters in your text must be Private Use Area (U+E000+) code
// points — use tools/gen_font.py to produce a PUA-normalised copy of your
// source files and the matching hebrew.fnt + hebrew.png sprite sheet.
//
// Rendering works by manually reversing both character order within each word
// and word order across each display line before handing the string to
// dc.drawText(), which renders strictly left-to-right.  Because every glyph
// is a PUA code point, Garmin's BiDi engine never fires.
module HebrewText {

    // CIQ 3.2-compatible string split (String.split() is not available in 3.2).
    function strSplit(str as String, delim as String) as Array<String> {
        var result = [] as Array<String>;
        var dlen = delim.length();
        var remaining = str;
        var idx = remaining.find(delim);
        while (idx != null) {
            result.add(remaining.substring(0, idx));
            remaining = remaining.substring(idx + dlen, remaining.length());
            idx = remaining.find(delim);
        }
        result.add(remaining);
        return result;
    }

    // Reverse the characters within a single word.
    function reverseStr(word as String) as String {
        var len = word.length();
        var s = "";
        for (var i = len - 1; i >= 0; i--) {
            s = s + word.substring(i, i + 1);
        }
        return s;
    }

    // Reverse word order on a line AND character order within each word.
    // Passing the result to a LTR drawText call produces correct RTL output.
    function reverseJoin(words as Array<String>) as String {
        var s = "";
        for (var i = words.size() - 1; i >= 0; i--) {
            if (s.length() > 0) { s = s + " "; }
            s = s + reverseStr(words[i]);
        }
        return s;
    }

    // Word-wrap one block of Hebrew text into display-ready RTL lines.
    //
    // Text format:
    //   "\n\n"  paragraph break  — a blank line is inserted between paragraphs
    //   "\n"    soft line break  — treated as a space by the word-wrapper
    //   "|..."  section header  — returned as a single reversed line with
    //                             the "|" prefix intact (draw in a different
    //                             colour to distinguish from body text)
    //
    // Every returned line is already reversed (reverseJoin applied); callers
    // pass the string directly to dc.drawText() for correct RTL rendering.
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

            var words = strSplit(paraText, " ");
            var lineWords = [] as Array<String>;
            var lineWidth = 0;

            for (var wi = 0; wi < words.size(); wi++) {
                var word = words[wi];
                if (word.length() == 0) { continue; }
                var wordW = dc.getTextWidthInPixels(word, font);
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
