import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Design tokens — Apple-inspired: restraint, whitespace, single accent
// ──────────────────────────────────────────────────────────────────────────────

const _radius = 12.0;
const _radiusSm = 8.0;
const _radiusLg = 16.0;

ThemeData buildLightTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    // Primary — pure black as accent (most premium)
    primary: Color(0xFF1D1D1F),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFF5F5F7),
    onPrimaryContainer: Color(0xFF1D1D1F),
    // Secondary — warm gray
    secondary: Color(0xFF6E6E73),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF5F5F7),
    onSecondaryContainer: Color(0xFF3A3A3C),
    // Tertiary — subtle warm tone for differentiation
    tertiary: Color(0xFF86868B),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF5F5F7),
    onTertiaryContainer: Color(0xFF48484A),
    // Error — the only real color in the system
    error: Color(0xFFFF3B30),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFF2F1),
    onErrorContainer: Color(0xFF6B1612),
    // Surfaces
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1D1D1F),
    onSurfaceVariant: Color(0xFF86868B),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF5F5F7),
    surfaceContainer: Color(0xFFF2F2F7),
    surfaceContainerHigh: Color(0xFFE5E5EA),
    surfaceContainerHighest: Color(0xFFD1D1D6),
    // Outline
    outline: Color(0xFFC7C7CC),
    outlineVariant: Color(0xFFE5E5EA),
    inverseSurface: Color(0xFF1D1D1F),
    onInverseSurface: Color(0xFFF5F5F7),
  );
  return _build(scheme, Brightness.light);
}

ThemeData buildDarkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    // Primary — pure white as accent
    primary: Color(0xFFF5F5F7),
    onPrimary: Color(0xFF1D1D1F),
    primaryContainer: Color(0xFF2C2C2E),
    onPrimaryContainer: Color(0xFFF5F5F7),
    // Secondary
    secondary: Color(0xFF98989D),
    onSecondary: Color(0xFF1D1D1F),
    secondaryContainer: Color(0xFF2C2C2E),
    onSecondaryContainer: Color(0xFFD1D1D6),
    // Tertiary
    tertiary: Color(0xFF8E8E93),
    onTertiary: Color(0xFF1D1D1F),
    tertiaryContainer: Color(0xFF2C2C2E),
    onTertiaryContainer: Color(0xFFC7C7CC),
    // Error
    error: Color(0xFFFF453A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFF3D1714),
    onErrorContainer: Color(0xFFFFB4AB),
    // Surfaces — true blacks
    surface: Color(0xFF000000),
    onSurface: Color(0xFFF5F5F7),
    onSurfaceVariant: Color(0xFF98989D),
    surfaceContainerLowest: Color(0xFF000000),
    surfaceContainerLow: Color(0xFF1C1C1E),
    surfaceContainer: Color(0xFF2C2C2E),
    surfaceContainerHigh: Color(0xFF3A3A3C),
    surfaceContainerHighest: Color(0xFF48484A),
    // Outline
    outline: Color(0xFF48484A),
    outlineVariant: Color(0xFF38383A),
    inverseSurface: Color(0xFFF5F5F7),
    onInverseSurface: Color(0xFF1D1D1F),
  );
  return _build(scheme, Brightness.dark);
}

ThemeData _build(ColorScheme scheme, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final text = GoogleFonts.dmSansTextTheme(
    isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
  );

  // Refined text theme with tighter line heights
  final refined = text.copyWith(
    displayLarge: text.displayLarge?.copyWith(letterSpacing: -0.5),
    headlineLarge: text.headlineLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    headlineMedium: text.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleLarge: text.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: text.bodyLarge?.copyWith(height: 1.5),
    bodyMedium: text.bodyMedium?.copyWith(height: 1.5),
    bodySmall: text.bodySmall?.copyWith(height: 1.45),
    labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    labelMedium: text.labelMedium?.copyWith(
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
    ),
    labelSmall: text.labelSmall?.copyWith(letterSpacing: 0.3),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: refined,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,

    // ── AppBar ────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: scheme.primary,
      titleTextStyle: refined.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
        fontSize: 20,
      ),
      systemOverlayStyle: isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),

    // ── Cards ─────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      color: isDark ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    ),

    // ── Inputs ────────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: refined.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    ),

    // ── Buttons ───────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: refined.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusSm),
        ),
        textStyle: refined.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusSm),
        ),
      ),
    ),

    // ── Chips ─────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radiusLg),
      ),
      side: BorderSide.none,
      labelStyle: refined.labelMedium,
    ),

    // ── FAB ───────────────────────────────────────────────────────────────
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
      elevation: 2,
      highlightElevation: 4,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
    ),

    // ── Dialogs ───────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radiusLg),
      ),
      titleTextStyle: refined.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontSize: 18,
      ),
    ),

    // ── SnackBar ──────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radiusSm),
      ),
      elevation: 3,
    ),

    // ── BottomSheet ───────────────────────────────────────────────────────
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      dragHandleSize: const Size(36, 4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(_radiusLg)),
      ),
      surfaceTintColor: scheme.primary,
    ),

    // ── ListTile ──────────────────────────────────────────────────────────
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    ),

    // ── Divider ───────────────────────────────────────────────────────────
    dividerTheme: DividerThemeData(
      space: 1,
      thickness: 0.5,
      color: scheme.outlineVariant.withValues(alpha: 0.3),
    ),

    // ── NavigationBar ─────────────────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radiusSm),
      ),
      indicatorColor: scheme.primaryContainer.withValues(alpha: 0.7),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return refined.labelSmall!.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
    ),

    // ── ExpansionTile ─────────────────────────────────────────────────────
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
    ),

    // ── ProgressIndicator ─────────────────────────────────────────────────
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearTrackColor: scheme.surfaceContainerHighest,
    ),

    // ── SegmentedButton ───────────────────────────────────────────────────
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusSm),
          ),
        ),
      ),
    ),

    // ── PopupMenu ─────────────────────────────────────────────────────────
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
      elevation: 3,
      surfaceTintColor: scheme.primary,
    ),

    // ── Tooltip ───────────────────────────────────────────────────────────
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: refined.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),
  );
}
