import 'package:flutter/material.dart';

const requestCardColor = Color(0xFF1C2541);
const requestMuted = Color(0xFF94A3B8);
const requestAccent = Color(0xFFFBBF24);
const requestWarn = Color(0xFFF97316);

/// One request (account or password) in the admin's queue.
class RequestCard extends StatelessWidget {
  const RequestCard({
    super.key,
    required this.request,
    required this.icon,
    required this.subtitle,
    required this.busy,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    this.extraLines = const [],
    this.sameIdCount = 1,
    this.menu,
  });

  final Map<String, dynamic> request;
  final IconData icon;
  final String subtitle;
  final bool busy;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;
  final List<(IconData, String)> extraLines;

  /// Open requests for the same ID number; more than one means different
  /// people (or passwords) asked for the same account.
  final int sameIdCount;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final count = request['request_count'] as int? ?? 1;
    final note = request['note'] as String?;
    final created = DateTime.tryParse(request['created_at'] as String? ?? '');
    final last =
        DateTime.tryParse(request['last_requested_at'] as String? ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: requestCardColor,
        borderRadius: BorderRadius.circular(14),
        border: sameIdCount > 1
            ? Border.all(color: requestWarn.withValues(alpha: 0.6))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: requestAccent.withValues(alpha: 0.2),
                child: Icon(icon, color: requestAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request['full_name'] as String? ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    Text(subtitle,
                        style:
                            const TextStyle(color: requestMuted, fontSize: 12)),
                  ],
                ),
              ),
              if (menu != null) menu!,
            ],
          ),
          if (sameIdCount > 1) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: requestWarn, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$sameIdCount different requests for this ID. Check '
                    'carefully which one is the real person.',
                    style: const TextStyle(color: requestWarn, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          for (final (lineIcon, text) in extraLines) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(lineIcon, size: 16, color: requestMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(text,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12.5)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            [
              if (created != null) 'Requested ${timeAgo(created)}',
              if (count > 1 && last != null)
                'sent $count times (last ${timeAgo(last)})',
            ].join(' • '),
            style: TextStyle(
                color: count > 1 ? requestAccent : requestMuted, fontSize: 12),
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0B132B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('"$note"',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic)),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: busy ? null : onSecondary,
                child: Text(secondaryLabel,
                    style: const TextStyle(color: requestMuted)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: requestAccent,
                    foregroundColor: Colors.black),
                onPressed: busy ? null : onPrimary,
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : Icon(primaryIcon, size: 18),
                label: Text(primaryLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Live list of requests with loading, empty and error states.
class RequestQueue extends StatelessWidget {
  const RequestQueue({
    super.key,
    required this.stream,
    required this.emptyText,
    required this.itemBuilder,
    required this.errorText,
  });

  final Stream<List<Map<String, dynamic>>> stream;
  final String emptyText;
  final String Function(Object error) errorText;

  /// Gets the request and how many open requests share its ID number.
  final Widget Function(Map<String, dynamic> request, int sameIdCount)
      itemBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _message(
              Icons.error_outline_rounded, errorText(snapshot.error!));
        }
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: requestAccent));
        }

        final requests = snapshot.data!;
        if (requests.isEmpty) {
          return _message(Icons.inbox_outlined, emptyText);
        }

        final perId = <String, int>{};
        for (final r in requests) {
          final id = r['id_number'] as String? ?? '';
          perId[id] = (perId[id] ?? 0) + 1;
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: requests.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${requests.length} waiting • oldest first',
                      style:
                          const TextStyle(color: requestMuted, fontSize: 12.5),
                    ),
                  );
                }
                final r = requests[i - 1];
                return itemBuilder(r, perId[r['id_number']] ?? 1);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _message(IconData icon, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF64748B), size: 48),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: requestMuted)),
            ],
          ),
        ),
      );
}

/// Yes / no confirmation in the app's style.
Future<bool> confirmRequestAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: requestCardColor,
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
      content: Text(message,
          style: const TextStyle(color: requestMuted, height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: requestMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: requestAccent, foregroundColor: Colors.black),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

String timeAgo(DateTime time) {
  final d = DateTime.now().difference(time.toLocal());
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays} days ago';
}
