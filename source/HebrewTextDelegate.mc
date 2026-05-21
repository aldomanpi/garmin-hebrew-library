import Toybox.Lang;
import Toybox.WatchUi;

// Input delegate for HebrewTextView.
//
// Works on both button-only watches (UP/DOWN/BACK) and touchscreen watches
// (drag-to-scroll with momentum, swipe detection).
//
// Default behaviour when the user scrolls past the last line or before the
// first: WatchUi.popView(SLIDE_RIGHT).  Override onScrollBoundary() in a
// subclass to change this.
class HebrewTextDelegate extends WatchUi.BehaviorDelegate {

    private var mView as HebrewTextView;

    function initialize(view as HebrewTextView) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    // DOWN button / swipe up → scroll toward end of text.
    function onNextPage() as Boolean {
        mView.cancelDrag();
        if (!mView.scrollDown()) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }

    // UP button / swipe down → scroll toward beginning.
    function onPreviousPage() as Boolean {
        mView.cancelDrag();
        if (!mView.scrollUp()) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    // ENTER / tap — no action in a read-only viewer.
    function onSelect() as Boolean {
        return true;
    }

    // Fast swipes are classified by BehaviorDelegate as a swipe gesture and
    // bypass the onDrag sequence.  Forward to cancelDrag so momentum fires
    // correctly for quick flicks.
    function onSwipe(swipeEvent as WatchUi.SwipeEvent) as Boolean {
        mView.cancelDrag();
        return true;
    }

    // Raw drag events: type 0 = touch-down, 1 = move, 2 = up.
    function onDrag(evt as WatchUi.DragEvent) as Boolean {
        var coords = evt.getCoordinates();
        var y = coords[1];
        var t = evt.getType();
        if (t == 0) {
            mView.touchDown(y);
        } else if (t == 1) {
            mView.touchMove(y);
        } else if (t == 2) {
            mView.touchUp(y);
        }
        return true;
    }
}
