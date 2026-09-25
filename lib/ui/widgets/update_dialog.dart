import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_info.dart';
import '../../data/update_service.dart';
import '../theme.dart';
import '../nav.dart';

/// Looks for a newer release and, if there is one, shows the update popup.
/// [manual] (the About screen's button) also reports "you're up to date". Returns whether the popup showed.
Future<bool> checkForUpdate(BuildContext context, {bool manual = false}) async {
  // Updates are APK downloads from GitHub, which only Android can install.
  if (!Platform.isAndroid) {
    if (manual) toast(context, 'You have version $kVersionName');
    return false;
  }
  final service = UpdateService();
  AppUpdate? update;
  try {
    update = await service.check(manual: manual);
  } catch (_) {
    if (manual && context.mounted) toast(context, 'Couldn\'t check for updates. Check your connection.');
    return false;
  }
  if (!context.mounted) return false;
  if (update == null) {
    if (manual) toast(context, 'You have the latest version ($kVersionName)');
    return false;
  }
  await showUpdateDialog(context, update, service);
  return true;
}

Future<void> showUpdateDialog(BuildContext context, AppUpdate u, UpdateService service) {
  Future<void> download(BuildContext ctx) async {
    final ok = await launchUrl(Uri.parse(u.downloadUrl), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && ctx.mounted) toast(ctx, 'Couldn\'t open the download. Visit the GitHub releases page instead.');
    if (ok && !u.required && ctx.mounted) Navigator.of(ctx).pop();
  }

  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: !u.required,
    builder: (ctx) => PopScope(
      canPop: !u.required,
      child: AlertDialog(
        icon: const Icon(Icons.system_update_rounded, size: 36, color: AppColors.pink),
        title: Text('Samgeet ${u.version} is available', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.4),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('You have $kVersionName.${u.required ? ' This update is required to keep using the app.' : ''}',
                  style: const TextStyle(color: AppColors.muted)),
              if (u.notes.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text("What's new", style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(u.notes, style: const TextStyle(height: 1.45)),
              ],
              const SizedBox(height: 14),
              const Text('Your playlists, likes and settings stay after updating.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ]),
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          if (!u.required)
            TextButton(
              onPressed: () {
                service.skip(u.version);
                Navigator.of(ctx).pop();
              },
              child: const Text('Skip this version', style: TextStyle(color: AppColors.muted)),
            ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (!u.required) TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Later')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
              onPressed: () => download(ctx),
              child: const Text('Download'),
            ),
          ]),
        ],
      ),
    ),
  );
}
