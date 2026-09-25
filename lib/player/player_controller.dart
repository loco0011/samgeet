import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../data/library_store.dart';
import '../data/saavn_api.dart';
import '../data/track.dart';
import '../engine/recommendation_service.dart';
import '../engine/taste_profile.dart';
import 'audio_fx.dart';

/// Owns the queue and the audio player.
///
/// The queue order *is* the play order (shuffle re-orders the upcoming songs),
/// and when the queue runs low, "smart radio" tops it up with songs that match
/// the mood of what's playing.
class PlayerController extends ChangeNotifier {
  /// Equalizer and loudness boost, wired into [player]'s output.
  final AudioFx fx = AudioFx();
  late final AudioPlayer player = AudioPlayer(audioPipeline: fx.pipeline);
  final SaavnApi api;
  final LibraryStore library;
  final RecommendationService reco;

  PlayerController({required this.api, required this.library, required this.reco}) {
    _subs.add(player.currentIndexStream.listen(_onIndexChanged));
    _subs.add(player.positionStream.listen(_onPosition));
    _subs.add(player.playerStateStream.listen((s) {
      notifyListeners();
      _watchStall(s);
    }));
    _subs.add(player.playbackEventStream.listen((_) {}, onError: _onPlayerError));
    player.setLoopMode(LoopMode.off);
  }

  final List<Track> queue = [];
  final List<StreamSubscription> _subs = [];
  final StreamController<String> _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  int index = -1;
  bool shuffle = false;
  LoopMode loopMode = LoopMode.off;
  bool loadingMore = false;

  /// What started this session (a category query) — keeps refills on-theme.
  String? sessionContext;

  List<String> _origin = []; // ids in their un-shuffled order

  // Bumped whenever a new queue starts, so a radio refill still running for
  // the old queue can't append its songs to the new one.
  int _session = 0;
  int? _refillFor;
  final Set<String> _skipped = {};
  final Set<String> _retried = {};

  // Listening analytics for the current song.
  String? _curId;
  Duration _maxPos = Duration.zero;
  bool _historyLogged = false;

  // A song that never starts (missing file, dead link) is skipped after this long.
  static const _stallLimit = Duration(seconds: 10);
  Timer? _stallTimer;

  // Sleep timer
  Timer? _sleepTimer;
  DateTime? sleepEndsAt;
  bool sleepAtEndOfTrack = false;

  Track? get current => index >= 0 && index < queue.length ? queue[index] : null;
  bool get isPlaying => player.playing;
  List<Track> get upNext => index + 1 < queue.length ? queue.sublist(index + 1) : const [];
  bool get hasSleepTimer => sleepEndsAt != null || sleepAtEndOfTrack;

  void _toast(String m) => _messages.add(m);

  // ---------- building sources ----------
  AudioSource _source(Track t) => AudioSource.uri(
        Uri.parse(t.streamUrl(library.quality)),
        tag: MediaItem(
          id: t.id,
          title: t.title,
          artist: t.artistLine,
          album: t.album,
          artUri: t.image.isEmpty ? null : Uri.parse(t.art(500)),
          duration: t.durationSec > 0 ? t.duration : null,
        ),
      );

  /// Fetches stream URLs for any songs that don't have one yet.
  Future<List<Track>> _makePlayable(List<Track> tracks) async {
    final missing = tracks.where((t) => !t.isPlayable).map((t) => t.id).toList();
    if (missing.isNotEmpty) {
      try {
        final fresh = {for (final t in await api.details(missing)) t.id: t};
        tracks = [for (final t in tracks) t.isPlayable ? t : (fresh[t.id] != null ? t.copyWithUrl(fresh[t.id]!) : t)];
      } catch (_) {}
    }
    return tracks.where((t) => t.isPlayable).toList();
  }

  // ---------- starting playback ----------
  /// Plays [tracks] starting at [start]. If [shuffleOn] the rest is shuffled
  /// (the chosen song still plays first).
  Future<void> playTracks(List<Track> tracks, {int start = 0, String? context, bool shuffleOn = false}) async {
    if (tracks.isEmpty) return;
    final chosen = tracks[start.clamp(0, tracks.length - 1)];
    var list = await _makePlayable(tracks);
    if (list.isEmpty) {
      _toast('These songs can\'t be played right now');
      return;
    }
    var startIndex = list.indexWhere((t) => t.id == chosen.id);
    if (startIndex < 0) startIndex = 0;

    _origin = list.map((t) => t.id).toList();
    shuffle = shuffleOn;
    if (shuffleOn) {
      final first = list[startIndex];
      final rest = [...list]..removeAt(startIndex);
      rest.shuffle(math.Random());
      list = [first, ...rest];
      startIndex = 0;
    }

    _finalizeCurrent(); // credit the song we're leaving before the queue is replaced
    _session++;
    _curId = null;
    sessionContext = context;
    _skipped.clear();
    queue
      ..clear()
      ..addAll(list);
    index = startIndex;
    notifyListeners();

    try {
      await player.setAudioSources([for (final t in list) _source(t)], initialIndex: startIndex, initialPosition: Duration.zero);
      unawaited(player.play());
    } catch (e) {
      _toast('Couldn\'t start playback. Check your connection.');
    }
    unawaited(_maybeRefill());
  }

