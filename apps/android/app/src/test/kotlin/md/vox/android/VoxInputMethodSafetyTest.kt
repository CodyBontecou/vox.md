package md.vox.android

import android.text.InputType
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoxInputMethodSafetyTest {
    @Test
    fun blocksAllPasswordEditorVariations() {
        assertTrue(isSensitiveEditorInput(InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD))
        assertTrue(isSensitiveEditorInput(InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD))
        assertTrue(isSensitiveEditorInput(InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD))
        assertTrue(isSensitiveEditorInput(InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD))
    }

    @Test
    fun permitsOrdinaryTextAndNumberEditors() {
        assertFalse(isSensitiveEditorInput(InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_NORMAL))
        assertFalse(isSensitiveEditorInput(InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS))
        assertFalse(isSensitiveEditorInput(InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_NORMAL))
        assertFalse(isSensitiveEditorInput(InputType.TYPE_NULL))
    }
}
