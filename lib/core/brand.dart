import 'package:flutter/material.dart';

// Ak Ulag look, taken from the "Easy Ride" taxi UI kit: amber/yellow brand colour,
// Poppins, white surfaces with thin yellow outlines, 8px-rounded inputs and buttons.
// This file is identical in every Ak Ulag Flutter app (staff, driver, rider, gateway).

class Brand {
  /// Splash / illustration yellow.
  static const yellow = Color(0xFFFFC400);

  /// Buttons, selected states and icon fills.
  static const amber = Color(0xFFEEAE0E);

  /// Amber for TEXT and thin icons on white (the bright amber is too pale to read).
  static const amberText = Color(0xFF9A6700);

  static const amberTint = Color(0xFFFFF8E1); // selected card / pale highlight
  static const amberLine = Color(0xFFFFE082); // card outline

  static const secondary = Color(0xFFB30B3A);
  static const success = Color(0xFF43A047);
  static const warning = Color(0xFFFB8C00);
  static const error = Color(0xFFF44336);

  static const text = Color(0xFF212121); // ContentPrimary
  static const textSecondary = Color(0xFF424242);
  static const textTertiary = Color(0xFF616161);
  static const disabled = Color(0xFFBDBDBD);
  static const line = Color(0xFFE0E0E0);
  static const background = Colors.white;
}

const _fontFamily = 'Poppins';

ThemeData buildBrandTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Brand.amber,
    onPrimary: Brand.text,
    primaryContainer: Color(0xFFFFF3CD),
    onPrimaryContainer: Color(0xFF5C4300),
    secondary: Brand.secondary,
    onSecondary: Colors.white,
    error: Brand.error,
    onError: Colors.white,
    surface: Brand.background,
    onSurface: Brand.text,
    onSurfaceVariant: Brand.textTertiary,
    outline: Brand.line,
    outlineVariant: Brand.amberLine,
    surfaceTint: Colors.transparent,
  );

  final radius8 = BorderRadius.circular(8);
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: radius8, borderSide: BorderSide(color: c, width: w));

  const buttonText = TextStyle(fontFamily: _fontFamily, fontSize: 14, fontWeight: FontWeight.w600);
  final buttonShape = RoundedRectangleBorder(borderRadius: radius8);

  return ThemeData(
    useMaterial3: true,
    fontFamily: _fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.background,
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: const DividerThemeData(color: Color(0xFFEEEEEE), space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.background,
      foregroundColor: Brand.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: TextStyle(
          fontFamily: _fontFamily, fontSize: 16, fontWeight: FontWeight.w600, color: Brand.text),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Brand.amber,
        foregroundColor: Brand.text,
        disabledBackgroundColor: const Color(0xFFF1E3B8),
        disabledForegroundColor: Brand.disabled,
        elevation: 0,
        minimumSize: const Size.fromHeight(50),
        textStyle: buttonText,
        shape: buttonShape,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.amber,
        foregroundColor: Brand.text,
        disabledBackgroundColor: const Color(0xFFF1E3B8),
        disabledForegroundColor: Brand.disabled,
        minimumSize: const Size(64, 48),
        textStyle: buttonText,
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.text,
        side: const BorderSide(color: Brand.amber),
        minimumSize: const Size(64, 48),
        textStyle: buttonText,
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Brand.amberText,
        textStyle: buttonText,
        shape: buttonShape,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Brand.amber,
      foregroundColor: Brand.text,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: Brand.disabled, fontSize: 13),
      labelStyle: const TextStyle(color: Brand.textTertiary, fontSize: 13),
      floatingLabelStyle: const TextStyle(color: Brand.amberText),
      border: border(Brand.line),
      enabledBorder: border(Brand.line),
      focusedBorder: border(Brand.amber, 1.5),
      errorBorder: border(Brand.error),
      focusedErrorBorder: border(Brand.error, 1.5),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Brand.amberLine),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: Brand.amber,
      side: const BorderSide(color: Brand.amberLine),
      labelStyle: const TextStyle(fontFamily: _fontFamily, fontSize: 13, color: Brand.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      showCheckmark: false,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Brand.text,
      unselectedLabelColor: Brand.textTertiary,
      indicatorColor: Brand.amber,
      dividerColor: Color(0xFFEEEEEE),
      labelStyle: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle: TextStyle(fontFamily: _fontFamily, fontSize: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: const Color(0xFFFFF3CD),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: _fontFamily,
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: s.contains(WidgetState.selected) ? Brand.amberText : Brand.textTertiary,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? Brand.amberText : Brand.textTertiary,
          )),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: const TextStyle(
          fontFamily: _fontFamily, fontSize: 17, fontWeight: FontWeight.w600, color: Brand.text),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Brand.text,
      contentTextStyle: const TextStyle(fontFamily: _fontFamily, color: Colors.white, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: radius8),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Brand.amber),
    textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Brand.amber, selectionColor: Color(0x55FFC400), selectionHandleColor: Brand.amber),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : Brand.disabled),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Brand.amber : const Color(0xFFEEEEEE)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Brand.amber : null),
      checkColor: const WidgetStatePropertyAll(Brand.text),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: Brand.amber,
        selectedForegroundColor: Brand.text,
        side: const BorderSide(color: Brand.amberLine),
      ),
    ),
    listTileTheme: const ListTileThemeData(iconColor: Brand.textSecondary),
    iconTheme: const IconThemeData(color: Brand.textSecondary),
  );
}
