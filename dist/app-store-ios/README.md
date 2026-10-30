# iOS App Store 掲載素材（日本語・バージョン 1.0）

[text.md](text.md) に App Store Connect の各欄へ貼り付ける掲載文をまとめています。Mac App Store・Google Play の既存掲載文を基に、iPhone・iPad の実装に合わせました。アプリ名は Prelis Mobile、対象ビルドは `1.0 (1)` です。

## ヘッダ・検索結果

| 用途 | ファイル | サイズ |
| --- | --- | --- |
| ヘッダ（横長・推奨） | [header-wide.png](creative/header-wide.png) | 3,840 × 1,646 px |
| ヘッダの別案／検索結果と共用 | [header-universal.png](creative/header-universal.png) | 5,244 × 2,950 px |
| 検索結果（3:2） | [search-results.png](creative/search-results.png) | 3,840 × 2,560 px |

ヘッダ欄には上の2種類から1枚を選びます。検索結果欄は `search-results.png`、または共用画像 `header-universal.png` を使用できます。PNG がアップロード用で、同名の SVG は編集用の原稿です。表示範囲の最終確認には App Store Connect のプレビューを使用してください。

既存の `brand.png` と共通機能アイコン、アプリと同じ配色を使用し、「毎日を、軽やかに。」と3機能を表現しました。別プラットフォームのロゴ、価格、URL は画像へ入れていません。

## アプリプレビューとスクリーンショット

| 順番 | 内容 | iPhone | iPad |
| --- | --- | --- | --- |
| 1 | 日記の入力・保存 | [01-diary.png](screenshots/iphone/01-diary.png) | [01-diary.png](screenshots/ipad/01-diary.png) |
| 2 | タイマーの時間設定と操作 | [02-timer.png](screenshots/iphone/02-timer.png) | [02-timer.png](screenshots/ipad/02-timer.png) |
| 3 | パスワードの生成条件 | [03-password.png](screenshots/iphone/03-password.png) | [03-password.png](screenshots/ipad/03-password.png) |
| 4 | 3機能を選ぶホーム | [04-home.png](screenshots/iphone/04-home.png) | [04-home.png](screenshots/ipad/04-home.png) |

- iPhone: iPhone 18 Pro / 1,206 × 2,622 px。Dynamic Island の中型ディスプレイ用の欄に使用します。
- iPad: iPad Pro 13-inch (M5) / 2,064 × 2,752 px。13インチ用の欄に使用します。
- 全画像は縦向きの RGB PNG で、アルファチャンネルはありません。動画のアプリプレビューは用意していません。

2026-10-30 に Mac 上の iOS 27.0 Simulator で、バージョン `1.0` / ビルド `1` の実際の React Native UI を撮影しました。撮影には Metro に接続した Debug ビルドを使用しています。Release の提出済みビルドを撮影した画像ではありません。画面構成のモックや Android・デスクトップ画面の流用はありません。UI の内容・サイズは変更せず、PNG を透過のない RGB 形式へ変換しています。

撮影専用の空の Simulator を2台作成し、時刻を9:41、バッテリーを100%に揃えました。日記には撮影用のサンプルだけを入力して保存し、別画面から戻って再表示を確認しました。タイマーの開始・一時停止・リセットと16文字のパスワード生成も両端末で操作確認しています。パスワード画像は生成結果を消した状態です。既存端末の個人データ・実際に利用するパスワードは含みません。撮影後は専用 Simulator と検証用 Metro を終了しています。

[capture-report.json](capture-report.json) に撮影構成・サンプル本文・撮影したファイルの対応を記録しています。音声ファイルの追加・再生やクリップボードへのコピーは、この撮影作業では操作していません。

## 入力する文面

| 欄 | 文字数 |
| --- | --- |
| プロモーション用テキスト | 64 |
| 概要 | 532 |
| このバージョンの最新情報 | 88 |
| キーワード | 34 |
| 著作権 | 14 |

掲載文にはバージョン `1.0`、著作権 `2026 KUPAC LLC`、既存のサポート URL・マーケティング URL を使用しています。両 URL とプライバシーポリシー URL は作成日に HTTP 200 を確認しました。経路案内機能はないため、ルーティングアプリカバレッジファイルは不要です。初回版で最新情報の欄が表示されない場合は入力しません。審査用の担当者氏名・電話番号は App Store Connect で入力してください。

[icon.png](icon.png) はアプリに同梱するものと同じ 1,024 × 1,024 px の RGB アイコンです。App Store のアイコンはビルドに含まれる AppIcon を使うため、ヘッダやスクリーンショットの欄には追加しません。

## 再生成・確認

リポジトリルートから、既存の Node.js 依存と Noto Sans CJK JP フォントを利用して実行します。

```sh
# ロゴ・共通アイコンからクリエイティブ3枚とアイコンを生成
node dist/app-store-ios/generate-assets.mjs

# 保存済みの Simulator 撮影データ8枚を RGB PNG に変換
node dist/app-store-ios/generate-assets.mjs --screenshots apps/mobile/ios/build/store-assets

# 生成・確認時点の画像ハッシュを照合
(cd dist/app-store-ios && sha256sum -c assets.sha256)
```

PNG のサイズ・RGB 形式・画像の破損、掲載文の文字数、差分を確認済みです。App Store Connect への登録、アップロード、Apple 側のアセットチェック・審査提出は行っていません。

参考: [Apple のクリエイティブ仕様](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)、[スクリーンショット仕様](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)、[アセットのベストプラクティス](https://developer.apple.com/app-store/asset-best-practices/)。
