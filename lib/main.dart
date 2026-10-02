import 'dart:async';

import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/analytics.dart';
import 'data/api_client.dart';
import 'data/app_config.dart';
import 'data/share_service.dart';
import 'data/sync_service.dart';
import 'data/cloud_service.dart';
import 'data/download_service.dart';
import 'data/library_store.dart';
import 'data/saavn_api.dart';
import 'engine/recommendation_service.dart';
import 'player/player_controller.dart';
import 'ui/shell.dart';
import 'ui/mood_theme.dart';
import 'ui/theme.dart';
import 'ui/widgets/aurora.dart';
import 'ui/widgets/dominant_color.dart';
import 'ui/widgets/launch_splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bundled fonts are under the SIL Open Font License; list them on the licences page.
  LicenseRegistry.addLicense(() async* {
    const ofl = 'This Font Software is licensed under the SIL Open Font License, Version 1.1.\n'
        'The licence and FAQ are available at https://openfontlicense.org';
    yield const LicenseEntryWithLineBreaks(['Sora (font)'], 'Copyright The Sora Project Authors.\n\n$ofl');
    yield const LicenseEntryWithLineBreaks(['Plus Jakarta Sans (font)'], 'Copyright The Plus Jakarta Sans Project Authors.\n\n$ofl');
  });

  // Background playback + lock-screen / notification controls.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'app.samgeet.music.playback',
    androidNotificationChannelName: 'Samgeet playback',
    androidNotificationIcon: 'drawable/ic_notification',
    androidNotificationOngoing: true,
    notificationColor: AppColors.pink,
  );
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  final library = await LibraryStore.load();
  final prefs = await SharedPreferences.getInstance();
  // Samgeet's own server: one signed client shared by sync, profile, listening data and messages.
  final server = ApiClient(prefs);
  final analytics = library.analytics = Analytics(prefs, server);
  ShareService.api = server;
  ShareService.analytics = analytics;
  library.cloud = CloudService(prefs, server);
  final sync = library.sync = SyncService(prefs, api: server)..beforeSnapshot = library.flush;
  unawaited(library.cloud!.retryPending(library.profile, playerStyle: library.playerStyle.id));
  final api = SaavnApi();
  final downloads = DownloadService(prefs, api)..analytics = analytics;
  await downloads.init();
  final config = AppConfig(prefs, server, analytics: analytics);
  final reco = RecommendationService(api, library);
  final player = PlayerController(api: api, library: library, reco: reco, downloads: downloads);
  final mood = MoodController(player, library);
  sync.onRemoteApplied = () async {
    library.reload();
    await player.fx.reload();
  };
  unawaited(sync.start());
  analytics.start();
  unawaited(config.start());

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // The launch animation picks up from Android's own splash, whose logo size depends on the version.
  var sdk = 31;
  if (Platform.isAndroid) {
    try {
      sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    } catch (_) {}
  }

  runApp(SamgeetApp(
    api: api,
    library: library,
    reco: reco,
    player: player,
    mood: mood,
    sync: sync,
    downloads: downloads,
    analytics: analytics,
    config: config,
    androidSdk: sdk,
  ));
}

class SamgeetApp extends StatelessWidget {
  final SaavnApi api;
  final LibraryStore library;
  final RecommendationService reco;
  final PlayerController player;
  final MoodController mood;
  final SyncService sync;
  final DownloadService downloads;
  final Analytics analytics;
  final AppConfig config;
  final int androidSdk;

  const SamgeetApp({
    super.key,
    required this.api,
    required this.library,
    required this.reco,
    required this.player,
    required this.mood,
    required this.sync,
    required this.downloads,
    required this.analytics,
    required this.config,
    this.androidSdk = 31,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SaavnApi>.value(value: api),
        Provider<RecommendationService>.value(value: reco),
        ChangeNotifierProvider<LibraryStore>.value(value: library),
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<MoodController>.value(value: mood),
        ChangeNotifierProvider<SyncService>.value(value: sync),
        ChangeNotifierProvider<DownloadService>.value(value: downloads),
        Provider<Analytics>.value(value: analytics),
        ChangeNotifierProvider<AppConfig>.value(value: config),
      ],
      child: MaterialApp(
        title: 'Samgeet',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        builder: (context, child) {
          // The whole app glows in the colour of the album that is playing. The
          // tree shape never changes, so the navigator below is never rebuilt.
          final art = context.select<PlayerController, String?>((p) => p.current?.art(150));
          final palette = context.select<MoodController, MoodPalette>((m) => m.palette);
          return DominantColorBuilder(
            url: art ?? '',
            builder: (_, color) => AuroraBackground(
              tint: art == null ? null : color,
              palette: palette,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: MediaQuery.textScalerOf(context).clamp(minScaleFactor: 0.85, maxScaleFactor: 1.25),
                ),
                child: LaunchSplash(androidSdk: androidSdk, child: child!),
              ),
            ),
          );
        },
        home: const AppShell(),
      ),
    );
  }
}
