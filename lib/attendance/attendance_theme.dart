// lib/attendance/attendance_theme.dart
import 'package:flutter/material.dart';

const kBg = Color(0xFF050805);
const kGreen = Color(0xFF00FF41);
const kRed = Color(0xFFFF3B3B);
const kAmber = Color(0xFFFFC107);
const kDim = Color(0xFF1B3A1B);
const kMono = 'monospace';

BoxDecoration neonBox({Color color = kGreen}) => BoxDecoration(
      color: color.withOpacity(0.04),
      border: Border.all(color: color.withOpacity(0.45)),
      borderRadius: BorderRadius.circular(10),
    );

TextStyle mono(double size, {Color color = kGreen, bool bold = false}) => TextStyle(
      color: color,
      fontFamily: kMono,
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