  /// Plays one song, then lets smart radio carry on in the same mood.
  Future<void> playSingle(Track t, {String? context}) => playTracks([t], context: context);

  Future<void> startRadio(Track seed) async {
    _toast('Starting radio for "${seed.title}"');
    final similar = await reco.similarTo(seed, take: 20);
    await playTracks([seed, ...similar]);
  }

  // ---------- transport ----------
  Future<void> togglePlay() async {
    if (player.playing) {
      await player.pause();
    } else {
      unawaited(player.play());
    }
  }

  Future<void> next() async {
    _markSkip();
    if (player.hasNext) {
      await player.seekToNext();
    } else if (queue.isNotEmpty) {
      await _maybeRefill(force: true);
      if (player.hasNext) await player.seekToNext();
    }
    if (!player.playing) unawaited(player.play());
  }

  Future<void> previous() async {
    if (player.position > const Duration(seconds: 4) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  Future<void> seek(Duration d) => player.seek(d);

  Future<void> jumpTo(int i) async {
    if (i < 0 || i >= queue.length) return;
    _markSkip();
    await player.seek(Duration.zero, index: i);
    if (!player.playing) unawaited(player.play());
  }

  Future<void> toggleLoop() async {
    loopMode = switch (loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await player.setLoopMode(loopMode);
    notifyListeners();
  }

  // ---------- queue editing ----------
  Future<void> _replaceUpcoming(List<Track> tracks) async {
    for (var i = queue.length - 1; i > index; i--) {
      await player.removeAudioSourceAt(i);
    }
    queue.removeRange(index + 1, queue.length);
    queue.addAll(tracks);
    if (tracks.isNotEmpty) await player.addAudioSources([for (final t in tracks) _source(t)]);
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    shuffle = !shuffle;
    notifyListeners();
    if (queue.length - index - 1 < 2) return;
    final upcoming = [...upNext];
    if (shuffle) {
      upcoming.shuffle(math.Random());
    } else {
      upcoming.sort((a, b) {
        final ia = _origin.indexOf(a.id), ib = _origin.indexOf(b.id);
        return (ia < 0 ? 1 << 20 : ia).compareTo(ib < 0 ? 1 << 20 : ib);
      });
    }
    await _replaceUpcoming(upcoming);
  }

  Future<void> playNext(Track t) async {
    final ready = await _makePlayable([t]);
    if (ready.isEmpty) return;
    if (queue.isEmpty) return playSingle(t);
    queue.insert(index + 1, ready.first);
    await player.insertAudioSource(index + 1, _source(ready.first));
    notifyListeners();
    _toast('Playing next: ${t.title}');
  }

  Future<void> addToQueue(Track t) async {
    final ready = await _makePlayable([t]);
    if (ready.isEmpty) return;
    if (queue.isEmpty) return playSingle(t);
    queue.add(ready.first);
    _origin.add(t.id);
    await player.addAudioSource(_source(ready.first));
    notifyListeners();
    _toast('Added to queue');
  }

  Future<void> removeFromQueue(int i) async {
    if (i <= index || i >= queue.length) return;
    queue.removeAt(i);
    await player.removeAudioSourceAt(i);
    notifyListeners();
  }

  Future<void> moveInQueue(int from, int to) async {
    if (from <= index || to <= index || from >= queue.length || to >= queue.length) return;
    final t = queue.removeAt(from);
    queue.insert(to, t);
    await player.moveAudioSource(from, to);
    notifyListeners();
  }

  // ---------- smart radio ----------
  Future<void> _maybeRefill({bool force = false}) async {
    if (queue.isEmpty || _refillFor == _session) return;
    if (!library.autoplay && !force) return;
    if (loopMode != LoopMode.off && !force) return;
    final remaining = queue.length - index - 1;
    if (remaining >= 3 && !force) return;

    final session = _session;
    _refillFor = session;
    loadingMore = true;
    notifyListeners();
    try {
      final tail = queue.last;
      final prev = queue.length > 1 ? queue[queue.length - 2] : null;
      final batch = await reco.nextBatch(
        seed: tail,
        previous: prev,
        exclude: queue.map((t) => t.id).toSet(),
        skipped: _skipped,
        contextQuery: sessionContext,
        take: 12,
      );
      final ready = await _makePlayable(batch);
      if (session != _session) return; // a different queue started meanwhile
      if (ready.isNotEmpty) {
        queue.addAll(ready);
        _origin.addAll(ready.map((t) => t.id));
        await player.addAudioSources([for (final t in ready) _source(t)]);
      }
    } catch (_) {
      // Radio is a bonus; never interrupt playback because it failed.
    } finally {
      if (_refillFor == session) {
        _refillFor = null;
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  // ---------- listening analytics ----------
  void _onIndexChanged(int? i) {
    _finalizeCurrent();
    index = i ?? -1;
    final t = current;
    _curId = t?.id;
    _maxPos = Duration.zero;
    _historyLogged = false;
    notifyListeners();
    _stallTimer?.cancel();
    _stallTimer = null;
    _watchStall(player.playerState);
    if (t != null) unawaited(_maybeRefill());
  }

  /// Starts a countdown while the current song is meant to be playing but is
  /// still loading; clears it as soon as audio is actually flowing or paused.
  void _watchStall(PlayerState s) {
    final waiting = s.playing && (s.processingState == ProcessingState.loading || s.processingState == ProcessingState.buffering);
    if (!waiting) {
      _stallTimer?.cancel();
      _stallTimer = null;
      return;
    }
    final id = _curId;
    _stallTimer ??= Timer(_stallLimit, () => _onStalled(id));
  }

  Future<void> _onStalled(String? id) async {
    _stallTimer = null;
    final t = current;
    if (t == null || t.id != id) return;
    final s = player.playerState;
    final waiting = s.playing && (s.processingState == ProcessingState.loading || s.processingState == ProcessingState.buffering);
    // Only songs that never began; a mid-song network dip shouldn't skip anything.
    if (!waiting || _maxPos > const Duration(seconds: 1)) return;
    _toast('Couldn\'t play "${t.title}". Skipping.');
    if (!player.hasNext) await _maybeRefill(force: true);
    if (player.hasNext) {
      await player.seekToNext();
      unawaited(player.play());
    } else {
      await player.pause();
    }
  }

  bool _userSkipped = false;
  void _markSkip() => _userSkipped = true;

  void _finalizeCurrent() {
    final id = _curId;
    if (id == null) return;
    final t = queue.where((x) => x.id == id).firstOrNull;
    if (t == null) return;
    final total = t.durationSec > 0 ? Duration(seconds: t.durationSec) : (player.duration ?? Duration.zero);
    final frac = total.inMilliseconds == 0 ? 0.0 : _maxPos.inMilliseconds / total.inMilliseconds;
    if (frac >= 0.7) {
      library.recordTaste(t, TasteEvent.completed);
    } else if (_userSkipped && _maxPos < const Duration(seconds: 25) && frac < 0.25) {
      library.recordTaste(t, TasteEvent.skipped);
      _skipped.add(t.id);
    } else if (frac >= 0.3) {
      library.recordTaste(t, TasteEvent.partial);
    }
    _userSkipped = false;
  }

  void _onPosition(Duration p) {
    if (p > _maxPos) _maxPos = p;
    final t = current;
    if (t == null) return;
    if (!_historyLogged && p > const Duration(seconds: 8)) {
      _historyLogged = true;
      library.addHistory(t);
    }
    if (sleepAtEndOfTrack) {
      final d = player.duration;
      if (d != null && d > Duration.zero && d - p < const Duration(milliseconds: 450)) {
        sleepAtEndOfTrack = false;
        player.pause();
        _toast('Sleep timer: playback stopped');
        notifyListeners();
      }
    }
  }

  // ---------- errors ----------
  Future<void> _onPlayerError(Object e, StackTrace st) async {
    final i = e is PlayerException ? (e.index ?? index) : index;
    if (i < 0 || i >= queue.length) return;
    final t = queue[i];

    // First try: the link may have gone stale — fetch a fresh one.
    if (_retried.add(t.id)) {
      try {
        final fresh = (await api.details([t.id])).firstOrNull;
        if (fresh != null && fresh.isPlayable) {
          final updated = t.copyWithUrl(fresh);
          queue[i] = updated;
          await player.removeAudioSourceAt(i);
          await player.insertAudioSource(i, _source(updated));
          if (i == index) {
            await player.seek(Duration.zero, index: i);
            unawaited(player.play());
          }
          return;
        }
      } catch (_) {}
    }
    _toast('Couldn\'t play "${t.title}". Skipping.');
    if (i == index && player.hasNext) {
      await player.seekToNext();
      unawaited(player.play());
    }
  }

  // ---------- quality ----------
  /// Re-applies the quality setting to everything after the current song.
  Future<void> refreshQuality() async {
    if (queue.isEmpty || index < 0) return;
    final upcoming = [...upNext];
    if (upcoming.isNotEmpty) await _replaceUpcoming(upcoming);
  }

  // ---------- sleep timer ----------
  void setSleepTimer(Duration d) {
    cancelSleepTimer();
    sleepEndsAt = DateTime.now().add(d);
    _sleepTimer = Timer(d, () {
      player.pause();
      sleepEndsAt = null;
      _toast('Sleep timer: playback stopped');
      notifyListeners();
    });
    notifyListeners();
  }

  void setSleepAtEndOfTrack() {
    cancelSleepTimer();
    sleepAtEndOfTrack = true;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepEndsAt = null;
    sleepAtEndOfTrack = false;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _sleepTimer?.cancel();
    _stallTimer?.cancel();
    _messages.close();
    player.dispose();
    fx.dispose();
    super.dispose();
  }
}
