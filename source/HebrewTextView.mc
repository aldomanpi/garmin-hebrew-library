import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

module HebrewText {

    // Font size constants for use with the :fontSize View option.
    // Apps that provide custom Hebrew fonts at multiple sizes should name them
    // hebrewFontSmall, hebrewFont (medium), and hebrewFontLarge in fonts.xml.
    // See tools/gen_font.py --font-size for generating size variants.
    const FONT_SIZE_SMALL  = 0;
    const FONT_SIZE_MEDIUM = 1;
    const FONT_SIZE_LARGE  = 2;

    // Full-screen scrollable Hebrew text viewer.
    //
    // Constructor options:
    //
    //   :pages         => Array<String>   — each element laid out independently;
    //                                       use for prayer books where some blocks
    //                                       are "|..." section headers and others
    //                                       are multi-paragraph body text.
    //   :text          => String          — single text block (convenience alias
    //                                       for :pages with one element).
    //   :title         => String          — top bar label; omit or pass "" to hide.
    //   :justification => Number          — Graphics.TEXT_JUSTIFY_LEFT / _CENTER /
    //                                       _RIGHT (default: TEXT_JUSTIFY_RIGHT).
    //   :startPosition => :top | :center  — where the first line appears initially.
    //                                       :top    — first line at top (default).
    //                                       :center — first line at vertical centre;
    //                                                 scrolling still reaches the top.
    //   :fontSize      => Number          — HebrewText.FONT_SIZE_SMALL / _MEDIUM /
    //                                       _LARGE (default: FONT_SIZE_MEDIUM).
    //                                       Loads hebrewFontSmall / hebrewFont /
    //                                       hebrewFontLarge from the app's Rez.Fonts;
    //                                       falls back to hebrewFont then system fonts
    //                                       when the size-specific resource is absent.
    //                                       Ignored when :font is also supplied.
    //   :color, :backgroundColor, :font  — as WatchUi.TextArea.  Passing :font
    //                                       overrides :fontSize completely.
    //
    //   WatchUi.pushView(view, new HebrewText.Delegate(view), WatchUi.SLIDE_LEFT);
    //
    // Text block format:
    //   "\n\n"  paragraph break
    //   "\n"    soft break (word-wrapper treats as space)
    //   "|..."  section header (drawn dimmer than body text)
    class View extends WatchUi.View {

        private var mLines        as Array<String>;
        private var mTitle        as String;
        private var mColor        as Graphics.ColorType;
        private var mBgColor      as Graphics.ColorType;
        private var mJustification as Number;
        private var mAllLines     as Array<String> = [] as Array<String>;
        private var mScrollPx     as Number  = 0;
        private var mScrollTarget as Number  = 0;
        private var mScrollTimer  as Timer.Timer? = null;
        private var mDragging     as Boolean = false;
        private var mFirstMove    as Boolean = true;
        private var mPrevDragY    as Number  = 0;
        private var mVelocity     as Float   = 0.0f;
        private var mMomentum     as Boolean = false;
        private var mLayoutDone   as Boolean = false;
        private var mFont         as Graphics.FontDefinition? = null;
        private var mFontH        as Number  = 0;
        private var mDcHeight     as Number  = 0;
        private var mTitleH       as Number  = 0;
        private var mCustomFont   as Graphics.FontDefinition? = null;
        private var mStartCenter  as Boolean = false;
        private var mStartOffset  as Number  = 0;
        private var mFontSize     as Number  = FONT_SIZE_MEDIUM;

        function initialize(options as Lang.Dictionary) {
            View.initialize();

            var v;
            mLines         = [] as Array<String>;
            mTitle         = "";
            mColor         = Graphics.COLOR_WHITE as Graphics.ColorType;
            mBgColor       = Graphics.COLOR_BLACK as Graphics.ColorType;
            mJustification = Graphics.TEXT_JUSTIFY_RIGHT;

            // :pages — Array<String>, each element laid out independently.
            // :text  — String, convenience alias for a single-element :pages.
            v = options.get(:pages);
            if (v != null) {
                mLines = v as Array<String>;
            } else {
                v = options.get(:text);
                if (v != null) { mLines = [v as String]; }
            }

            v = options.get(:title);           if (v != null) { mTitle         = v as String; }
            v = options.get(:color);           if (v != null) { mColor         = v as Graphics.ColorType; }
            v = options.get(:backgroundColor); if (v != null) { mBgColor       = v as Graphics.ColorType; }
            v = options.get(:font);            if (v != null) { mCustomFont    = v as Graphics.FontDefinition; }
            v = options.get(:justification);   if (v != null) { mJustification = v as Number; }
            v = options.get(:startPosition);   if (v != null) { mStartCenter   = v.equals(:center); }
            v = options.get(:fontSize);        if (v != null) { mFontSize      = v as Number; }
        }

        function setText(text as String) as Void {
            mLines      = [text];
            mLayoutDone = false;
            WatchUi.requestUpdate();
        }

