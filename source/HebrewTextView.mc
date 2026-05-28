import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

module HebrewText {

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
    //   :color, :backgroundColor, :font  — as WatchUi.TextArea.
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

        // Render cache: built once after layout, invalidated on text/font change.
        // Stores pre-reversed strings, per-line widths, and header flags so
        // onUpdate never rebuilds strings or runs the totalW width pass per frame.
        // Per-character advances are NOT cached to keep memory usage bounded on
        // devices with small heaps (e.g. Fenix 6 / FR245 at ~64 KB app heap).
        private var mRenderCacheBuilt as Boolean        = false;
        private var mAllLinesReversed as Array<String>  = [] as Array<String>;
        private var mAllLineWidths    as Array<Number>  = [] as Array<Number>;
        private var mLineIsHeader     as Array<Boolean> = [] as Array<Boolean>;

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
        }

        function setText(text as String) as Void {
            mLines            = [text];
            mLayoutDone       = false;
            mRenderCacheBuilt = false;
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
            mCustomFont       = font;
            mFont             = null;
            mFontH            = 0;
            mLayoutDone       = false;
            mRenderCacheBuilt = false;
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
            System.println("HTV onUpdate start");
            dc.setColor(mBgColor, mBgColor);
            dc.clear();

            var w = dc.getWidth();
            var h = dc.getHeight();
            mDcHeight = h;

            if (mFont == null) {
                System.println("HTV pickFont");
                mFont   = _pickFont();
                mFontH  = dc.getFontHeight(mFont) + 2;
                mTitleH = mTitle.length() > 0
                    ? dc.getFontHeight(Graphics.FONT_XTINY) + 6 : 0;
                mStartOffset = mStartCenter ? (h - mTitleH - 4) / 2 : 0;
                System.println("HTV font ok fontH=" + mFontH);
            }

            if (!mLayoutDone) {
                System.println("HTV layout pages=" + mLines.size());
                mAllLines = [] as Array<String>;
                for (var p = 0; p < mLines.size(); p++) {
                    if (p > 0) { mAllLines.add(""); }
                    var pl = layoutLines(dc, mLines[p],
                                        mFont as Graphics.FontDefinition, w);
                    for (var li = 0; li < pl.size(); li++) {
                        mAllLines.add(pl[li]);
                    }
                }
                mLayoutDone = true;
                System.println("HTV layout done lines=" + mAllLines.size());
            }

            if (!mRenderCacheBuilt) {
                System.println("HTV buildCache start lines=" + mAllLines.size());
                _buildRenderCache(dc);
                System.println("HTV buildCache done");
            }

            var x     = _xForJustification(w);
            var yBase = mTitleH + 2 + mStartOffset - mScrollPx;

            for (var i = 0; i < mAllLines.size(); i++) {
                var y = yBase + i * mFontH;
                if (y + mFontH <= 0) { continue; }
                if (y >= h)          { break; }
                var rev = mAllLinesReversed[i];
                if (rev.length() == 0) { continue; }
                if (mLineIsHeader[i]) {
                    dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                } else {
                    dc.setColor(mColor, Graphics.COLOR_TRANSPARENT);
                }
                _drawLine(dc, x, y, mFont as Graphics.FontDefinition,
                          rev, mAllLineWidths[i] as Number);
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

        private function _buildRenderCache(dc as Graphics.Dc) as Void {
            mAllLinesReversed = [] as Array<String>;
            mAllLineWidths    = [] as Array<Number>;
            mLineIsHeader     = [] as Array<Boolean>;

            var font = mFont as Graphics.FontDefinition;
            for (var i = 0; i < mAllLines.size(); i++) {
                System.println("HTV cache i=" + i);
                var line = mAllLines[i];
                if (line.length() == 0) {
                    mAllLinesReversed.add("");
                    mAllLineWidths.add(0);
                    mLineIsHeader.add(false);
                } else {
                    var isHdr  = line.substring(0, 1).equals("|");
                    var text   = isHdr ? line.substring(1, line.length()) : line;
                    System.println("HTV cache rev i=" + i + " len=" + text.length());
                    var rev    = reverseForDisplay(text);
                    var revLen = rev.length();
                    var w      = 0;
                    for (var j = 0; j < revLen; j++) {
                        var ch = rev.substring(j, j + 1);
                        var cw = dc.getTextWidthInPixels(ch, font);
                        w += ch.equals(" ") ? cw : (cw - CHAR_SPACING_ADJUST);
                    }
                    System.println("HTV cache w=" + w);
                    mAllLinesReversed.add(rev);
                    mAllLineWidths.add(w);
                    mLineIsHeader.add(isHdr);
                }
            }
            mRenderCacheBuilt = true;
        }

        // Draw a pre-reversed line using a pre-computed total width.
        // Avoids string reversal and the totalW measurement pass per frame;
        // still calls getTextWidthInPixels per character to advance cx.
        private function _drawLine(
            dc     as Graphics.Dc,
            x      as Number,
            y      as Number,
            font   as Graphics.FontDefinition,
            rev    as String,
            totalW as Number
        ) as Void {
            var len = rev.length();
            if (len == 0) { return; }
            var cx = x;
            if (mJustification == Graphics.TEXT_JUSTIFY_CENTER)     { cx = x - totalW / 2; }
            else if (mJustification == Graphics.TEXT_JUSTIFY_RIGHT) { cx = x - totalW; }
            for (var i = 0; i < len; i++) {
                var ch = rev.substring(i, i + 1);
                var cw = dc.getTextWidthInPixels(ch, font);
                dc.drawText(cx, y, font, ch, Graphics.TEXT_JUSTIFY_LEFT);
                cx += ch.equals(" ") ? cw : (cw - CHAR_SPACING_ADJUST);
            }
        }

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
                f = WatchUi.loadResource(Rez.Fonts.hebrewFont) as Graphics.FontDefinition;
            } catch (e instanceof Lang.Exception) {
                f = null;
            }
            if (f == null) { f = Graphics.FONT_MEDIUM as Graphics.FontDefinition; }
            return f as Graphics.FontDefinition;
        }
    }
}
