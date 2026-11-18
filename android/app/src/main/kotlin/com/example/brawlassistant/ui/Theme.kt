package com.example.brawlassistant.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** Draft Room 디자인 토큰 (iOS Theme 과 같은 값). 검은 배경 · 미니멀 · 강조색은 필요한 곳에만 */
object Tokens {
    val background = Color(0xFF000000)
    val card = Color(0xFF111111)
    val secondaryBackground = Color(0xFF1A1A1A)
    val text = Color(0xFFFFFFFF)
    val secondaryText = Color(0xFF8E8E93)
    val divider = Color(0xFF292929)
    /** Draft Room 웹 강조색 (--gold) */
    val accent = Color(0xFFFFCF1F)
    val error = Color(0xFFFF3D6E)
    val positive = Color(0xFF36E39B)
}

@Composable
fun BrawlTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            background = Tokens.background, surface = Tokens.card, surfaceVariant = Tokens.secondaryBackground,
            onBackground = Tokens.text, onSurface = Tokens.text, onSurfaceVariant = Tokens.secondaryText,
            primary = Tokens.text, onPrimary = Color.Black, secondary = Tokens.accent, outline = Tokens.divider, error = Tokens.error,
        ),
        content = content,
    )
}
