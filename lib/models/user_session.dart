class UserSession {
  final String idNumber;
  final String fullName;
  final String role; // 'student', 'instructor', 'admin'
  final String department; // 'BSIT', 'BSBA', 'BSA', 'BSOA', 'ALL'

  UserSession({
    required this.idNumber,
    required this.fullName,
    required this.role,
    required this.department,
  });

  /// Parse an ID number and return a map with role and department.
  ///
  /// ID formats:
  ///   Student:      DD-YY-NNNNN   (e.g., IT-23-01003)
  ///   Faculty:      DD-T-NNNNN    (e.g., IT-T-00001)
  ///   Administrator: ADMIN-NNNN   (e.g., ADMIN-0001)
  static Map<String, String>? parseId(String idNumber) {
    final parts = idNumber.trim().toUpperCase().split('-');

    // Administrator
    if (parts.length == 2 && parts[0] == 'ADMIN') {
      return {'role': 'admin', 'department': 'ALL'};
    }

    // Student or Faculty
    if (parts.length == 3) {
      final deptCode = parts[0];
      final middle = parts[1];

      final department = _departmentFromCode(deptCode);
      if (department == null) return null;

      if (middle == 'T') {
        return {'role': 'instructor', 'department': department};
      }

      // Student: middle part is a 2-digit year
      if (middle.length == 2 && int.tryParse(middle) != null) {
        return {'role': 'student', 'department': department};
      }
    }

    return null;
  }

  /// Map department codes (IT, BA, AC, OA) to full program names.
  static String? _departmentFromCode(String code) {
    switch (code) {
      case 'IT':
        return 'BSIT';
      case 'BA':
        return 'BSBA';
      case 'AC':
        return 'BSA';
      case 'OA':
        return 'BSOA';
      default:
        return null;
    }
  }

  /// Create a UserSession from a Supabase row (Map<String, dynamic>).
  factory UserSession.fromMap(Map<String, dynamic> data) {
    return UserSession(
      idNumber: data['id_number'] ?? '',
      fullName: data['full_name'] ?? '',
      role: data['role'] ?? 'student',
      department: data['department'] ?? 'BSIT',
    );
  }

  /// Convert this session to a Map (for Supabase writes).
  Map<String, dynamic> toMap() {
    return {
      'id_number': idNumber,
      'full_name': fullName,
      'role': role,
      'department': department,
    };
  }
}
