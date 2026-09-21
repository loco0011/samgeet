import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/taste_profile.dart';
import 'cloud_service.dart';
import 'profile.dart';
import 'track.dart';

class UserPlaylist {
  final String id;
  String name;
  final List<Track> tracks;
  final int createdAt;
  UserPlaylist({required this.id, required this.name, List<Track>? tracks, int? createdAt})
      : tracks = tracks ?? [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  /// Up to four distinct covers for a collage.
  List<String> get covers => tracks.map((t) => t.image).where((s) => s.isNotEmpty).toSet().take(4).toList();

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'createdAt': createdAt, 'tracks': tracks.map((t) => t.toJson()).toList()};

  factory UserPlaylist.fromJson(Map<String, dynamic> j) => UserPlaylist(
        id: '${j['id']}',
        name: '${j['name']}',
        createdAt: (j['createdAt'] as num?)?.toInt(),
        tracks: ((j['tracks'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => Track.fromStored(Map<String, dynamic>.from(m)))
            .toList(),
      );
}

/// Everything the listener owns, saved on-device.
class LibraryStore extends ChangeNotifier {
  static const _maxHistory = 150;

  /// Guests can keep this many songs in a playlist. Signing in removes the cap.
  static const guestPlaylistLimit = 5;

  final SharedPreferences _prefs;
  LibraryStore._(this._prefs);

  final List<Track> favorites = [];
  final List<UserPlaylist> playlists = [];
  final List<Track> history = [];
  final List<ArtistRef> followedArtists = [];
  final List<String> recentSearches = [];
  TasteProfile taste = TasteProfile();

  // Settings
  AudioQuality quality = AudioQuality.high;
  bool autoplay = true;
  List<String> languages = ['hindi', 'bengali', 'english'];
  Profile? profile;

  /// Online copy of the profile. Left null in tests and when offline-only.
  CloudService? cloud;

  /// Which dark accent style the app wears when a song has no clear mood.
  String accent = 'ember';

  final Set<String> _favIds = {};
  final Set<String> _dirty = {};
  Timer? _saveTimer;

  static Future<LibraryStore> load() async {
    final s = LibraryStore._(await SharedPreferences.getInstance());
    s._read();
    return s;
  }

  // ---------- persistence ----------
  List<Map<String, dynamic>> _list(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    } catch (_) {
      return const [];
    }
  }

  void _read() {
    favorites.addAll(_list('favorites').map(Track.fromStored));
    _favIds.addAll(favorites.map((t) => t.id));
    playlists.addAll(_list('playlists').map(UserPlaylist.fromJson));
    history.addAll(_list('history').map(Track.fromStored));
    followedArtists.addAll(_list('artists').map(ArtistRef.fromJson));
    recentSearches.addAll(_prefs.getStringList('searches') ?? const []);
    try {
      final t = _prefs.getString('taste');
      if (t != null) taste = TasteProfile.fromJson(Map<String, dynamic>.from(jsonDecode(t)));
    } catch (_) {}
    quality = AudioQuality.values.firstWhere(
      (q) => q.kbps == (_prefs.getInt('quality') ?? 320),
      orElse: () => AudioQuality.high,
    );
    autoplay = _prefs.getBool('autoplay') ?? true;
    languages = _prefs.getStringList('languages') ?? languages;
    accent = _prefs.getString('accent') ?? 'ember';
    try {
      final p = _prefs.getString('profile');
      if (p != null) profile = Profile.fromJson(Map<String, dynamic>.from(jsonDecode(p)));
    } catch (_) {}
  }

  void _touch(String key) {
    _dirty.add(key);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    final keys = _dirty.toList();
    _dirty.clear();
    for (final k in keys) {
      switch (k) {
        case 'favorites':
          await _prefs.setString(k, jsonEncode(favorites.map((t) => t.toJson()).toList()));
        case 'playlists':
          await _prefs.setString(k, jsonEncode(playlists.map((p) => p.toJson()).toList()));
        case 'history':
          await _prefs.setString(k, jsonEncode(history.map((t) => t.toJson()).toList()));
        case 'artists':
          await _prefs.setString(k, jsonEncode(followedArtists.map((a) => a.toJson()).toList()));
        case 'searches':
          await _prefs.setStringList(k, recentSearches);
        case 'taste':
          await _prefs.setString(k, jsonEncode(taste.toJson()));
        case 'profile':
          if (profile == null) {
            await _prefs.remove(k);
          } else {
            await _prefs.setString(k, jsonEncode(profile!.toJson()));
          }
        case 'settings':
          await _prefs.setInt('quality', quality.kbps);
          await _prefs.setBool('autoplay', autoplay);
          await _prefs.setStringList('languages', languages);
          await _prefs.setString('accent', accent);
      }
    }
  }

  void _changed(String key) {
    _touch(key);
    notifyListeners();
  }

  // ---------- favourites ----------
  bool isFavorite(String id) => _favIds.contains(id);

  void toggleFavorite(Track t) {
    if (_favIds.remove(t.id)) {
      favorites.removeWhere((x) => x.id == t.id);
      taste.record(t, TasteEvent.unliked);
    } else {
      _favIds.add(t.id);
      favorites.insert(0, t);
      taste.record(t, TasteEvent.liked);
    }
    _touch('taste');
    _changed('favorites');
  }

  // ---------- playlists ----------
  UserPlaylist createPlaylist(String name, {List<Track> tracks = const []}) {
    final p = UserPlaylist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'My playlist' : name.trim(),
      tracks: [...tracks],
    );
    playlists.insert(0, p);
    _changed('playlists');
    return p;
  }

