# Snap Store 掲載情報

対象: Prelis Desktop v0.1.2 / Snap 名 `prelis`

更新日: 2026-10-31。ユーザーから提示された Snap Store の正式フォームに沿った掲載用の入力内容です。Summary・Description は日本語にし、画像素材を用意しています。問い合わせ先などの既存入力値は提示内容を引き継ぎ、確認が必要な点を末尾に記載しています。

フォームの案内では、保存した変更は Snap の掲載ページに即時反映されます。

## Listing details

### Snap icon

フォーム上の表示名: `prelis icon`

アップロード用: [icon.png](icon.png)（512 × 512 px、PNG）。他ストアと同じブランド図案です。

### Title（必須）

```text
Prelis Desktop
```

### Category（必須）

```text
Utilities
```

追加カテゴリ: 未設定。

### Video

未設定。

### Images

次の順にアップロードします。

1. [screenshots/01-home.png](screenshots/01-home.png) — 日記・タイマー・パスワード生成を選ぶホーム
2. [screenshots/02-diary.png](screenshots/02-diary.png) — 日付選択・カレンダー・日記の入力欄
3. [screenshots/03-timer.png](screenshots/03-timer.png) — 残り時間・時間設定・終了音の選択
4. [screenshots/04-password.png](screenshots/04-password.png) — 文字種・文字数・間違えやすい文字の除外設定

すべて 1,600 × 900 px、PNG。撮影条件と素材の仕様は [README](README.md) を参照してください。

### Featured banner

[featured-banner.png](featured-banner.png)（1,920 × 640 px、3:1、PNG）。「毎日を、軽やかに。」と3機能を紹介します。

フォームの案内では、バナーの追加は snapcraft.io や GNOME Software で紹介される機会を増やしますが、追加しただけで紹介対象になることは保証されません。

### Summary（必須）

```text
日記、タイマー、パスワード生成をひとつのデスクトップアプリで
```

### Description（必須）

```text
Prelis Desktop は、日記・タイマー・パスワード生成をひとつにまとめたデスクトップアプリです。サイドバーから使いたい機能を選べます。KUPAC LLC が開発しています。

日記
日付ごとに文章を記録し、このデバイスに保存できます。カレンダーや前日・翌日のボタンから日付を選べます。別の端末との同期機能はありません。

タイマー
1〜180分のタイマーを開始・一時停止・再開・リセットできます。アプリ内で画面を切り替えても計時を続けます。手持ちの MP3・WAV ファイル（10 MB 以下）を終了音として追加し、選択・試聴できます。

パスワード生成
大文字・小文字・数字・記号から文字種を選び、4・8・12・16文字のパスワードを生成できます。間違えやすい文字を除く設定にも対応し、生成した文字列はコピーできます。

Snap 版について
Snap の制限により、ホームディレクトリ外や隠しファイルへのアクセスが制限されます。
```

## Contact information

### Primary website

```text
https://prelis.prj.kupac.co.jp
```

所有権の検証状態: 提示内容では不明。

### Other websites

```text
https://www.kupac.co.jp
```

### Contacts

```text
https://web2md.prj.kupac.co.jp/#contact
```

### Donations

未設定。

### Source code

```text
https://github.com/OsawaKousei/prelis
```

### Issues

```text
https://github.com/OsawaKousei/prelis/issues
```

## Additional information

### License

提示フォームの選択値:

```text
Apache License 2.0
```

### Metrics

提示内容には見出しのみあり、設定項目・値は不明。

## 素材と入力内容の確認事項

- 画像素材の一覧、寸法、容量、画像要件の参照先は [README](README.md) にまとめています。
- Contacts は提示された `web2md` の URL をそのまま記録しています。Prelis の問い合わせ先として使用する URL か、掲載時に確認します。
- [snapcraft.yaml](../snap/snapcraft.yaml) の Summary・Description も同じ日本語文面に揃えています。既に公開済みの Snap と Store の掲載情報は、このファイルの編集だけでは更新されません。
