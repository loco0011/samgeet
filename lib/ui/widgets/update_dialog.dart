import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_info.dart';
import '../../data/analytics.dart';
import '../../data/app_config.dart';
import '../../data/update_service.dart';
import '../nav.dart';
import '../theme.dart';
import 'fancy_dialog.dart';

/// Looks for a newer version and, if there is one, shows the update popup.
/// [manual] (the About screen's button) also reports "you're up to date". Returns whether the popup showed.
Future<bool> checkForUpdate(BuildContext context, {bool manual = false}) async {
  // Updates are APK downloads, which only Android can install.
  if (!Platform.isAndroid) {
    if (manual) toast(context, 'You have version $kVersionName');
    return false;
  }
  final service = UpdateService(config: context.read<AppConfig>());
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
  final analytics = context.read<Analytics>();
  analytics.log('update_open', value: u.version, meta: {'required': u.required, 'step': 'shown'});

  Future<void> download(BuildContext ctx) async {
    analytics.log('update_open', value: u.version, meta: {'step': 'download'});
    final ok = await launchUrl(Uri.parse(u.downloadUrl), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && ctx.mounted) toast(ctx, 'Couldn\'t open the download. Try again in a moment.');
    if (ok && !u.required && ctx.mounted) Navigator.of(ctx).pop();
  }

  final size = u.sizeBytes == null ? '' : ' · ${(u.sizeBytes! / 1048576).toStringAsFixed(0)} MB';
  return showFancy<void>(
    context,
    dismissible: !u.required,
    Builder(
      builder: (ctx) => FancyDialog(
        icon: Icons.rocket_launch_rounded,
        tone: u.required ? FancyTone.warning : FancyTone.celebrate,
        badge: '$kVersionName  →  ${u.version}$size',
        title: u.required ? 'Update needed to keep listening' : 'A fresh Samgeet is here',
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(u.required
              ? 'This version stops working soon. Updating takes a minute, and your playlists, likes and settings stay as they are.'
              : 'Samgeet ${u.version} is ready to install. Your playlists, likes and settings stay as they are.'),
          if (u.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("WHAT'S NEW", style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: AppColors.muted)),
                const SizedBox(height: 8),
                Text(u.notes, style: const TextStyle(fontSize: 13.5, height: 1.5)),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          const Text('Android may ask you to allow installs from your browser the first time.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
        primaryLabel: 'Download update',
        primaryIcon: Icons.download_rounded,
        onPrimary: () => download(ctx),
        onClose: u.required ? null : () => Navigator.of(ctx).pop(),
        secondary: [
          if (!u.required) ...[
            TextButton(
              onPressed: () {
                analytics.log('update_later', value: u.version);
                Navigator.of(ctx).pop();
              },
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () {
                analytics.log('update_later', value: u.version, meta: {'skip': true});
                service.skip(u.version);
                Navigator.of(ctx).pop();
              },
              child: const Text('Skip this version', style: TextStyle(color: AppColors.muted)),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Shows a message sent from the admin panel. [onAction] runs its button's action (opening the
/// update, a link, or a search); the server hears whether it was opened or dismissed.
Future<void> showAnnouncement(BuildContext context, Announcement a, {required Future<void> Function(Announcement) onAction}) {
  final config = context.read<AppConfig>();
  var handled = false;
  void close(BuildContext ctx, {required bool opened}) {
    if (handled) return;
    handled = true;
    config.closed(a, opened: opened);
    Navigator.of(ctx).pop();
  }

  return showFancy<void>(
    context,
    Builder(
      builder: (ctx) => PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop && !handled) {
            handled = true;
            config.closed(a, opened: false);
          }
        },
        child: FancyDialog(
          icon: switch (a.style) {
            'celebrate' => Icons.celebration_rounded,
            'warning' => Icons.campaign_rounded,
            _ => Icons.notifications_active_rounded,
          },
          tone: switch (a.style) {
            'celebrate' => FancyTone.celebrate,
            'warning' => FancyTone.warning,
            _ => FancyTone.info,
          },
          imageUrl: a.image,
          badge: 'FROM SAMGEET',
          title: a.title,
          body: Text(a.body),
          primaryLabel: a.buttonLabel,
          primaryIcon: switch (a.action) {
            'update' => Icons.download_rounded,
            'url' => Icons.open_in_new_rounded,
            'search' => Icons.search_rounded,
            _ => Icons.check_rounded,
          },
          onPrimary: () {
            close(ctx, opened: true); // pressing the main button counts as opened, link or not
            if (a.action != 'none') onAction(a);
          },
          onClose: () => close(ctx, opened: false),
        ),
      ),
    ),
  );
}
