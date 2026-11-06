package md.vox.android

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import md.vox.android.ui.GeistFontFamily
import md.vox.android.ui.VoxColors
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Locale

@RunWith(AndroidJUnit4::class)
class VisualAccessibilityInstrumentationTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun everyMaterialTypographyRoleUsesTheSharedGeistFamily() {
        var usesGeist = false
        compose.setContent {
            VoxTheme(darkTheme = false) {
                val typography = MaterialTheme.typography
                SideEffect {
                    usesGeist = listOf(
                        typography.displayLarge,
                        typography.displayMedium,
                        typography.displaySmall,
                        typography.headlineLarge,
                        typography.headlineMedium,
                        typography.headlineSmall,
                        typography.titleLarge,
                        typography.titleMedium,
                        typography.titleSmall,
                        typography.bodyLarge,
                        typography.bodyMedium,
                        typography.bodySmall,
                        typography.labelLarge,
                        typography.labelMedium,
                        typography.labelSmall,
                    ).all { it.fontFamily == GeistFontFamily }
                }
            }
        }
        compose.runOnIdle { assertTrue(usesGeist) }
    }

    @Test
    fun onboardingSupportsDarkRtlAndTwoHundredPercentTextWithoutLosingItsAction() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val deviceDensity = context.resources.displayMetrics.density
        val baseConfiguration = context.resources.configuration
        var dark by mutableStateOf(false)
        var fontScale by mutableStateOf(1f)
        var direction by mutableStateOf(LayoutDirection.Ltr)
        var locale by mutableStateOf(Locale.ENGLISH)
        var renderedBackground = VoxColors.BackgroundLight
        var folderLaunches = 0
        var started: Set<StarterRoute>? = null
        compose.setContent {
            val configuration = Configuration(baseConfiguration).apply {
                setLocales(LocaleList(locale))
                this.fontScale = fontScale
            }
            CompositionLocalProvider(
                LocalConfiguration provides configuration,
                LocalDensity provides Density(deviceDensity, fontScale),
                LocalLayoutDirection provides direction,
            ) {
                VoxTheme(darkTheme = dark) {
                    val background = MaterialTheme.colorScheme.background
                    SideEffect { renderedBackground = background }
                    FirstRunFlow(
                        destination = null,
                        notice = null,
                        isBusy = false,
                        onChooseFolder = { folderLaunches += 1 },
                        onStartCapturing = { started = it },
                    )
                }
            }
        }

        val getStarted = compose.onNode(hasText("Get started") and hasClickAction())
        getStarted.assertIsDisplayed().assertHasClickAction()
        assertTrue(getStarted.fetchSemanticsNode().boundsInRoot.height / deviceDensity >= 48f)
        compose.runOnIdle { assertEquals(VoxColors.BackgroundLight, renderedBackground) }
        getStarted.performClick()

        // Setup: Journal starts off; toggling it is a whole-row checkbox.
        compose.onNodeWithTag("onboarding.starter.journal").performScrollTo().assertIsOff().performClick().assertIsOn()

        compose.runOnIdle {
            dark = true
            fontScale = 2f
            direction = LayoutDirection.Rtl
            locale = Locale.forLanguageTag("ar")
        }
        compose.waitForIdle()
        compose.onNodeWithText("ابدأ بهذه المسارات").performScrollTo().assertIsDisplayed()
        // Without a folder, Start capturing opens the folder picker instead of finishing.
        compose.onNode(hasText("ابدأ الالتقاط") and hasClickAction())
            .performScrollTo()
            .assertIsDisplayed()
            .assertHasClickAction()
            .performClick()
        compose.runOnIdle {
            assertEquals(VoxColors.BackgroundDark, renderedBackground)
            assertEquals(1, folderLaunches)
            assertEquals(null, started)
        }
    }

}
