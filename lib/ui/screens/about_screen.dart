import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_info.dart';
import '../mood_theme.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

/// About Samgeet: who made it, the licence, the branding rule and the disclaimers.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) toast(context, 'Couldn\'t open the link. It has been copied instead.');
    if (!ok) await Clipboard.setData(ClipboardData(text: url));
  }

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);

    Widget card(IconData icon, String title, String body, {Widget? action}) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: GlassBox(
            radius: 22,
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 20, color: mood.light),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: const TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w800, fontSize: 15.5))),
              ]),
              const SizedBox(height: 10),
              Text(body, style: const TextStyle(color: AppColors.muted, height: 1.5, fontSize: 13.5)),
              if (action != null) ...[const SizedBox(height: 14), action],
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
        Center(
          child: Column(children: [
            Image.asset('assets/mark-chrome.webp', height: 120),
            const SizedBox(height: 16),
            GradientText(kAppName, gradient: mood.textGradient, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
            const SizedBox(height: 4),
            const Text('Version $kAppVersion', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 6),
            const Text('Ad-free music, open to everyone', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 26),
        card(
          Icons.person_rounded,
          'Created by $kAuthor',
          'Samgeet is an open-source app designed, built and maintained by $kAuthor.',
          action: Wrap(spacing: 10, runSpacing: 10, children: [
            Pressable(
              onTap: () => _open(context, kAuthorLinkedIn),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(gradient: mood.gradient, borderRadius: BorderRadius.circular(30)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.open_in_new_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Connect on LinkedIn', style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            Pressable(
              onTap: () => _open(context, kSourceCodeUrl),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), border: Border.all(color: mood.accent, width: 1.5)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.code_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('View on GitHub', style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ),
        card(
          Icons.code_rounded,
          'Open source · $kLicenseName',
          'The code is free to use, copy and modify under the $kLicenseName. The one condition: '
          'you must keep the copyright notice — $kCopyright — and credit the original author in any copy or fork.',
        ),
        card(
          Icons.verified_rounded,
          'Name and logo',
          'The "$kAppName" name and logo belong to $kAuthor and are not covered by the open-source licence. '
          'If you build your own version, please give it your own name and logo, and say it is based on '
          'Samgeet by $kAuthor. Please don\'t present this app, or a copy of it, as your own work.',
        ),
        card(
          Icons.music_note_rounded,
          'About the music',
          'Samgeet does not host or own any music. Songs are streamed from a third-party catalogue and belong to '
          'their artists, labels and rights holders. Samgeet is not affiliated with or endorsed by that service or any label. '
          'It is meant for personal, non-commercial listening — you are responsible for following the law and the terms of '
          'the service where you live. Availability and quality can change at any time.',
        ),
        card(
          Icons.lock_rounded,
          'Your data',
          'Your profile, playlists, favourites and listening history are stored on this phone only. '
          'Samgeet does not upload them anywhere.',
        ),
        card(
          Icons.gavel_rounded,
          'No warranty',
          'The app is provided "as is", without warranty of any kind. The author is not liable for any damage or loss arising from its use.',
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton.icon(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: kAppName,
              applicationVersion: kAppVersion,
              applicationIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.asset('assets/mark-chrome.webp', height: 56),
              ),
              applicationLegalese: '$kCopyright\nOpen source under the $kLicenseName.',
            ),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Open-source licences'),
          ),
        ),
        const SizedBox(height: 6),
        const Center(child: Text('$kCopyright · $kAppName', style: TextStyle(color: AppColors.muted, fontSize: 12))),
      ]),
    );
  }
}
