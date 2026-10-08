import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_session.dart';
import 'ui_helpers.dart';

class RecordEditor extends StatefulWidget {
  const RecordEditor({
    super.key,
    required this.session,
    required this.kind,
    this.record,
    this.users = const [],
    this.products = const [],
  });
  final AuthSession session;
  final String kind;
  final Map<String, dynamic>? record;
  final List<Map<String, dynamic>> users, products;
  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  final form = GlobalKey<FormState>();
  final controllers = <String, TextEditingController>{};
  final permissions = <String, bool>{};
  static const permissionNames = [
    'canLogin',
    'canAddUser',
    'canEditUser',
    'canDeleteUser',
    'canViewProduct',
    'canAddProduct',
    'canEditProduct',
    'canDeleteProduct',
    'canAssignProduct',
    'canActivation',
  ];
  String userType = 'User';
  int? userId, productId;
  bool saving = false;
  String? error;
  bool get editing => widget.record != null;
  @override
  void initState() {
    super.initState();
    final r = widget.record ?? {};
    for (final key in [
      'userName',
      'fullName',
      'email',
      'mobileNo',
      'authenticationCode',
      'password',
      'productCode',
      'productName',
      'description',
      'version',
      'startDate',
      'expiryDate',
    ]) {
      var value = field(r, key)?.toString() ?? '';
      if (key.endsWith('Date') && value.length >= 10) {
        value = value.substring(0, 10);
      }
      controllers[key] = TextEditingController(text: value);
    }
    userType = field(r, 'userType')?.toString() ?? 'User';
    userId = field(r, 'userID') as int?;
    productId = field(r, 'productID') as int?;
    if (!widget.users.any(
      (r) => field(r, 'userId') == userId && field(r, 'isActive') == true,
    )) {
      userId = null;
    }
    if (!widget.products.any(
      (r) => field(r, 'productID') == productId && field(r, 'isActive') == true,
    )) {
      productId = null;
    }
    final p = mapOf(field(r, 'permissions'));
    for (final name in permissionNames) {
      permissions[name] =
          field(p, name) as bool? ??
          (name == 'canLogin' || name == 'canViewProduct');
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget input(
    String key,
    String label, {
    bool required = false,
    int? max,
    bool secret = false,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controllers[key],
      enabled: !saving,
      obscureText: secret,
      maxLength: max,
      keyboardType:
          numeric
              ? TextInputType.number
              : key == 'email'
              ? TextInputType.emailAddress
              : TextInputType.text,
      inputFormatters:
          numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(labelText: label, counterText: ''),
      validator: (v) {
        if (required && (v ?? '').trim().isEmpty) return 'Please enter $label';
        if (secret && (v ?? '').isNotEmpty && v!.length < 8) {
          return 'Use at least 8 characters';
        }
        if (key == 'email' &&
            (v ?? '').isNotEmpty &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v!)) {
          return 'Enter a valid email';
        }
        return null;
      },
    ),
  );
  Widget date(String key, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controllers[key],
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today_outlined),
        suffixIcon: IconButton(
          onPressed: saving ? null : () => controllers[key]!.clear(),
          icon: const Icon(Icons.clear),
        ),
      ),
      onTap:
          saving
              ? null
              : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate:
                      DateTime.tryParse(controllers[key]!.text) ??
                      DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  controllers[key]!.text = picked.toIso8601String().substring(
                    0,
                    10,
                  );
                }
              },
    ),
  );
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final values = {
        for (final e in controllers.entries) e.key: e.value.text.trim(),
      };
      final Map<String, dynamic> body;
      String path;
      if (widget.kind == 'users') {
        body = {
          for (final key in [
            'userName',
            'fullName',
            'email',
            'mobileNo',
            'password',
            'authenticationCode',
          ])
            key: values[key],
          'userType': userType,
          'permissions': permissions,
        };
        if (editing && values['password']!.isEmpty) body.remove('password');
        if (editing && values['authenticationCode']!.isEmpty) {
          body.remove('authenticationCode');
        }
        path = '/users';
      } else if (widget.kind == 'products') {
        body = {
          for (final key in [
            'productCode',
            'productName',
            'description',
            'version',
          ])
            key: values[key],
          'isActive': true,
        };
        path = '/products';
      } else {
        final start = DateTime.tryParse(values['startDate']!);
        final end = DateTime.tryParse(values['expiryDate']!);
        if (start != null && end != null && end.isBefore(start)) {
          throw const ApiFailure('Expiry date must be on or after start date.');
        }
        body = {
          'userID': userId,
          'productID': productId,
          'startDate': start?.toIso8601String(),
          'expiryDate': end?.toIso8601String(),
        };
        path = '/productassignments';
      }
      final id = field(
        widget.record ?? {},
        widget.kind == 'users'
            ? 'userId'
            : widget.kind == 'products'
            ? 'productID'
            : 'productAssignID',
      );
      await widget.session.request(
        editing ? 'PUT' : 'POST',
        editing ? '$path/$id' : path,
        data: body,
      );
      if (editing && widget.kind == 'users') {
        try {
          await widget.session.request(
            'PUT',
            '$path/$id/permissions',
            data: permissions,
          );
        } catch (e) {
          throw ApiFailure(
            'User details saved, but permissions were not saved: $e',
          );
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          '${editing ? 'Edit' : 'Add'} ${widget.kind == 'assignments'
              ? 'assignment'
              : widget.kind == 'users'
              ? 'user'
              : 'product'}',
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: FilledButton.icon(
            onPressed: saving ? null : save,
            icon: const Icon(Icons.check_rounded),
            label: Text(saving ? 'Saving…' : 'Save changes'),
          ),
        ),
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.kind == 'users') ...[
              input('userName', 'Username', required: true, max: 100),
              input('fullName', 'Full name', required: true, max: 200),
              input('email', 'Email', max: 256),
              input('mobileNo', 'Mobile number', max: 40),
              input(
                'authenticationCode',
                'Authentication code',
                required: !editing,
                numeric: true,
                max: 64,
              ),
              if (editing)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Leave password or authentication code blank to keep the current value.',
                  ),
                ),
              input('password', 'Password', required: !editing, secret: true),
              DropdownButtonFormField<String>(
                value: userType,
                items:
                    ['User', 'Admin']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                onChanged: saving ? null : (v) => setState(() => userType = v!),
                decoration: const InputDecoration(labelText: 'Account type'),
              ),
              const SizedBox(height: 16),
              const Text('Permissions'),
              ...permissionNames.map(
                (name) => CheckboxListTile(
                  title: Text(labelOf(name)),
                  value: permissions[name],
                  onChanged:
                      saving
                          ? null
                          : (v) => setState(() => permissions[name] = v!),
                ),
              ),
            ],
            if (widget.kind == 'products') ...[
              input('productCode', 'Product code', required: true, max: 100),
              input('productName', 'Product name', required: true, max: 200),
              input('description', 'Description', max: 1000),
              input('version', 'Version', max: 50),
            ],
            if (widget.kind == 'assignments') ...[
              DropdownButtonFormField<int>(
                value: userId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'User'),
                validator: (v) => v == null ? 'Select an active user' : null,
                items:
                    widget.users
                        .where((r) => field(r, 'isActive') == true)
                        .map(
                          (r) => DropdownMenuItem<int>(
                            value: field(r, 'userId') as int,
                            child: Text('${field(r, 'userName')}'),
                          ),
                        )
                        .toList(),
                onChanged: saving ? null : (v) => setState(() => userId = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: productId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Product'),
                validator: (v) => v == null ? 'Select an active product' : null,
                items:
                    widget.products
                        .where((r) => field(r, 'isActive') == true)
                        .map(
                          (r) => DropdownMenuItem<int>(
                            value: field(r, 'productID') as int,
                            child: Text(
                              '${field(r, 'productName')} (${field(r, 'productCode')})',
                            ),
                          ),
                        )
                        .toList(),
                onChanged: saving ? null : (v) => setState(() => productId = v),
              ),
              const SizedBox(height: 16),
              date('startDate', 'Start date'),
              date('expiryDate', 'Expiry date'),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
