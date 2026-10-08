import 'package:flutter/material.dart';
import 'auth_session.dart';

class DeviceRegistryPage extends StatefulWidget {
  const DeviceRegistryPage({super.key, required this.session});
  final AuthSession session;
  @override
  State<DeviceRegistryPage> createState() => _DeviceRegistryPageState();
}

class _DeviceRegistryPageState extends State<DeviceRegistryPage> {
  List<Map<String, dynamic>> rows = [];
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(sessionChanged);
    load();
  }

  void sessionChanged() {
    if (!widget.session.signedIn && mounted) {
      setState(() {
        rows = [];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(sessionChanged);
    super.dispose();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.session.request('GET', '/devices');
      if (mounted) {
        setState(() {
          rows =
              (result as List)
                  .map((r) => Map<String, dynamic>.from(r as Map))
                  .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Registered devices'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Every account can sign in on one registered device. An administrator must reset the binding before changing devices.',
          ),
          const SizedBox(height: 16),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!busy && rows.isEmpty && error == null)
            const Text('No registered devices found.'),
          for (final row in rows)
            Card(
              child: ExpansionTile(
                leading: Icon(
                  (row['device'] as Map)['isActive'] == true
                      ? Icons.verified_user_outlined
                      : Icons.phonelink_erase,
                ),
                title: Text(
                  '${row['userName']} · ${(row['device'] as Map)['platform']}',
                ),
                subtitle: Text(
                  '${(row['device'] as Map)['machineName']} · ${(row['device'] as Map)['isActive'] == true ? 'Registered' : 'Revoked'}',
                ),
                children: [
                  for (final field in (row['device'] as Map).entries)
                    ListTile(
                      title: Text(field.key.toString()),
                      subtitle: SelectableText(
                        field.value == null || field.value == ''
                            ? 'Unavailable on this device'
                            : field.value.toString(),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
