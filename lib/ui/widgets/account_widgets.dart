import 'package:flutter/material.dart';

import '../../data/sync_service.dart';

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// One line on how syncing stands, shown under the account in Settings.
String syncStatusText(SyncService s) => switch (s.status) {
      SyncStatus.off => 'Not backed up. Tap Edit and add a password to keep your library safe.',
      SyncStatus.syncing => 'Syncing…',
      SyncStatus.offline => 'Will sync when you\'re online',
      SyncStatus.loggedOutElsewhere => 'Sync stopped. Sign out and sign in again.',
      SyncStatus.synced => s.lastSync == null ? 'Synced' : 'Synced ${_ago(s.lastSync!)}',
    };

/// A password box with a show/hide eye.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? error;
  final String? helper;
  final TextInputAction action;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.error,
    this.helper,
    this.action = TextInputAction.next,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: _hidden,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: widget.action,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: widget.error,
          helperText: widget.helper,
          helperMaxLines: 3,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            tooltip: _hidden ? 'Show' : 'Hide',
            icon: Icon(_hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded),
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        ),
      );
}