        function setColor(color as Graphics.ColorType) as Void {
            mColor = color;
            WatchUi.requestUpdate();
        }

        function setBackgroundColor(color as Graphics.ColorType) as Void {
            mBgColor = color;
            WatchUi.requestUpdate();
        }

        function setJustification(j as Number) as Void {
            mJustification = j;
            WatchUi.requestUpdate();
        }

        function setFont(font as Graphics.FontDefinition) as Void {
            mCustomFont = font;
            mFont       = null;
            mFontH      = 0;
            mLayoutDone = false;
        }

        function setFontSize(size as Number) as Void {
            mFontSize   = size;
            mFont       = null;
            mFontH      = 0;
            mLayoutDone = false;
            WatchUi.requestUpdate();
        }

        function getFontSize() as Number {
            return mFontSize;
        }

        // ── Navigation ───────────────────────────────────────────────────────

        function scrollDown() as Boolean {
            if (mFontH == 0) { return false; }
            var mx = _maxScrollPx();
            if (mScrollTarget < mx) {
                mScrollTarget += mFontH;
                if (mScrollTarget > mx) { mScrollTarget = mx; }
                _startScrollTimer();
                return true;
            }
            return false;
        }

        function scrollUp() as Boolean {
            if (mScrollTarget > 0) {
                mScrollTarget -= mFontH;
                if (mScrollTarget < 0) { mScrollTarget = 0; }
                _startScrollTimer();
                return true;
            }
            return false;
        }

        function isAtEnd()   as Boolean { return mScrollTarget >= _maxScrollPx(); }
        function isAtStart() as Boolean { return mScrollTarget <= 0; }

        private function _startScrollTimer() as Void {
            if (mScrollTimer == null) { mScrollTimer = new Timer.Timer(); }
            (mScrollTimer as Timer.Timer).start(method(:onScrollTick), 16, true);
        }

        public function onScrollTick() as Void {
            if (mMomentum) {
                mVelocity = mVelocity * 0.92f;
                var absV = mVelocity >= 0.0f ? mVelocity : -mVelocity;
                if (absV < 1.0f) {
                    mMomentum = false;
                    mVelocity = 0.0f;
                    (mScrollTimer as Timer.Timer).stop();
                    _snapToLine();
                    return;
                }
                var newScroll = mScrollPx + mVelocity.toNumber();
                var mx = _maxScrollPx();
                if (newScroll <= 0)  { newScroll = 0;  mMomentum = false; }
                if (newScroll >= mx) { newScroll = mx; mMomentum = false; }
                mScrollPx     = newScroll;
                mScrollTarget = newScroll;
                WatchUi.requestUpdate();
                if (!mMomentum) {
                    (mScrollTimer as Timer.Timer).stop();
                    _snapToLine();
                }
            } else {
                var diff    = mScrollTarget - mScrollPx;
                var absDiff = diff < 0 ? -diff : diff;
                if (absDiff <= 5) {
                    mScrollPx = mScrollTarget;
                    (mScrollTimer as Timer.Timer).stop();
                } else {
                    mScrollPx += diff > 0 ? 5 : -5;
                }
                WatchUi.requestUpdate();
            }
        }

        private function _snapToLine() as Void {
            if (mFontH <= 0) { return; }
            var rounded = ((mScrollPx + mFontH / 2) / mFontH) * mFontH;
            var mx = _maxScrollPx();
            if (rounded < 0)  { rounded = 0; }
            if (rounded > mx) { rounded = mx; }
            if (rounded != mScrollPx) { mScrollTarget = rounded; _startScrollTimer(); }
        }

        // ── Touch input ──────────────────────────────────────────────────────

        function touchDown(y as Number) as Void {
            if (mScrollTimer != null) { (mScrollTimer as Timer.Timer).stop(); }
            mMomentum     = false;
            mVelocity     = 0.0f;
            mPrevDragY    = y;
            mFirstMove    = true;
            mDragging     = true;
            mScrollTarget = mScrollPx;
        }

        function touchMove(y as Number) as Void {
            if (!mDragging) { return; }
            if (mFirstMove) { mPrevDragY = y; mFirstMove = false; return; }
            var delta = mPrevDragY - y;
            mPrevDragY = y;
            mVelocity  = delta.toFloat() * 0.6f + mVelocity * 0.4f;
            var newScroll = mScrollPx + delta;
            var mx = _maxScrollPx();
            if (newScroll < 0)  { newScroll = 0; }
            if (newScroll > mx) { newScroll = mx; }
            mScrollPx     = newScroll;
            mScrollTarget = newScroll;
            WatchUi.requestUpdate();
        }

        function touchUp(y as Number) as Void {
            if (!mDragging) { return; }
            mDragging = false;
            if (!mFirstMove) { touchMove(y); }
            _launchMomentumOrSnap();
        }

        function cancelDrag() as Void {
            if (!mDragging) { return; }
            mDragging = false;
            _launchMomentumOrSnap();
        }

