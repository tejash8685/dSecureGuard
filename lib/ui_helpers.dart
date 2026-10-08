import 'package:flutter/material.dart';

dynamic field(Map<String, dynamic> row, String name) {
  if (row.containsKey(name)) return row[name];
  for (final entry in row.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

List<Map<String, dynamic>> rowsOf(dynamic value) =>
    value is List
        ? value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
        : [];
Map<String, dynamic> mapOf(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
String _splitLabel(String name) => name
    .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match[1]} ${match[2]}',
    )
    .replaceAll('_', ' ');
String labelOf(String name) {
  const labels = {
    'sno': 'Serial number',
    'ano': 'Account number',
    'cpuID': 'CPU ID',
    'biosID': 'BIOS ID',
    'macID': 'MAC ID',
    'autoriseCode': 'Activation code',
    'canLogin': 'Allow login',
    'canAddUser': 'Add users',
    'canEditUser': 'Edit users',
    'canDeleteUser': 'Delete users',
    'canViewProduct': 'View products',
    'canAddProduct': 'Add products',
    'canEditProduct': 'Edit products',
    'canDeleteProduct': 'Delete products',
    'canAssignProduct': 'Assign products',
    'canActivation': 'Manage activations',
  };
  final label = labels[name] ?? _splitLabel(name);
  return label.isEmpty ? label : label[0].toUpperCase() + label.substring(1);
}

String shortDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '—';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Pending' => const Color(0xff966300),
      'Approved' || 'Active' => const Color(0xff216b51),
      'Rejected' || 'Inactive' => const Color(0xffb3261e),
      _ => const Color(0xff59645e),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String displayValue(dynamic value) {
  if (value == null || value == '') return '—';
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is Map) {
    return value.entries
        .map(
          (entry) =>
              '${labelOf(entry.key.toString())}: ${displayValue(entry.value)}',
        )
        .join('\n');
  }
  return value.toString();
}

Future<void> showRecordDetails(
  BuildContext context,
  String title,
  Map<String, dynamic> row,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder:
      (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  ...row.entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            labelOf(entry.key),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(displayValue(entry.value)),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
);

class ActivationFilters extends StatelessWidget {
  const ActivationFilters({
    super.key,
    required this.rows,
    required this.value,
    required this.onChanged,
  });
  final List<Map<String, dynamic>> rows;
  final String value;
  final ValueChanged<String> onChanged;
  static const statuses = ['All', 'Pending', 'Approved', 'Deactivated'];
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children:
            statuses
                .map(
                  (status) => ChoiceChip(
                    label: Text(
                      '$status (${rows.where((row) => status == 'All' || field(row, 'status') == status).length})',
                    ),
                    selected: value == status,
                    onSelected: (_) => onChanged(status),
                  ),
                )
                .toList(),
      ),
      const SizedBox(height: 8),
      Text(
        'Showing ${rows.where((row) => value == 'All' || field(row, 'status') == value).length} of ${rows.length} requests',
      ),
    ],
  );
}
