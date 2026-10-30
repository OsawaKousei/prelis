# Snap Store 掲載素材

[text.md](text.md) に正式フォームに沿った日本語の掲載情報をまとめています。対象は Prelis Desktop v0.1.2（Ubuntu amd64）です。動画は用意していません。

## アップロードする画像

| 入力欄・順序 | ファイル | サイズ | 内容 |
| --- | --- | --- | --- |
| Snap icon | [icon.png](icon.png) | 512 × 512 px、PNG | 他ストアと共通のアプリアイコン |
| Images 1 | [screenshots/01-home.png](screenshots/01-home.png) | 1,600 × 900 px、PNG | 日記・タイマー・パスワード生成を選ぶホーム |
| Images 2 | [screenshots/02-diary.png](screenshots/02-diary.png) | 1,600 × 900 px、PNG | 日付選択・カレンダー・日記の入力欄 |
| Images 3 | [screenshots/03-timer.png](screenshots/03-timer.png) | 1,600 × 900 px、PNG | 残り時間・時間設定・終了音の選択 |
| Images 4 | [screenshots/04-password.png](screenshots/04-password.png) | 1,600 × 900 px、PNG | 文字種・文字数・間違えやすい文字の除外設定 |
| Featured banner | [featured-banner.png](featured-banner.png) | 1,920 × 640 px、PNG、3:1 | 「毎日を、軽やかに。」と3機能の紹介 |

アップロード対象は上記の PNG 6枚です。SVG・生成スクリプト・撮影記録は管理用です。

## デザインと撮影条件

アイコンは [Google Play 用アイコン](../../play-store/icon.png)をそのままコピーしています。バナーは [App Store の編集可能な素材](../../app-store-ios/creative/header-wide.svg)を参考に、水色の背景、ロゴ、見出し、3機能のアイコンを Snap 用の 3:1 レイアウトに配置しました。既存のブランド図案を利用しています。

画面の構成と掲載順は [Microsoft Store の素材](../../microsoft-store/README.md)を参考にしています。スクリーンショットは v0.1.1 の素材を流用せず、`dist/snap-work/prelis_0.1.2_amd64.snap` に含まれる実行ファイルを抽出し、Linux の仮想ディスプレイ（Xvfb）上で起動して撮影しました。画面内のバージョン表示は v0.1.2 です。

撮影には専用の一時データ・設定・キャッシュ領域を使っています。日記本文は空欄、パスワードは未生成です。画面の拡大縮小や文字の差し替えは行っていません。Snap の起動ラッパーと strict confinement はこの撮影環境で再現していないため、権限やファイルアクセスの動作確認は [Snap 公開手順](../../../docs/development/dist/linux/snap.md)の Store 版で行います。

元の Snap と実行ファイルの SHA-256、撮影方法は [capture-report.json](capture-report.json) に記録しています。画像のチェックサムは [assets.sha256](assets.sha256) で確認できます。

## 画像要件と検証

2026-10-31 に Canonical の掲載フォーム実装を確認し、以下を基準に用意しています。最終的なアップロード時にはフォームの制限表示とプレビューも確認します。

| 用途 | 確認した条件 | 用意した画像 |
| --- | --- | --- |
| アイコン | 1:1、40〜512 px、256,000 bytes 以下 | 512 × 512 px、40,145 bytes |
| スクリーンショット | 表示上の最小 480 × 480 px・最大 3,840 × 2,160 px、縦横比 1:2〜2:1、各 2,000,000 bytes 以下 | 1,600 × 900 px、16:9、各 83,000 bytes 未満 |
| バナー | 3:1、最小 720 × 240 px・最大 4,320 × 1,440 px、2,000,000 bytes 以下 | 1,920 × 640 px、55,301 bytes |

画像の寸法・容量・縦横比を確認し、全画像を目視で確認しています。スクリーンショットは RGB、バナーは不透明な RGBA、アイコンは透過を含む RGBA です。

参照: Canonical の [アイコン・バナーの検証設定](https://github.com/canonical/snapcraft.io/blob/main/static/js/publisher/pages/Listing/ListingDetails/ListingDetails.tsx)、[スクリーンショットの制限表示と検証](https://github.com/canonical/snapcraft.io/blob/main/static/js/publisher/pages/Listing/ListingDetails/Screenshots.tsx)。

## バナーとアイコンの再生成

リポジトリのルートで実行します。既存の `node_modules` にある `@resvg/resvg-js` と、システムの Noto Sans CJK JP フォントを使用します。

```sh
node dist/snap-work/assets/generate-assets.mjs
```

[generate-assets.mjs](generate-assets.mjs) は `icon.png`・[featured-banner.svg](featured-banner.svg)・`featured-banner.png` を生成します。スクリーンショットは上書きしません。画像を変更した場合は、容量の記録と `assets.sha256` も更新します。

このディレクトリで次のコマンドを実行すると、アップロード画像のチェックサムを検証できます。

```sh
sha256sum -c assets.sha256
```
