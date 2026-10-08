import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'activation_request.dart';
import 'api_service.dart' show ApiService, deviceChannel, storage;

class ActivationPage extends StatefulWidget {
  const ActivationPage({super.key});

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage>
    with WidgetsBindingObserver {
  final product = TextEditingController();
  final productId = TextEditingController();
  final api = ApiService();
  final listKey = GlobalKey();
  final List<SavedActivationRequest> requests = [];
  Timer? pollTimer;
  String message = 'Loading saved activation requests…';
  String selectedStatus = 'All';
  bool busy = false;
  bool refreshing = false;
  bool restored = false;
  bool foreground = true;
  static const statuses = ['All', 'Pending', 'Approved', 'Deactivated'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    deviceChannel.setMethodCallHandler((call) async {
      if (call.method == 'activationNotificationTapped' &&
          call.arguments is Map) {
        _openNotification(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
    api.requestNotificationPermission().catchError((_) => false);
    _restore();
  }

  Future<void> _restore() async {
    try {
      final saved = await storage.read(key: 'activationRequests');
      if (!mounted) return;
      if (saved != null) {
        final records = jsonDecode(saved) as List;
        requests.addAll(
          records.map(
            (row) => SavedActivationRequest.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          ),
        );
      }
      final code = await storage.read(key: 'productCode');
      final idText = await storage.read(key: 'productId');
      final oldStatus = await storage.read(key: 'activationStatus');
      final notified = await storage.read(key: 'activationNotificationStatus');
      if (!mounted) return;
      product.text = code ?? '';
      productId.text = idText ?? '';
      final id = int.tryParse(idText ?? '');
      if (id != null &&
          code != null &&
          code.isNotEmpty &&
          !requests.any((row) => row.key == '$id:$code')) {
        requests.add(
          SavedActivationRequest(
            productId: id,
            productCode: code,
            status: oldStatus ?? 'Pending',
            notifiedStatus: notified,
          ),
        );
        await _save();
      }
      if (!mounted) return;
      setState(() {
        restored = true;
        message =
            'Enter product details to request activation, or review your saved requests below.';
      });
      await _refresh();
      try {
        final initial = await deviceChannel.invokeMapMethod<String, dynamic>(
          'getActivationNotification',
        );
        if (initial != null && mounted) _openNotification(initial);
      } on PlatformException catch (_) {
        // Notification navigation is optional; saved requests remain available.
      } on MissingPluginException catch (_) {
        // Allows the request screen to be previewed outside Android.
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              message =
                  'Could not load saved requests. Close and reopen the app to try again.',
        );
      }
    }
  }

  Future<void> _save() => storage.write(
    key: 'activationRequests',
    value: jsonEncode(requests.map((row) => row.toJson()).toList()),
  );

  void _scheduleRefresh() {
    pollTimer?.cancel();
    if (mounted && foreground && restored) {
      pollTimer = Timer(const Duration(seconds: 15), _refresh);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    pollTimer?.cancel();
    if (foreground && restored) _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted || !restored || !foreground || busy || refreshing) return;
    pollTimer?.cancel();
    setState(() => refreshing = true);
    var failed = false;
    try {
      for (var index = 0; index < requests.length; index++) {
        if (!mounted || !foreground) break;
        final previous = requests[index];
        try {
          final response = await api.getActivationStatus(
            previous.productId,
            previous.productCode,
          );
          if (!mounted) return;
          if (response['success'] != true || response['data'] is! Map) {
            failed = true;
            continue;
          }
          final data = Map<String, dynamic>.from(response['data'] as Map);
          var next = previous.updated(data);
          final changed =
              next.status.toLowerCase() != previous.status.toLowerCase();
          if (changed &&
              next.notifiedStatus?.toLowerCase() != next.status.toLowerCase()) {
            _showUpdate(next);
            try {
              await api.showNotification(
                'Activation ${next.status.toLowerCase()}',
                'Your ${next.productCode} activation request is ${next.status}.',
                status: next.status,
                productId: next.productId,
                productCode: next.productCode,
              );
              next = next.updated(data, notified: next.status);
            } catch (_) {
              // Denied notification permission must not prevent status updates.
            }
          }
          requests[index] = next;
        } catch (_) {
          failed = true;
        }
      }
      await _save();
      if (mounted) {
        setState(
          () =>
              message =
                  failed
                      ? 'Some requests could not be refreshed. Showing saved statuses; retrying automatically.'
                      : 'Request statuses are up to date.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              message =
                  'Could not save the latest statuses. Your saved requests have been kept.',
        );
      }
    } finally {
      if (mounted) setState(() => refreshing = false);
      _scheduleRefresh();
    }
  }

  Future<void> _requestActivation() async {
    final id = int.tryParse(productId.text.trim());
    final code = product.text.trim();
    if (id == null || id <= 0 || code.isEmpty) {
      setState(() => message = 'Enter a valid product ID and product code.');
      return;
    }
    pollTimer?.cancel();
    setState(() => busy = true);
    try {
      final result = await api.requestActivation(id, code);
      if (result['success'] != true || result['data'] is! Map) {
        if (mounted) {
          setState(
            () =>
                message =
                    result['message']?.toString() ??
                    'The activation request could not be submitted.',
          );
        }
        return;
      }
      final data = Map<String, dynamic>.from(result['data'] as Map);
      final request = SavedActivationRequest(
        productId: id,
        productCode: code,
        status: 'Pending',
      ).updated(data);
      final index = requests.indexWhere((row) => row.key == request.key);
      if (index < 0) {
        requests.insert(0, request);
      } else {
        requests[index] = request;
      }
      await _save();
      await storage.write(key: 'productCode', value: code);
      await storage.write(key: 'productId', value: id.toString());
      if (mounted) {
        setState(() {
          selectedStatus =
              statuses.contains(request.status) ? request.status : 'All';
          message =
              result['message']?.toString() ?? 'Activation request submitted.';
        });
        _scrollToRequests();
      }
    } catch (error) {
      if (mounted) setState(() => message = _errorMessage(error));
    } finally {
      if (mounted) setState(() => busy = false);
      _scheduleRefresh();
    }
  }

  String _errorMessage(Object error) {
    if (error is DioException) {
      final response = error.response?.data;
      final serverMessage =
          response is Map ? response['message']?.toString() : null;
      if (serverMessage != null && serverMessage.isNotEmpty) {
        return serverMessage;
      }
    }
    return 'Request failed. Check the API address and network connection.';
  }

  void _scrollToRequests() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = listKey.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
  }

  void _openNotification(Map<String, dynamic> data) {
    if (!mounted) return;
    final status = data['status']?.toString() ?? 'Pending';
    setState(() => selectedStatus = statuses.contains(status) ? status : 'All');
    _scrollToRequests();
  }

  void _showUpdate(SavedActivationRequest request) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${request.productCode}: ${request.status}'),
        action: SnackBarAction(
          label: 'Review',
          onPressed: () => _openNotification({'status': request.status}),
        ),
      ),
    );
  }

