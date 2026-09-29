import 'package:flutter/material.dart';

class HamaColors {
  static const navy = Color(0xFF0B1633);
  static const navy2 = Color(0xFF152A52);
  static const teal = Color(0xFF00A6A6);
  static const cyan = Color(0xFF26C6DA);
  static const orange = Color(0xFFFFA62B);
  static const green = Color(0xFF18A66A);
  static const red = Color(0xFFE45757);
  static const bg = Color(0xFFF4F7FB);
  static const surface = Colors.white;
  static const ink = Color(0xFF17233C);
  static const muted = Color(0xFF71809B);
  static const border = Color(0xFFE3E9F2);
}

class HamaTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: HamaColors.teal,
      brightness: Brightness.light,
    ).copyWith(
      primary: HamaColors.teal,
      secondary: HamaColors.orange,
      surface: HamaColors.surface,
      error: HamaColors.red,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: HamaColors.bg,
      fontFamily: 'Arial',
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: HamaColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: HamaColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: HamaColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: HamaColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: HamaColors.teal, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: HamaColors.teal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: HamaColors.navy,
          side: const BorderSide(color: HamaColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      dividerTheme: const DividerThemeData(color: HamaColors.border, space: 1),
      navigationDrawerTheme: const NavigationDrawerThemeData(
        backgroundColor: Colors.white,
      ),
    );
  }
}

class HamaMark extends StatelessWidget {
  final double size;
  final bool compact;
  const HamaMark({super.key, this.size = 48, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .28),
        gradient: const LinearGradient(
          colors: [HamaColors.teal, HamaColors.navy2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: HamaColors.navy.withOpacity(.18),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: size * .16,
            right: size * .17,
            child: Icon(Icons.circle, size: size * .13, color: Colors.white.withOpacity(.9)),
          ),
          Icon(Icons.account_tree_rounded, size: size * .52, color: Colors.white),
        ],
      ),
    );
  }
}

class HamaSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;
  const HamaSectionHeader({super.key, required this.title, required this.icon, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: HamaColors.teal.withOpacity(.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: HamaColors.teal),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: HamaColors.ink)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HamaColors.muted)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
