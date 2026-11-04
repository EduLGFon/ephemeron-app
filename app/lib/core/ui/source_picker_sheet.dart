// Two-step source picker: choose an account, then one of its calendars or
// task lists. Returns the selected source id, or null for the allowed none
// option / dismissal.
import 'package:flutter/material.dart';

import 'app_sheet.dart';
import 'escape_to_close.dart';

class SourceOption {
  const SourceOption({
    required this.id,
    required this.name,
    this.account,
    this.isLocal = false,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String? account;
  final bool isLocal;
  final bool enabled;

  String get accountKey => isLocal || account == null ? '__local__' : account!;
  String get accountLabel =>
      isLocal || account == null ? 'On this device' : account!;
}

Future<String?> showSourcePickerSheet(
  BuildContext context, {
  required String title,
  required List<SourceOption> options,
  String? selectedId,
  bool allowNone = false,
  String noneLabel = 'No list',
}) {
  final enabled = options.where((o) => o.enabled).toList();
  return showAppSheet<String?>(
    context,
    builder: (_) => EscapeToClose(
      child: _SourcePicker(
        title: title,
        options: enabled,
        selectedId: selectedId,
        allowNone: allowNone,
        noneLabel: noneLabel,
      ),
    ),
  );
}

class _SourcePicker extends StatefulWidget {
  const _SourcePicker({
    required this.title,
    required this.options,
    required this.selectedId,
    required this.allowNone,
    required this.noneLabel,
  });

  final String title;
  final List<SourceOption> options;
  final String? selectedId;
  final bool allowNone;
  final String noneLabel;

  @override
  State<_SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends State<_SourcePicker> {
  String? _account;

  List<String> get _accounts {
    final keys = <String>[];
    for (final option in widget.options) {
      if (!keys.contains(option.accountKey)) keys.add(option.accountKey);
    }
    return keys;
  }

  String _accountLabel(String key) {
    final option = widget.options.firstWhere((o) => o.accountKey == key);
    return option.accountLabel;
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    final account = _account;
    final visible = account == null
        ? const <SourceOption>[]
        : widget.options.where((o) => o.accountKey == account).toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  if (account != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back to accounts',
                      onPressed: () => setState(() => _account = null),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          account == null
                              ? 'Choose an account'
                              : _accountLabel(account),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: account == null
                  ? _AccountList(
                      accounts: accounts,
                      labelOf: _accountLabel,
                      allowNone: widget.allowNone,
                      noneLabel: widget.noneLabel,
                      onNone: () => Navigator.of(context).pop(null),
                      onSelected: (key) => setState(() => _account = key),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final option in visible)
                          ListTile(
                            key: ValueKey('source-option-${option.id}'),
                            title: Text(option.name),
                            subtitle: option.isLocal
                                ? const Text('Local')
                                : null,
                            trailing: option.id == widget.selectedId
                                ? const Icon(Icons.check)
                                : const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).pop(option.id),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountList extends StatelessWidget {
  const _AccountList({
    required this.accounts,
    required this.labelOf,
    required this.allowNone,
    required this.noneLabel,
    required this.onNone,
    required this.onSelected,
  });

  final List<String> accounts;
  final String Function(String) labelOf;
  final bool allowNone;
  final String noneLabel;
  final VoidCallback onNone;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No sources available.'),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        if (allowNone)
          ListTile(
            leading: const Icon(Icons.inbox_outlined),
            title: Text(noneLabel),
            onTap: onNone,
          ),
        for (final account in accounts)
          ListTile(
            key: ValueKey('source-account-$account'),
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(labelOf(account)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onSelected(account),
          ),
      ],
    );
  }
}
