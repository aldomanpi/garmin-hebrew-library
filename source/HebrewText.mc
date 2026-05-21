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

    // Draw one line of Hebrew text with automatic RTL reversal.
    //
    // Drop-in replacement for dc.drawText() for PUA-encoded Hebrew strings.
    // Text may contain multiple space-separated words; word order and character
    // order within each word are both reversed so the string renders RTL.
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
        dc.drawText(x, y, font, reverseJoin(strSplit(text, " ")), justification);
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
                var wordW  = dc.getTextWidthInPixels(word, font);
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
    private function _joinWords(words as Array<String>) as String {
        var s = "";
        for (var i = 0; i < words.size(); i++) {
            if (i > 0) { s = s + " "; }
            s = s + words[i];
        }
        return s;
    }
}
