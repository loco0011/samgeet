import 'package:flutter/material.dart';

/// Screen-size helpers so every screen adapts: small phones, big phones,
/// landscape, foldables and tablets.
class Responsive {
  /// At or above this width we use a side rail instead of a bottom bar.
  static const double wide = 720;

  /// Content is centred and capped at this width on very large screens.
  static const double maxContent = 1200;

  static bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= wide;

  /// Width of a poster card in a horizontal shelf. On phones exactly three fit,
  /// with a peek of the fourth so it is obvious the row scrolls.
  static double posterWidth(double width) => width < 600 ? (width - 20 - 3 * 10) / 3.25 : (width >= 1000 ? 178.0 : 164.0);

  /// Poster cards are taller than they are wide.
  static double posterHeight(double w) => w * 1.28;

  /// How many category tiles fit per row (three on a phone).
  static int tileColumns(double width) => (width / 124).floor().clamp(3, 9);
}
