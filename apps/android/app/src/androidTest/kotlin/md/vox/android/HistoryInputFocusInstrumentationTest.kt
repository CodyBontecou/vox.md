package md.vox.android

import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import md.vox.android.ui.VoxTheme
import org.junit.Rule
import org.junit.Test

/** Real pointer + input-connection controls for the live Library focus ANR investigation. */
class HistoryInputFocusInstrumentationTest {
    @get:Rule val compose = createComposeRule()

    @Test fun fingerFocusAcceptsNativeKeyEvents() = checkInput(stylus = false)
    @Test fun stylusFocusAcceptsNativeKeyEvents() = checkInput(stylus = true)

    private fun checkInput(stylus: Boolean) {
        lateinit var root: View
        compose.setContent {
            val view = LocalView.current
            SideEffect { root = view }
            VoxTheme { HistoryScreen(
                items = emptyList(), transcripts = emptyList(), isBusy = false,
                navigateBack = {}, refresh = {}, retry = {}, repairAccess = {},
                openDetail = {}, openTranscript = {}, clearCompleted = {},
            ) }
        }
        val search = compose.onNode(hasSetTextAction() and hasText("Search words, routes, files"))
        injectSearchPointer(search, root, stylus)
        search.assertIsFocused()
        InstrumentationRegistry.getInstrumentation().sendStringSync("qa")
        search.assertTextContains("qa")
    }
}

internal fun injectSearchPointer(search: SemanticsNodeInteraction, root: View, stylus: Boolean) {
    val point = search.fetchSemanticsNode().boundsInRoot.center
    val origin = IntArray(2)
    InstrumentationRegistry.getInstrumentation().runOnMainSync { root.getLocationOnScreen(origin) }
    val properties = MotionEvent.PointerProperties().apply {
        id = 0
        toolType = if (stylus) MotionEvent.TOOL_TYPE_STYLUS else MotionEvent.TOOL_TYPE_FINGER
    }
    val coordinates = MotionEvent.PointerCoords().apply {
        x = point.x + origin[0]; y = point.y + origin[1]
        pressure = 1f; size = 1f
    }
    val source = InputDevice.SOURCE_TOUCHSCREEN or (if (stylus) InputDevice.SOURCE_STYLUS else 0)
    val devices = InputDevice.getDeviceIds().map { InputDevice.getDevice(it) }.filterNotNull()
    val device = devices.firstOrNull {
        it.supportsSource(InputDevice.SOURCE_TOUCHSCREEN) && it.supportsSource(InputDevice.SOURCE_STYLUS)
    } ?: devices.firstOrNull { !stylus && it.supportsSource(InputDevice.SOURCE_TOUCHSCREEN) }
    org.junit.Assume.assumeTrue("The native input control needs a matching physical input device", device != null)
    val deviceID = requireNotNull(device).id
    val instrumentation = InstrumentationRegistry.getInstrumentation()
    val down = SystemClock.uptimeMillis()
    for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
        val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, 1,
            arrayOf(properties), arrayOf(coordinates), 0, 0, 1f, 1f, deviceID, 0, source, 0)
        try { instrumentation.sendPointerSync(event) } finally { event.recycle() }
        if (action == MotionEvent.ACTION_DOWN) SystemClock.sleep(50)
    }
}
