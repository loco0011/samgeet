import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_info.dart';
import '../../data/analytics.dart';
import '../../data/app_config.dart';
import '../../data/update_service.dart';
import '../mood_theme.dart';
import '../nav.dart';
import '../theme.dart';
import 'fancy_dialog.dart';

/// Looks for a newer version and, if there is one, shows the update popup.
/// [manual] (the About screen's button) also reports "you're up to date". Returns whether the popup showed.
/// True while the update popup is on screen, so returning to the app doesn't stack a second one.
bool _updateShowing = false;

Future<bool> checkForUpdate(BuildContext context, {bool manual = false}) async {
  if (_updateShowing) return true;
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
  _updateShowing = true;
  try {
    await showUpdateDialog(context, update, service);
  } finally {
    _updateShowing = false;
  }
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
        tone: FancyTone.celebrate,
        badge: '$kVersionName  →  ${u.version}$size',
        title: u.required ? 'Update to keep listening' : 'Samgeet ${u.version} is here',
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (u.highlights.isNotEmpty) ...[
            HighlightList(highlights: u.highlights.take(6).toList()),
            const SizedBox(height: 14),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(u.required ? 'This version needs an update to keep working.' : 'A new version is ready to install.'),
            ),
          Row(children: [
            const Icon(Icons.verified_user_outlined, size: 15, color: AppColors.muted),
            const SizedBox(width: 6),
            const Expanded(child: Text('Your playlists, likes and settings stay as they are.', style: TextStyle(color: AppColors.muted, fontSize: 12))),
            if (u.notes.isNotEmpty)
              GestureDetector(
                onTap: () => showUpdateDetails(ctx, u.version, u.notes),
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('All the details', style: TextStyle(color: AppColors.pink, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ),
          ]),
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

/// The headlines of an update as icon tiles, one short line each.
class HighlightList extends StatelessWidget {
  final List<Highlight> highlights;
  const HighlightList({super.key, required this.highlights});

  @override
  Widget build(BuildContext context) {
    final accent = moodPalette(context).accent;
    return Column(children: [
      for (var i = 0; i < highlights.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(colors: [accent.withValues(alpha: 0.32), accent.withValues(alpha: 0.12)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: highlights[i].icon.isEmpty
                  ? Icon(Icons.auto_awesome_rounded, size: 18, color: moodPalette(context).light)
                  : Text(highlights[i].icon, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(highlights[i].title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Colors.white))),
          ]),
        ),
    ]);
  }
}

/// The full release notes, from the popup's "All the details" or the About screen.
Future<void> showUpdateDetails(BuildContext context, String version, String notes) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('What\'s new in $version', style: const TextStyle(fontFamily: kDisplay, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              const SizedBox(height: 14),
              Text(notes, style: const TextStyle(height: 1.6, fontSize: 14, color: Color(0xFFD9D9E6))),
            ]),
          ),
        ),
      ),
    );

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
