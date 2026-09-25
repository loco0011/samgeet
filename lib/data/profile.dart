import 'device_snapshot.dart';

/// Who is listening, and what they told us they like.
///
/// The profile lives on this device and syncs with the account (see `SyncService`; the email,
/// stored lower-case, is part of the account key). It unlocks sharing and long playlists and
/// seeds the recommendations.
class Profile {
  final String name;
  final String email;
  final List<String> languages; // language ids, e.g. "bengali"
  final List<String> moods; // category ids, e.g. "romantic"
  final List<String> artists; // singer names
  final int createdAt;

  /// The profile picture, as one string: empty (show the initials), an icon id
  /// (see `kAvatarIcons`), `emoji:🎧`, or `photo:<file path>` for an uploaded image.
  final String avatar;
  static const emojiPrefix = 'emoji:';
  static const photoPrefix = 'photo:';

  /// File path of the uploaded photo, if the picture is one.
  String? get photoPath => avatar.startsWith(photoPrefix) ? avatar.substring(photoPrefix.length) : null;

  /// The listener agreed to share device details and approximate location.
  final bool shareDeviceInfo;
  final DeviceSnapshot? device; // only ever set while [shareDeviceInfo] is true

  const Profile({
    required this.name,
    this.email = '',
    this.languages = const [],
    this.moods = const [],
    this.artists = const [],
    required this.createdAt,
    this.avatar = '',
    this.shareDeviceInfo = false,
    this.device,
  });

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  Profile copyWith({String? name, String? email, List<String>? languages, List<String>? moods, List<String>? artists, String? avatar}) => Profile(
        name: name ?? this.name,
        email: email ?? this.email,
        languages: languages ?? this.languages,
        moods: moods ?? this.moods,
        artists: artists ?? this.artists,
        createdAt: createdAt,
        avatar: avatar ?? this.avatar,
        shareDeviceInfo: shareDeviceInfo,
        device: device,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'languages': languages,
        'moods': moods,
        'artists': artists,
        'createdAt': createdAt,
        'avatar': avatar,
        'shareDeviceInfo': shareDeviceInfo,
        'device': device?.toJson(),
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        name: '${j['name'] ?? ''}',
        email: '${j['email'] ?? ''}',
        languages: ((j['languages'] as List?) ?? const []).map((e) => '$e').toList(),
        moods: ((j['moods'] as List?) ?? const []).map((e) => '$e').toList(),
        artists: ((j['artists'] as List?) ?? const []).map((e) => '$e').toList(),
        createdAt: (j['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        avatar: '${j['avatar'] ?? ''}',
        shareDeviceInfo: j['shareDeviceInfo'] == true,
        device: j['device'] is Map ? DeviceSnapshot.fromJson(Map<String, dynamic>.from(j['device'] as Map)) : null,
      );
}
