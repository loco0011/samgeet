/// The looks the full-screen player can wear. Picked after signing in, or in Settings.
enum PlayerStyle {
  disc('disc', 'Disc', 'The spinning record with the seek ring. The original.'),
  cover('cover', 'Cover', 'Big square artwork and a classic progress bar.'),
  immersive('immersive', 'Immersive', 'The album art fills the screen behind frosted controls.'),
  minimal('minimal', 'Minimal', 'Big type, a slim timeline, nothing in the way.');

  final String id;
  final String label;
  final String description;
  const PlayerStyle(this.id, this.label, this.description);

  static PlayerStyle byId(String? id) => values.firstWhere((s) => s.id == id, orElse: () => disc);
}
