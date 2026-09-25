import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/sync_service.dart';
import 'data/cloud_service.dart';
import 'data/library_store.dart';
import 'data/saavn_api.dart';
import 'engine/recommendation_service.dart';
import 'player/player_controller.dart';
import 'ui/shell.dart';
import 'ui/mood_theme.dart';
import 'ui/theme.dart';
import 'ui/widgets/aurora.dart';
import 'ui/widgets/dominant_color.dart';

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
  library.cloud = CloudService(prefs);
  final sync = library.sync = SyncService(prefs)..beforeSnapshot = library.flush;
  unawaited(library.cloud!.retryPending(library.profile));
  final api = SaavnApi();
  final reco = RecommendationService(api, library);
  final player = PlayerController(api: api, library: library, reco: reco);
  final mood = MoodController(player, library);
  sync.onRemoteApplied = () async {
    library.reload();
    await player.fx.reload();
  };
  unawaited(sync.start());

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(SamgeetApp(api: api, library: library, reco: reco, player: player, mood: mood, sync: sync));
}

class SamgeetApp extends StatelessWidget {
  final SaavnApi api;
  final LibraryStore library;
  final RecommendationService reco;
  final PlayerController player;
  final MoodController mood;
  final SyncService sync;

  const SamgeetApp({super.key, required this.api, required this.library, required this.reco, required this.player, required this.mood, required this.sync});

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
                child: child!,
              ),
            ),
          );
        },
        home: const AppShell(),
      ),
    );
  }
}