        private function _launchMomentumOrSnap() as Void {
            var absV = mVelocity >= 0.0f ? mVelocity : -mVelocity;
            if (absV > 1.5f) { mMomentum = true; _startScrollTimer(); }
            else             { _snapToLine(); }
        }

        // ── Drawing ──────────────────────────────────────────────────────────

        function onUpdate(dc as Graphics.Dc) as Void {
            dc.setColor(mBgColor, mBgColor);
            dc.clear();

            var w = dc.getWidth();
            var h = dc.getHeight();
            mDcHeight = h;

            if (mFont == null) {
                mFont   = _pickFont();
                mFontH  = dc.getFontHeight(mFont) + 2;
                mTitleH = mTitle.length() > 0
                    ? dc.getFontHeight(Graphics.FONT_XTINY) + 6 : 0;
                mStartOffset = mStartCenter ? (h - mTitleH - 4) / 2 : 0;
            }

            if (!mLayoutDone) {
                // layoutLinesReversed returns already-reversed lines so the
                // drawing loop below makes a single native dc.drawText call per
                // visible line — ~10× fewer DC calls/frame than per-character drawing.
                mAllLines = [] as Array<String>;
                for (var p = 0; p < mLines.size(); p++) {
                    if (p > 0) { mAllLines.add(""); }
                    var pl = layoutLinesReversed(dc, mLines[p],
                                        mFont as Graphics.FontDefinition, w);
                    for (var li = 0; li < pl.size(); li++) {
                        mAllLines.add(pl[li]);
                    }
                }
                mLayoutDone = true;
            }

            var x     = _xForJustification(w);
            var yBase = mTitleH + 2 + mStartOffset - mScrollPx;
            var font  = mFont as Graphics.FontDefinition;

            for (var i = 0; i < mAllLines.size(); i++) {
                var y = yBase + i * mFontH;
                if (y + mFontH <= 0) { continue; }
                if (y >= h)          { break; }
                var line = mAllLines[i];
                if (line.length() == 0) { continue; }
                if (line.substring(0, 1).equals("|")) {
                    dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(x, y, font,
                                line.substring(1, line.length()), mJustification);
                } else {
                    dc.setColor(mColor, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(x, y, font, line, mJustification);
                }
            }

            if (mTitleH > 0) {
                dc.setColor(mBgColor, mBgColor);
                dc.fillRectangle(0, 0, w, mTitleH);
                dc.setColor(mColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(w / 2, 2, Graphics.FONT_XTINY, mTitle,
                            Graphics.TEXT_JUSTIFY_CENTER);
            }
        }

        // ── Private helpers ──────────────────────────────────────────────────

        private function _xForJustification(w as Number) as Number {
            if (mJustification == Graphics.TEXT_JUSTIFY_CENTER) { return w / 2; }
            if (mJustification == Graphics.TEXT_JUSTIFY_LEFT)   { return 8; }
            return w - 8;
        }

        private function _maxScrollPx() as Number {
            if (mFontH == 0 || mAllLines.size() == 0 || mDcHeight == 0) { return 0; }
            var textAreaH = mDcHeight - mTitleH - 4;
            var max = mAllLines.size() * mFontH - textAreaH + mStartOffset;
            return max > 0 ? max : 0;
        }

        private function _pickFont() as Graphics.FontDefinition {
            if (mCustomFont != null) { return mCustomFont as Graphics.FontDefinition; }
            var f = null as Graphics.FontDefinition?;
            try {
                if (mFontSize == FONT_SIZE_SMALL) {
                    f = WatchUi.loadResource(Rez.Fonts.hebrewFontSmall) as Graphics.FontDefinition;
                } else if (mFontSize == FONT_SIZE_LARGE) {
                    f = WatchUi.loadResource(Rez.Fonts.hebrewFontLarge) as Graphics.FontDefinition;
                } else {
                    f = WatchUi.loadResource(Rez.Fonts.hebrewFont) as Graphics.FontDefinition;
                }
            } catch (e instanceof Lang.Exception) {
                f = null;
            }
            // Fall back to hebrewFont if size variant failed to load.
            if (f == null && mFontSize != FONT_SIZE_MEDIUM) {
                try {
                    f = WatchUi.loadResource(Rez.Fonts.hebrewFont) as Graphics.FontDefinition;
                } catch (e instanceof Lang.Exception) {
                    f = null;
                }
            }
            // Last resort: system font scaled to match the requested size.
            if (f == null) {
                if (mFontSize == FONT_SIZE_SMALL)      { f = Graphics.FONT_SMALL  as Graphics.FontDefinition; }
                else if (mFontSize == FONT_SIZE_LARGE) { f = Graphics.FONT_LARGE  as Graphics.FontDefinition; }
                else                                   { f = Graphics.FONT_MEDIUM as Graphics.FontDefinition; }
            }
            return f as Graphics.FontDefinition;
        }
    }
}
