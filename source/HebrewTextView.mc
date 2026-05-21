import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

module HebrewText {

    // Smooth-scrolling RTL Hebrew text viewer.
    //
    // Usage:
    //   var view = new HebrewText.View("Title", [puaEncodedText]);
    //   WatchUi.pushView(view, new HebrewText.Delegate(view), WatchUi.SLIDE_LEFT);
    //
    // Strings must be PUA-encoded.  Run tools/gen_font.py on your source
    // files to produce the normalised .mc files and hebrew.fnt / hebrew.png.
    //
    // Text block format:
    //   "\n\n"  paragraph break
    //   "\n"    soft break (word-wrapper treats as space)
    //   "|..."  section header (drawn in COLOR_LT_GRAY)
    class View extends WatchUi.View {

        private var mLines        as Array<String>;
        private var mTitle        as String;
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

        // title: shown in the top bar; pass "" to hide it entirely.
        // lines: array of text blocks, each word-wrapped independently.
        function initialize(title as String, lines as Array<String>) {
            View.initialize();
            mTitle = title;
            mLines = lines;
        }

        // Replace the default hebrewFont resource with a custom FontDefinition.
        // Call before the view is first drawn; triggers a full layout rebuild.
        function setFont(font as Graphics.FontDefinition) as Void {
            mCustomFont = font;
            mFont       = null;
            mFontH      = 0;
            mLayoutDone = false;
        }

        // ── Navigation ───────────────────────────────────────────────────────

        // Scroll one line toward the end. Returns false when already at bottom
        // (caller should then pop the view).
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

        // Scroll one line toward the top. Returns false when already at top.
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

        // 16 ms timer tick — two modes:
        //   momentum: 0.92 friction coast after touch release
        //   button:   linear 5 px/tick snap toward mScrollTarget
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
        //
        // Jump fix: the first onDrag event after touch-down carries the finger
        // already in motion, so we absorb it as the new reference rather than
        // computing a delta — the first visible frame is always incremental.
        //
        // Momentum: velocity is a 60/40 EMA of per-frame deltas.  On release,
        // if speed > 1.5 px/frame the timer coasts with 0.92 friction/tick.

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

        // Call when a BehaviorDelegate swipe event interrupts the drag sequence
        // so momentum fires correctly for fast flicks.
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
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();

            var w = dc.getWidth();
            var h = dc.getHeight();

            mDcHeight = h;

            if (mFont == null) {
                mFont   = _pickFont();
                mFontH  = dc.getFontHeight(mFont) + 2;
                mTitleH = mTitle.length() > 0
                    ? dc.getFontHeight(Graphics.FONT_XTINY) + 6 : 0;
            }

            if (!mLayoutDone) {
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
            }

            var yBase     = mTitleH + 2 - mScrollPx;
            var rightEdge = w - 8;

            for (var i = 0; i < mAllLines.size(); i++) {
                var y = yBase + i * mFontH;
                if (y + mFontH <= 0) { continue; }
                if (y >= h)          { break; }
                var line = mAllLines[i];
                if (line.length() > 0 && line.substring(0, 1).equals("|")) {
                    dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(rightEdge, y, mFont as Graphics.FontDefinition,
                                line.substring(1, line.length()),
                                Graphics.TEXT_JUSTIFY_RIGHT);
                } else {
                    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(rightEdge, y, mFont as Graphics.FontDefinition,
                                line, Graphics.TEXT_JUSTIFY_RIGHT);
                }
            }

            // Redraw title bar on top so scrolled text behind it is masked.
            if (mTitleH > 0) {
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(0, 0, w, mTitleH);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(w / 2, 2, Graphics.FONT_XTINY, mTitle,
                            Graphics.TEXT_JUSTIFY_CENTER);
            }
        }

        // ── Private helpers ──────────────────────────────────────────────────

        private function _maxScrollPx() as Number {
            if (mFontH == 0 || mAllLines.size() == 0 || mDcHeight == 0) { return 0; }
            var textAreaH = mDcHeight - mTitleH - 4;
            var max = mAllLines.size() * mFontH - textAreaH;
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