  void renamePlaylist(String id, String name) {
    final p = playlists.where((p) => p.id == id).firstOrNull;
    if (p == null || name.trim().isEmpty) return;
    p.name = name.trim();
    _changed('playlists');
  }

  void deletePlaylist(String id) {
    playlists.removeWhere((p) => p.id == id);
    _changed('playlists');
  }

  /// Returns how many songs were actually added (duplicates are skipped).
  int addToPlaylist(String id, Iterable<Track> tracks) {
    final p = playlists.where((p) => p.id == id).firstOrNull;
    if (p == null) return 0;
    var added = 0;
    for (final t in tracks) {
      if (p.tracks.any((x) => x.id == t.id)) continue;
      p.tracks.add(t);
      taste.record(t, TasteEvent.addedToPlaylist);
      added++;
    }
    if (added > 0) {
      _touch('taste');
      _changed('playlists');
    }
    return added;
  }

  void removeFromPlaylist(String id, String trackId) {
    final p = playlists.where((p) => p.id == id).firstOrNull;
    if (p == null) return;
    p.tracks.removeWhere((t) => t.id == trackId);
    _changed('playlists');
  }

  void reorderPlaylist(String id, int oldIndex, int newIndex) {
    final p = playlists.where((p) => p.id == id).firstOrNull;
    if (p == null) return;
    final t = p.tracks.removeAt(oldIndex);
    p.tracks.insert(newIndex, t);
    _changed('playlists');
  }

  // ---------- artists ----------
  bool isFollowing(ArtistRef a) => followedArtists.any((x) => x.id == a.id || x.name == a.name);

  void toggleFollow(ArtistRef a) {
    if (isFollowing(a)) {
      followedArtists.removeWhere((x) => x.id == a.id || x.name == a.name);
    } else {
      followedArtists.insert(0, a);
      taste.record(Track(id: 'artist:${a.id}', title: '', artists: [a]), TasteEvent.followedArtist);
      _touch('taste');
    }
    _changed('artists');
  }

  // ---------- history / taste ----------
  void addHistory(Track t) {
    history.removeWhere((x) => x.id == t.id);
    history.insert(0, t);
    if (history.length > _maxHistory) history.removeRange(_maxHistory, history.length);
    _changed('history');
  }

  void clearHistory() {
    history.clear();
    _changed('history');
  }

  void recordTaste(Track t, TasteEvent e) {
    taste.record(t, e);
    _touch('taste');
  }

  void resetTaste() {
    taste = TasteProfile();
    _changed('taste');
  }

  // ---------- search history ----------
  void addSearch(String q) {
    final s = q.trim();
    if (s.isEmpty) return;
    recentSearches.remove(s);
    recentSearches.insert(0, s);
    if (recentSearches.length > 12) recentSearches.removeLast();
    _changed('searches');
  }

  void clearSearches() {
    recentSearches.clear();
    _changed('searches');
  }

  // ---------- settings ----------
  void setQuality(AudioQuality q) {
    quality = q;
    _changed('settings');
  }

  void setAutoplay(bool v) {
    autoplay = v;
    _changed('settings');
  }

  // ---------- profile ----------
  bool get signedIn => profile != null;

  /// Can a playlist hold [count] songs? Guests are capped, signed-in users are not.
  bool canHold(int count) => signedIn || count <= guestPlaylistLimit;

  /// Saves the profile and tunes the recommendations to what the listener picked.
  void signIn(Profile p) {
    final first = profile == null;
    profile = p;
    if (p.languages.isNotEmpty) languages = [...p.languages];
    if (first) {
      for (final a in p.artists) {
        taste.record(Track(id: 'pref:$a', title: '', artists: [ArtistRef(id: '', name: a)]), TasteEvent.followedArtist);
      }
      for (final l in p.languages) {
        taste.record(Track(id: 'pref:lang:$l', title: '', language: l), TasteEvent.liked);
      }
      _touch('taste');
    }
    _touch('settings');
    _changed('profile');
    final c = cloud;
    if (c != null) unawaited(c.saveProfile(p));
  }

  void signOut() {
    final photo = profile?.photoPath; // the uploaded picture goes with the profile
    if (photo != null) File(photo).delete().catchError((_) => File(photo));
    profile = null;
    _changed('profile');
    final c = cloud;
    if (c != null) unawaited(c.deleteProfile()); // the server copy goes too
  }

  void setAccent(String id) {
    if (accent == id) return;
    accent = id;
    _changed('settings');
  }

  void setLanguages(List<String> l) {
    languages = l.isEmpty ? ['hindi'] : l;
    _changed('settings');
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    flush();
    super.dispose();
  }
}
