import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

module HebrewText {

    // Drop-in replacement for WatchUi.TextArea with RTL Hebrew support.
    //
    // Usage is identical to WatchUi.TextArea:
    //
    //   var area = new HebrewText.TextArea({
    //       :text          => myPuaText,
    //       :color         => Graphics.COLOR_WHITE,
    //       :font          => Rez.Fonts.hebrewFont,
    //       :justification => Graphics.TEXT_JUSTIFY_RIGHT,
    //       :locX => 10, :locY => 50, :width => 200, :height => 150,
    //   });
    //   area.draw(dc);
    //
    // Text must be PUA-encoded (run tools/gen_font.py on your source files).
    // Default justification is TEXT_JUSTIFY_RIGHT (suits Hebrew; WatchUi.TextArea
    // defaults to TEXT_JUSTIFY_LEFT).
    class TextArea {

        private var mText          as String;
        private var mColor         as Graphics.ColorType;
        private var mBgColor       as Graphics.ColorType;
        private var mFont          as Graphics.FontDefinition?;
        private var mJustification as Number;
        private var mLocX          as Number;
        private var mLocY          as Number;
        private var mWidth         as Number?;
        private var mHeight        as Number?;
        private var mVisible       as Boolean;

        function initialize(options as Lang.Dictionary) {
            var v;
            mText          = "";
            mColor         = Graphics.COLOR_WHITE as Graphics.ColorType;
            mBgColor       = Graphics.COLOR_TRANSPARENT as Graphics.ColorType;
            mFont          = null;
            mJustification = Graphics.TEXT_JUSTIFY_RIGHT;
            mLocX          = 0;
            mLocY          = 0;
            mWidth         = null;
            mHeight        = null;
            mVisible       = true;

            v = options.get(:text);            if (v != null) { mText          = v as String; }
            v = options.get(:color);           if (v != null) { mColor         = v as Graphics.ColorType; }
            v = options.get(:backgroundColor); if (v != null) { mBgColor       = v as Graphics.ColorType; }
            v = options.get(:font);            if (v != null) { mFont          = v as Graphics.FontDefinition; }
            v = options.get(:justification);   if (v != null) { mJustification = v as Number; }
            v = options.get(:locX);            if (v != null) { mLocX          = (v as Lang.Numeric).toNumber(); }
            v = options.get(:locY);            if (v != null) { mLocY          = (v as Lang.Numeric).toNumber(); }
            v = options.get(:width);           if (v != null) { mWidth         = (v as Lang.Numeric).toNumber(); }
            v = options.get(:height);          if (v != null) { mHeight        = (v as Lang.Numeric).toNumber(); }
            v = options.get(:visible);         if (v != null) { mVisible       = v as Boolean; }
        }

        function setText(text as String)                    as Void { mText          = text;  }
        function setColor(color as Graphics.ColorType)      as Void { mColor         = color; }
        function setBackgroundColor(c as Graphics.ColorType) as Void { mBgColor      = c;     }
        function setFont(font as Graphics.FontDefinition)   as Void { mFont          = font;  }
        function setJustification(j as Number)              as Void { mJustification = j;     }

        // Render the text area into dc.  Call from your View's onUpdate().
        function draw(dc as Graphics.Dc) as Void {
            if (!mVisible) { return; }

            var font  = mFont != null ? mFont as Graphics.FontDefinition
                                      : Graphics.FONT_MEDIUM as Graphics.FontDefinition;
            var width = mWidth != null ? mWidth as Number : dc.getWidth() - mLocX;

            if (mBgColor != (Graphics.COLOR_TRANSPARENT as Graphics.ColorType)) {
                dc.setColor(mBgColor, mBgColor);
                dc.fillRectangle(mLocX, mLocY, width,
                                 mHeight != null ? mHeight as Number
                                                 : dc.getHeight() - mLocY);
            }

            var x;
            if (mJustification == Graphics.TEXT_JUSTIFY_CENTER) {
                x = mLocX + width / 2;
            } else if (mJustification == Graphics.TEXT_JUSTIFY_LEFT) {
                x = mLocX + 4;
            } else {
                x = mLocX + width - 4;
            }

            var lineH = dc.getFontHeight(font) + 2;
            var lines = layoutLines(dc, mText, font, width);
            var maxY  = mLocY + (mHeight != null ? mHeight as Number : dc.getHeight());

            dc.setColor(mColor, Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < lines.size(); i++) {
                var y = mLocY + i * lineH;
                if (y + lineH > maxY) { break; }
                var line = lines[i];
                if (line.length() > 0 && line.substring(0, 1).equals("|")) {
                    drawText(dc, x, y, font,
                             line.substring(1, line.length()), mJustification);
                } else {
                    drawText(dc, x, y, font, line, mJustification);
                }
            }
        }
    }
}
