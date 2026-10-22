import 'dart:async';

import 'package:flutter/material.dart';

/// Shared pieces for the login-screen request forms
/// (Request an account, Forgot password).

mixin RequestCooldown<T extends StatefulWidget> on State<T> {
  Duration cooldown = Duration.zero;
  Timer? _timer;

  bool get isCoolingDown => cooldown > Duration.zero;

  String get cooldownLabel {
    final s = (cooldown.inSeconds % 60).toString().padLeft(2, '0');
    return '${cooldown.inMinutes}:$s';
  }

  void startCooldown(Duration remaining) {
    _timer?.cancel();
    setState(() => cooldown = remaining);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      final next = cooldown - const Duration(seconds: 1);
      setState(() => cooldown = next.isNegative ? Duration.zero : next);
      if (next <= Duration.zero) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

Widget requestField(
  TextEditingController controller,
  String label,
  IconData icon, {
  TextCapitalization caps = TextCapitalization.none,
  String? Function(String?)? validator,
  String? helper,
  int? maxLength,
  int maxLines = 1,
  bool obscure = false,
  VoidCallback? onToggleObscure,
  ValueChanged<String>? onChanged,
  TextInputType? keyboardType,
}) {
  return TextFormField(
    controller: controller,
    textCapitalization: caps,
    validator: validator,
    maxLength: maxLength,
    maxLines: maxLines,
    obscureText: obscure,
    onChanged: onChanged,
    keyboardType: keyboardType,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 2,
      helperStyle: const TextStyle(color: Color(0xFF64748B)),
      labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
      counterStyle: const TextStyle(color: Color(0xFF64748B)),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B)),
      suffixIcon: onToggleObscure == null
          ? null
          : IconButton(
              tooltip: obscure ? 'Show password' : 'Hide password',
              icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF64748B)),
              onPressed: onToggleObscure,
            ),
      filled: true,
      fillColor: const Color(0xFF1C2541),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

Widget requestSubmitButton({
  required bool sending,
  required bool coolingDown,
  required String cooldownLabel,
  required String label,
  required VoidCallback onPressed,
}) {
  return ElevatedButton.icon(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF3A86FF),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    onPressed: sending || coolingDown ? null : onPressed,
    icon: sending
        ? const SizedBox(
            width: 16,
            height: 16,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : const Icon(Icons.send_rounded, size: 18),
    label: Text(sending
        ? 'Sending...'
        : coolingDown
            ? 'Wait $cooldownLabel'
            : label),
  );
}

Widget requestSentCard(BuildContext context,
    {required String title, required String message}) {
  return Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF1C2541),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0x6610B981)),
    ),
    child: Column(
      children: [
        const Icon(Icons.mark_email_read_rounded,
            color: Color(0xFF10B981), size: 40),
        const SizedBox(height: 10),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        const SizedBox(height: 8),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF94A3B8), height: 1.4)),
        const SizedBox(height: 14),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to login',
              style: TextStyle(color: Color(0xFF38BDF8))),
        ),
      ],
    ),
  );
}

/// Snackbar text for a request result, or null when it was sent.
String? requestResultMessage(String result) => switch (result) {
      'submitted' => null,
      'cooldown' =>
        'You just sent a request. Please wait before sending again.',
      'invalid_id' => 'Check your ID number format.',
      'invalid_contact' => 'Enter a valid email or phone number.',
      'invalid' => 'Please check your name.',
      'rate_limited' =>
        'Too many requests right now. Please try again in a few minutes.',
      'offline' => 'No internet connection. Please try again.',
      _ => 'Something went wrong. Please try again later.',
    };

/// An email address or a phone number (at least 7 digits).
bool isValidContact(String value) {
  final v = value.trim();
  if (RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) return true;
  final digits = v.replaceAll(RegExp(r'[\s\-()+.]'), '');
  return RegExp(r'^\d{7,15}$').hasMatch(digits);
}