  String _date(DateTime? value) =>
      value == null ? '—' : value.toLocal().toString().split('.').first;

  void _details(SavedActivationRequest request) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Activation request',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Text('Product: ${request.productCode}'),
                  Text('Product ID: ${request.productId}'),
                  Text('Request ID: ${request.activationId ?? '—'}'),
                  Text('Status: ${request.status}'),
                  Text('Active: ${request.isActive ? 'Yes' : 'No'}'),
                  Text('Requested: ${_date(request.requestDate)}'),
                  Text('Installed: ${_date(request.installationDate)}'),
                  if (request.reason.isNotEmpty)
                    Text('Reason: ${request.reason}'),
                  const SizedBox(height: 16),
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
    );
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    deviceChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    product.dispose();
    productId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        requests
            .where(
              (row) => selectedStatus == 'All' || row.status == selectedStatus,
            )
            .toList();
    final pendingCount =
        requests.where((row) => row.status == 'Pending').length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activate device'),
        actions: [
          IconButton(
            tooltip: '$pendingCount pending activation requests',
            onPressed: () => _openNotification({'status': 'Pending'}),
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Refresh requests',
            onPressed: busy || refreshing || !restored ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const Icon(Icons.verified_user_outlined, size: 42),
                const SizedBox(height: 12),
                Text(
                  'Activate your product',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(message),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: product,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Product code',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: productId,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Product ID',
                    prefixIcon: Icon(Icons.tag_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed:
                      busy || refreshing || !restored
                          ? null
                          : _requestActivation,
                  icon: const Icon(Icons.send),
                  label: Text(busy ? 'Please wait…' : 'Request activation'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Your activation requests',
                  key: listKey,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Saved requests from this device. Statuses refresh automatically while the app is open.',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      statuses
                          .map(
                            (status) => ChoiceChip(
                              label: Text(
                                '$status (${requests.where((row) => status == 'All' || row.status == status).length})',
                              ),
                              selected: selectedStatus == status,
                              onSelected:
                                  (_) =>
                                      setState(() => selectedStatus = status),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 12),
                Text(
                  'Showing ${visible.length} of ${requests.length} requests',
                ),
                if (refreshing)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                const SizedBox(height: 8),
                if (visible.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        selectedStatus == 'All'
                            ? 'No saved activation requests yet.'
                            : 'No ${selectedStatus.toLowerCase()} activation requests.',
                      ),
                    ),
                  ),
                ...visible.map(
                  (request) => Card(
                    child: ListTile(
                      isThreeLine: true,
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(request.productCode),
                      subtitle: Text(
                        '${request.status} · Request #${request.activationId ?? '—'}\n${_date(request.requestDate)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _details(request),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
