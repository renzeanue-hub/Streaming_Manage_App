enum StreamCategory {
  game,
  singing,
  chat,
  collab,
  other,
}

extension StreamCategoryX on StreamCategory {
  String get label => switch (this) {
        StreamCategory.game => 'ゲーム実況',
        StreamCategory.singing => '歌枠',
        StreamCategory.chat => '雑談',
        StreamCategory.collab => 'コラボ',
        StreamCategory.other => 'その他',
      };
}