import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const brand = Color(0xFF1C3352);
  const brandStrong = Color(0xFF13253F);
  const brandAccent = Color(0xFF2F5D8C);
  const brandSoft = Color(0xFFEAF0F7);
  const surface = Color(0xFFF6F8FB);
  const card = Color(0xFFFFFFFF);
  const border = Color(0xFFDCE4EE);
  const text = Color(0xFF162334);
  const textMuted = Color(0xFF667587);
  const success = Color(0xFF1E8E5A);
  const warning = Color(0xFFB7791F);
  const error = Color(0xFFC53B3B);
  const info = Color(0xFF2C6ECB);

  final scheme = ColorScheme.fromSeed(
    seedColor: brand,
    brightness: Brightness.light,
  ).copyWith(
    primary: brand,
    secondary: brandAccent,
    surface: card,
    error: error,
  );

  OutlineInputBorder borderFor(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: 1),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    splashFactory: InkRipple.splashFactory,
    fontFamily: 'Inter',
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: text,
        letterSpacing: -0.8,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: text,
        letterSpacing: -0.4,
        height: 1.15,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: text,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        color: text,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: textMuted,
        height: 1.5,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: border,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: const TextStyle(color: textMuted),
      labelStyle: const TextStyle(
        color: textMuted,
        fontWeight: FontWeight.w600,
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 50, minHeight: 48),
      suffixIconConstraints: const BoxConstraints(minWidth: 50, minHeight: 48),
      border: borderFor(border),
      enabledBorder: borderFor(border),
      focusedBorder: borderFor(brandAccent),
      errorBorder: borderFor(error),
      focusedErrorBorder: borderFor(error),
      floatingLabelStyle: const TextStyle(
        color: brandAccent,
        fontWeight: FontWeight.w700,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: brand,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: const BorderSide(color: border),
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: brand,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: brand,
        backgroundColor: brandSoft,
        minimumSize: const Size(42, 42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      titleTextStyle: TextStyle(
        color: text,
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
      subtitleTextStyle: TextStyle(
        color: textMuted,
        fontSize: 13,
        height: 1.45,
      ),
      iconColor: textMuted,
    ),
    chipTheme: ChipThemeData(
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: const BorderSide(color: border),
      backgroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: const BorderSide(color: border),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return brand;
        return Colors.white;
      }),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return brand;
        return textMuted;
      }),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      textStyle: TextStyle(color: text),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: brandStrong,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: text,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    extensions: const [
      AppPalette(
        brand: brand,
        brandStrong: brandStrong,
        brandAccent: brandAccent,
        brandSoft: brandSoft,
        surface: surface,
        card: card,
        border: border,
        text: text,
        textMuted: textMuted,
        success: success,
        warning: warning,
        error: error,
        info: info,
      ),
    ],
  );
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brand,
    required this.brandStrong,
    required this.brandAccent,
    required this.brandSoft,
    required this.surface,
    required this.card,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });

  final Color brand;
  final Color brandStrong;
  final Color brandAccent;
  final Color brandSoft;
  final Color surface;
  final Color card;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  static const fallback = AppPalette(
    brand: Color(0xFF1C3352),
    brandStrong: Color(0xFF13253F),
    brandAccent: Color(0xFF2F5D8C),
    brandSoft: Color(0xFFEAF0F7),
    surface: Color(0xFFF6F8FB),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFDCE4EE),
    text: Color(0xFF162334),
    textMuted: Color(0xFF667587),
    success: Color(0xFF1E8E5A),
    warning: Color(0xFFB7791F),
    error: Color(0xFFC53B3B),
    info: Color(0xFF2C6ECB),
  );

  @override
  AppPalette copyWith({
    Color? brand,
    Color? brandStrong,
    Color? brandAccent,
    Color? brandSoft,
    Color? surface,
    Color? card,
    Color? border,
    Color? text,
    Color? textMuted,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
  }) {
    return AppPalette(
      brand: brand ?? this.brand,
      brandStrong: brandStrong ?? this.brandStrong,
      brandAccent: brandAccent ?? this.brandAccent,
      brandSoft: brandSoft ?? this.brandSoft,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      border: border ?? this.border,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      brand: Color.lerp(brand, other.brand, t) ?? brand,
      brandStrong: Color.lerp(brandStrong, other.brandStrong, t) ?? brandStrong,
      brandAccent: Color.lerp(brandAccent, other.brandAccent, t) ?? brandAccent,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t) ?? brandSoft,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      card: Color.lerp(card, other.card, t) ?? card,
      border: Color.lerp(border, other.border, t) ?? border,
      text: Color.lerp(text, other.text, t) ?? text,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      error: Color.lerp(error, other.error, t) ?? error,
      info: Color.lerp(info, other.info, t) ?? info,
    );
  }
}

extension AppPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.fallback;
}

extension AppPaletteConvenienceX on AppPalette {
  Color get surfaceAlt => brandSoft.withValues(alpha: 0.35);

  Gradient get heroGradient => LinearGradient(
        colors: [brandStrong, brand],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}