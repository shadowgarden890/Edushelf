import 'package:flutter/material.dart';

/// One of the college's four programs, with its logo.
class Department {
  const Department(this.code, this.name, this.logo, this.color);

  /// Matches `users.department` and `materials.program` (e.g. 'BSIT').
  final String code;
  final String name;
  final String logo;
  final Color color;

  static const all = [
    Department('BSIT', 'BS Information Technology', 'assets/logos/bsit.jpg',
        Color(0xFF94A3B8)),
    Department(
        'BSA', 'BS Accountancy', 'assets/logos/bsa.jpg', Color(0xFF5B7DB8)),
    Department('BSBA', 'BS Business Administration', 'assets/logos/bsba.jpg',
        Color(0xFFF5B301)),
    Department('BSOA', 'BS Office Administration', 'assets/logos/bsoa.jpg',
        Color(0xFFB91C1C)),
  ];
}
