import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'app_brand.dart';
import 'activation_page.dart';
import 'api_service.dart';
import 'auth_session.dart';
import 'record_editor.dart';
import 'ui_helpers.dart';

class ManagementPage extends StatefulWidget {
  const ManagementPage({super.key, required this.session});
  final AuthSession session;
  @override
  State<ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends State<ManagementPage>
    with WidgetsBindingObserver {
  String page = 'dashboard', filter = 'All';
  String search = '';
  int searchVersion = 0;
  bool loading = true,
      saving = false,
      polling = false,
      foreground = true,
      devicePage = false;
  String? error;
  int pending = 0, epoch = 0;
  bool baseline = false;
  final seen = <String>{};
  Timer? timer;
  CancelToken? loadToken;
  Map<String, dynamic> stats = {};
  List<Map<String, dynamic>> records = [], users = [], products = [];
  bool get admin => widget.session.isAdmin;
  String get accountName {
    final name =
        field(widget.session.user, 'fullName')?.toString().trim() ?? '';
    final username =
        field(widget.session.user, 'userName')?.toString().trim() ?? '';
    return name.isNotEmpty
        ? name
        : username.isNotEmpty
        ? username
        : appName;
  }

  Map<String, String> get menu => {
    'dashboard': 'Dashboard',
    if (admin) 'users': 'Users',
    'products': admin ? 'Products' : 'My products',
    if (admin) 'assignments': 'Product assignments',
    'activations': 'Activation requests',
    'profile': 'Profile',
    'more': 'Account',
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    attachNotifications();
    ApiService().requestNotificationPermission().catchError((_) => false);
    poll();
    startBackgroundAlerts();
    timer = Timer.periodic(const Duration(seconds: 15), (_) => poll());
  }

  void attachNotifications() {
    deviceChannel.setMethodCallHandler((call) async {
      if (call.method == 'activationNotificationTapped' && mounted) {
        openPending(mapOf(call.arguments)['status']?.toString() ?? 'Pending');
      }
    });
    deviceChannel
        .invokeMethod<dynamic>('getActivationNotification')
        .then((value) {
          if (mounted && value is Map) {
            openPending(value['status']?.toString() ?? 'Pending');
          }
        })
        .catchError((_) {});
  }

  Future<void> startBackgroundAlerts() async {
    if (!isAndroidDevice || !widget.session.signedIn) return;
    try {
      final started = await deviceChannel
          .invokeMethod<bool>('startRequestMonitor', {
            'token': widget.session.token,
            'apiUrl': apiBase,
            'expiresAt': widget.session.expiresAt!.millisecondsSinceEpoch,
          });
      if (started != true && mounted) {
        notice('Allow notifications to receive alerts after closing the app.');
      }
    } catch (_) {
      notice(
        'Background alerts could not start. Use Restart background alerts in the menu.',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      widget.session.checkExpiry();
      startBackgroundAlerts();
      poll();
      load();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    loadToken?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    deviceChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void openPending([String status = 'Pending']) {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      page = 'activations';
      search = '';
      ++searchVersion;
      filter = ActivationFilters.statuses.contains(status) ? status : 'All';
    });
    load();
  }

  Future<void> poll() async {
    if (polling || !foreground || devicePage || !widget.session.signedIn) {
      return;
    }
    polling = true;
    try {
      final result = mapOf(
        await widget.session.request('GET', '/activations/notifications'),
      );
      final requests = rowsOf(result['requests']);
      final fresh =
          requests
              .where(
                (r) =>
                    !seen.contains(
                      '${field(r, 'activationID')}|${field(r, 'requestDate')}',
                    ),
              )
              .toList();
      seen.addAll(
        requests.map(
          (r) => '${field(r, 'activationID')}|${field(r, 'requestDate')}',
        ),
      );
      if (!mounted) return;
      setState(() => pending = (result['pendingCount'] as num?)?.toInt() ?? 0);
      if (baseline && fresh.isNotEmpty) {
        notice(
          '${fresh.length} new activation request${fresh.length == 1 ? '' : 's'}',
        );
        try {
          await ApiService().requestNotificationPermission();
          await ApiService().showNotification(
            'New activation request',
            '${fresh.length} new request${fresh.length == 1 ? '' : 's'} waiting for review.',
            status: 'Pending',
          );
        } catch (_) {
          /* The badge remains available when notifications are disabled. */
        }
        if (page == 'activations' || page == 'dashboard') await load();
      }
      baseline = true;
    } catch (_) {
      /* Keep the last badge during temporary connection failures. */
    } finally {
      polling = false;
    }
  }

  Future<void> load() async {
    final current = ++epoch;
    loadToken?.cancel();
    final token = CancelToken();
    loadToken = token;
    final selected = page;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    Future<dynamic> get(String path) =>
        widget.session.request('GET', path, cancelToken: token);
    try {
      Map<String, dynamic> nextStats = {};
      List<Map<String, dynamic>> nextRecords = [],
          nextUsers = [],
          nextProducts = [];
      if (selected == 'more') {
        nextStats = {};
      } else if (selected == 'profile') {
        nextStats = mapOf(await get('/auth/me'));
      } else if (!admin &&
          ['dashboard', 'products', 'activations'].contains(selected)) {
        final result = await Future.wait([
          get('/dashboard/user'),
          if (selected != 'products') get('/activations/assigned'),
        ]);
        nextStats = mapOf(result[0]);
        nextProducts = rowsOf(nextStats['products']);
        nextRecords =
            selected == 'products'
                ? nextProducts
                : rowsOf(result[1])
                    .map(
                      (r) => {
                        ...mapOf(r['activation']),
                        ...Map<String, dynamic>.from(r)..remove('activation'),
                      },
                    )
                    .toList();
      } else if (selected == 'dashboard') {
        nextStats = mapOf(await get('/dashboard/admin'));
      } else if (selected == 'assignments') {
        final result = await Future.wait([
          get('/productassignments'),
          get('/users'),
          get('/products'),
        ]);
        nextRecords = rowsOf(result[0]);
        nextUsers = rowsOf(result[1]);
        nextProducts = rowsOf(result[2]);
      } else {
        nextRecords = rowsOf(await get('/$selected'));
      }
      if (mounted && current == epoch) {
        setState(() {
          stats = nextStats;
          records = nextRecords;
          users = nextUsers;
          products = nextProducts;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && current == epoch) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> edit([Map<String, dynamic>? row]) async {
    if (saving) return;
    try {
      Map<String, dynamic>? full = row;
      if (row != null && page == 'users') {
        full = mapOf(
          await widget.session.request('GET', '/users/${field(row, 'userId')}'),
        );
      }
      if (!mounted) return;
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder:
              (_) => RecordEditor(
                session: widget.session,
                kind: page,
                record: full,
                users: users,
                products: products,
              ),
        ),
      );
      if (changed == true) {
        notice('Saved successfully.');
        await load();
      }
    } catch (e) {
      notice(e.toString());
    }
  }

  Future<String?> confirm(String title, {bool reason = false}) async {
    final controller = TextEditingController();
    String? validation;
    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, update) => AlertDialog(
                  title: Text(title),
                  content:
                      reason
                          ? TextField(
                            controller: controller,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: 'Reason',
                              errorText: validation,
                            ),
                          )
                          : const Text('Continue with this action?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (reason && controller.text.trim().isEmpty) {
                          update(() => validation = 'Enter a reason');
                          return;
                        }
                        Navigator.pop(
                          context,
                          reason
                              ? controller.text.trim()
                              : 'Updated from Android',
                        );
                      },
                      child: const Text('Confirm'),
                    ),
                  ],
                ),
          ),
    );
    // Dialog exit animations may still refer to the controller.
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
    return result;
  }

  bool canManage(Map<String, dynamic> r) =>
      admin ||
      stats['canManageActivations'] == true &&
          products.any(
            (p) =>
                field(p, 'productID') == field(r, 'productID') &&
                field(p, 'productActive') == true &&
                field(p, 'assignmentActive') == true,
          );
  Future<void> action(
    String kind,
    Map<String, dynamic> row,
    String operation,
  ) async {
    if (saving) return;
    final reason = await confirm(
      operation == 'approve'
          ? 'Accept activation request?'
          : '${labelOf(operation)} ${kind == 'assignments'
              ? 'assignment'
              : kind == 'activations'
              ? 'activation'
              : kind == 'users'
              ? 'user'
              : 'product'}?',
      reason: operation == 'reject',
    );
    if (reason == null || !mounted) return;
    setState(() => saving = true);
    try {
      final id = field(
        row,
        kind == 'users'
            ? 'userId'
            : kind == 'products'
            ? 'productID'
            : kind == 'assignments'
            ? 'productAssignID'
            : 'activationID',
      );
      final base = kind == 'assignments' ? 'productassignments' : kind;
      final result = await widget.session.request(
        operation == 'delete' ? 'DELETE' : 'POST',
        '/$base/$id${operation == 'delete' ? '' : '/${operation == 'reset' ? 'reset-device' : operation}'}',
        data: kind == 'activations' ? {'reason': reason} : null,
      );
      if (!mounted) return;
      if (operation == 'approve') {
        await showRecordDetails(context, 'Activation accepted', mapOf(result));
      } else {
        notice('Updated successfully.');
      }
      await load();
      await poll();
    } catch (e) {
      notice(e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void selectPage(String next) {
    if (page == next) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      page = next;
      search = '';
    });
    load();
  }

  List<Map<String, dynamic>> get searchedRecords =>
      records
          .where(
            (row) =>
                search.isEmpty ||
                row.values.any(
                  (v) =>
                      v.toString().toLowerCase().contains(search.toLowerCase()),
                ),
          )
          .toList();

  Widget button(String title, VoidCallback callback, {bool allowed = true}) =>
      TextButton(
        onPressed: saving || !allowed ? null : callback,
        child: Text(title),
      );

  IconData iconFor(String kind) => switch (kind) {
    'users' => Icons.person_outline_rounded,
    'products' => Icons.inventory_2_outlined,
    'assignments' => Icons.link_rounded,
    'activations' => Icons.verified_outlined,
    _ => Icons.dashboard_outlined,
  };

  Widget sectionTitle(String title, {String? destination}) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (destination != null)
          TextButton(
            onPressed: () => selectPage(destination),
            child: const Text('View all'),
          ),
      ],
    ),
  );

  Widget emptyState(
    String title,
    String subtitle, {
    IconData icon = Icons.inbox_outlined,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
    child: Column(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            icon,
            size: 30,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget detailLine(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );

  Widget card(Map<String, dynamic> row, String kind) {
    final active = field(row, 'isActive') == true;
    final status =
        kind == 'activations'
            ? field(row, 'status')?.toString() ?? 'Pending'
            : kind == 'products' && !admin
            ? field(row, 'productActive') == true &&
                    field(row, 'assignmentActive') == true
                ? 'Active'
                : 'Inactive'
            : active
            ? 'Active'
            : 'Inactive';
    final title =
        kind == 'users'
            ? field(row, 'fullName') ?? field(row, 'userName')
            : kind == 'products'
            ? field(row, 'productName')
            : kind == 'assignments'
            ? users
                    .where((u) => field(u, 'userId') == field(row, 'userID'))
                    .map((u) => field(u, 'userName'))
                    .firstOrNull ??
                'User #${field(row, 'userID')}'
            : field(row, 'productName') ??
                'Product #${field(row, 'productID')}';
    final subtitle =
        kind == 'users'
            ? '@${field(row, 'userName')} · ${field(row, 'userType')}'
            : kind == 'products'
            ? '${field(row, 'productCode')} · v${field(row, 'version') ?? '—'}'
            : kind == 'assignments'
            ? products
                    .where(
                      (p) => field(p, 'productID') == field(row, 'productID'),
                    )
                    .map((p) => field(p, 'productName'))
                    .firstOrNull
                    ?.toString() ??
                'Product #${field(row, 'productID')}'
            : 'Request #${field(row, 'activationID')} · ${shortDate(field(row, 'requestDate'))}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    iconFor(kind),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$title',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(status),
              ],
            ),
            if (kind == 'users' &&
                (field(row, 'email')?.toString().isNotEmpty ?? false))
              detailLine(Icons.mail_outline, field(row, 'email').toString()),
            if (kind == 'users' &&
                (field(row, 'mobileNo')?.toString().isNotEmpty ?? false))
              detailLine(
                Icons.phone_outlined,
                field(row, 'mobileNo').toString(),
              ),
            if (kind == 'users' && field(row, 'authenticationCode') != null)
              detailLine(
                Icons.pin_outlined,
                'Authentication code: ${field(row, 'authenticationCode')}',
              ),
            if (kind == 'assignments' || kind == 'products' && !admin)
              detailLine(
                Icons.date_range_outlined,
                '${shortDate(field(row, 'startDate'))} – ${field(row, 'expiryDate') == null ? 'No expiry' : shortDate(field(row, 'expiryDate'))}',
              ),
            if (kind == 'activations' && field(row, 'ano') != null)
              detailLine(Icons.tag_rounded, 'Account: ${field(row, 'ano')}'),
            if (kind == 'activations' && field(row, 'sno') != null)
              detailLine(
                Icons.confirmation_number_outlined,
                'Serial: ${field(row, 'sno')}',
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (kind == 'activations' && status == 'Pending') ...[
                  FilledButton.icon(
                    onPressed:
                        saving || !canManage(row)
                            ? null
                            : () => action(kind, row, 'approve'),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Accept'),
                  ),
                  OutlinedButton(
                    onPressed:
                        saving || !canManage(row)
                            ? null
                            : () => action(kind, row, 'reject'),
                    child: const Text('Reject'),
                  ),
                ],
                button(
                  'Details',
                  () => showRecordDetails(context, '$title', row),
                ),
                if (kind == 'activations' &&
                    admin &&
                    active &&
                    status == 'Approved')
                  button('Deactivate', () => action(kind, row, 'deactivate')),
                if (admin &&
                    ['users', 'products', 'assignments'].contains(kind)) ...[
                  button('Edit', () => edit(row)),
                  if (kind != 'assignments')
                    button(
                      active ? 'Deactivate' : 'Activate',
                      () =>
                          action(kind, row, active ? 'deactivate' : 'activate'),
                    ),
                  if (kind == 'users')
                    button('Reset device', () => action(kind, row, 'reset')),
                  if (kind == 'assignments')
                    button('Remove', () => action(kind, row, 'delete')),
                ],
              ],
            ),
            if (kind == 'activations' && status == 'Pending' && !canManage(row))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'An active assignment and activation permission are required to review this request.',
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> activationList() {
    final rows = searchedRecords;
    final visible =
        rows
            .where((r) => filter == 'All' || field(r, 'status') == filter)
            .toList();
    return [
      ActivationFilters(
        rows: rows,
        value: filter,
        onChanged: (v) => setState(() => filter = v),
      ),
      const SizedBox(height: 16),
      if (visible.isEmpty)
        emptyState(
          'No requests found',
          'Try another filter or pull down to refresh.',
        ),
      ...visible.map((r) => card(r, 'activations')),
    ];
  }

  Future<void> openDevice() async {
    devicePage = true;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ActivationPage()),
    );
    if (mounted) {
      devicePage = false;
      attachNotifications();
      poll();
    }
  }

  Widget greeting() {
    final name = accountName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            admin ? 'Administrator overview' : 'Your workspace',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Hello, $name',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Manage your products and activation requests.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget pendingCard() => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.pending_actions_rounded, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$pending waiting for review',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Text('New activation requests'),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Review pending requests',
            onPressed: () => openPending(),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    ),
  );

  Widget metrics() => LayoutBuilder(
    builder: (context, constraints) {
      const names = {
        'totalUsers': 'Users',
        'activeUsers': 'Active users',
        'totalProducts': 'Products',
        'activeProducts': 'Active products',
        'pendingActivations': 'Pending requests',
        'approvedActivations': 'Approved',
        'rejectedActivations': 'Rejected',
        'activeLicenses': 'Active licenses',
      };
      final count = constraints.maxWidth >= 600 ? 4 : 2;
      final width = (constraints.maxWidth - 12 * (count - 1)) / count;
      return Wrap(
        spacing: 12,
        children:
            names.entries
                .map(
                  (e) => SizedBox(
                    width: width,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              e.key.contains('Users')
                                  ? Icons.people_outline
                                  : e.key.contains('Products')
                                  ? Icons.inventory_2_outlined
                                  : Icons.verified_outlined,
                              size: 22,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${stats[e.key] ?? 0}',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              e.value,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
      );
    },
  );

  Widget accountPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                child: Text(accountName.characters.first),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accountName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(admin ? 'Administrator' : 'User'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      Card(
        child: Column(
          children: [
            if (admin)
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('Product assignments'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => selectPage('assignments'),
              ),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Profile'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => selectPage('profile'),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android_rounded),
              title: const Text('Activate this device'),
              trailing: const Icon(Icons.chevron_right),
              onTap: openDevice,
            ),
            if (isAndroidDevice)
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Background alerts'),
                subtitle: const Text('Restart monitoring for new requests'),
                trailing: const Icon(Icons.refresh_rounded),
                onTap: startBackgroundAlerts,
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () async {
          final answer = await confirm('Sign out?');
          if (answer != null) await widget.session.signOut();
        },
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Sign out'),
      ),
    ],
  );

  List<Widget> pageContent() {
    if (page == 'more') return [accountPage()];
    if (page == 'profile') {
      return [
        sectionTitle('Account details'),
        Card(
          child: Column(
            children:
                stats.entries
                    .map(
                      (e) => ListTile(
                        title: Text(labelOf(e.key)),
                        subtitle: SelectableText(displayValue(e.value)),
                      ),
                    )
                    .toList(),
          ),
        ),
        TextButton.icon(
          onPressed: () => selectPage('more'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to account'),
        ),
      ];
    }
    if (page == 'dashboard' && admin) {
      return [
        greeting(),
        if (pending > 0) pendingCard(),
        metrics(),
        for (final section in [
          'recentActivations',
          'recentProducts',
          'recentUsers',
        ]) ...[
          sectionTitle(
            labelOf(section),
            destination:
                section == 'recentActivations'
                    ? 'activations'
                    : section == 'recentProducts'
                    ? 'products'
                    : 'users',
          ),
          if (rowsOf(stats[section]).isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No records yet.'),
            ),
          ...rowsOf(stats[section]).map(
            (r) => Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: Icon(
                  iconFor(
                    section == 'recentActivations'
                        ? 'activations'
                        : section == 'recentProducts'
                        ? 'products'
                        : 'users',
                  ),
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  '${field(r, 'fullName') ?? field(r, 'productName') ?? 'Request #${field(r, 'activationID')}'}',
                ),
                subtitle: Text(
                  section == 'recentActivations'
                      ? shortDate(field(r, 'requestDate'))
                      : field(r, 'productCode')?.toString() ??
                          field(r, 'userName')?.toString() ??
                          '',
                ),
                trailing:
                    field(r, 'status') != null
                        ? StatusBadge(field(r, 'status').toString())
                        : const Icon(Icons.chevron_right),
                onTap: () => showRecordDetails(context, labelOf(section), r),
              ),
            ),
          ),
        ],
      ];
    }
    if (page == 'dashboard') {
      return [
        greeting(),
        if (pending > 0) pendingCard(),
        sectionTitle('Your products', destination: 'products'),
        if (products.isEmpty)
          emptyState(
            'No assigned products',
            'Your administrator can assign products to your account.',
            icon: Icons.inventory_2_outlined,
          ),
        ...products.map((r) => card(r, 'products')),
        sectionTitle('Activation requests', destination: 'activations'),
        ...activationList(),
      ];
    }
    if (page == 'activations') return activationList();
    return [
      if (searchedRecords.isEmpty)
        emptyState(
          search.isEmpty ? 'No records yet' : 'No results found',
          search.isEmpty && admin
              ? 'Use the Add button to get started.'
              : 'Try another search or pull down to refresh.',
          icon: iconFor(page),
        ),
      ...searchedRecords.map((r) => card(r, page)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pages =
        admin
            ? ['dashboard', 'activations', 'products', 'users', 'more']
            : ['dashboard', 'products', 'activations', 'more'];
    final index = pages.indexOf(page);
    return PopScope(
      canPop: page == 'dashboard',
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          selectPage(
            page == 'profile' || page == 'assignments' ? 'more' : 'dashboard',
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(
                  appLogoAsset,
                  width: 34,
                  height: 34,
                  semanticLabel: appName,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  page == 'dashboard' ? appName : menu[page] ?? appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '$pending pending requests',
              onPressed: () => openPending(),
              icon: Badge(
                label: Text('$pending'),
                isLabelVisible: pending > 0,
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index < 0 ? pages.length - 1 : index,
          onDestinationSelected: (i) => selectPage(pages[i]),
          destinations:
              pages
                  .map(
                    (p) => NavigationDestination(
                      icon: Icon(
                        p == 'dashboard'
                            ? Icons.home_outlined
                            : p == 'more'
                            ? Icons.person_outline_rounded
                            : iconFor(p),
                      ),
                      selectedIcon: Icon(
                        p == 'dashboard'
                            ? Icons.home_rounded
                            : p == 'more'
                            ? Icons.person_rounded
                            : p == 'activations'
                            ? Icons.verified_rounded
                            : p == 'products'
                            ? Icons.inventory_2_rounded
                            : Icons.people_rounded,
                      ),
                      label:
                          p == 'dashboard'
                              ? 'Home'
                              : p == 'activations'
                              ? 'Requests'
                              : p == 'more'
                              ? 'Account'
                              : menu[p]!,
                    ),
                  )
                  .toList(),
        ),
        floatingActionButton:
            admin &&
                    ['users', 'products', 'assignments'].contains(page) &&
                    !loading
                ? FloatingActionButton.extended(
                  onPressed: saving ? null : () => edit(),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(
                    page == 'assignments'
                        ? 'Assign product'
                        : page == 'users'
                        ? 'Add user'
                        : 'Add product',
                  ),
                )
                : null,
        body: SafeArea(
          top: false,
          bottom: false,
          child:
              loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                    onRefresh: load,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 840),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                          children: [
                            if (saving) const LinearProgressIndicator(),
                            if (error != null) ...[
                              emptyState(
                                'Unable to load this page',
                                error!,
                                icon: Icons.wifi_off_rounded,
                              ),
                              FilledButton.icon(
                                onPressed: load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                              ),
                            ] else ...[
                              if ([
                                'users',
                                'products',
                                'assignments',
                                'activations',
                              ].contains(page)) ...[
                                TextFormField(
                                  key: ValueKey('$page:$searchVersion'),
                                  initialValue: search,
                                  onChanged:
                                      (value) => setState(() => search = value),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Search ${page == 'activations' ? 'requests' : page}',
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              ...pageContent(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
        ),
      ),
    );
  }
}
