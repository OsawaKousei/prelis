# iOS App Store 掲載素材と審査資料

## v0.1.4 再審査用テキスト

- [app-review-notes.txt](app-review-notes.txt): App Review Information の Notes 欄用の英文。Guideline 2.1 の6項目に回答します。
- [app-review-reply.txt](app-review-reply.txt): 審査メッセージへの英文返信案。

どちらも未提出のテンプレートです。角括弧の値を埋めずに送信しないでください。今回は Linux のみをビルド・検証し、iOS ビルド・実機テスト・動画撮影・審査への送信は行っていません。

再提出前に以下を実施します。

1. App Store Connect の対象バージョンとビルドを確認します。現行ソースは `0.1.4` / ビルド `3` です。下記の旧版素材や既存 IPA を新版の証拠として扱いません。提出する版とソースの版を一致させてからビルドします。
2. 提出対象ビルドを TestFlight で対応する iPhone・iPad 実機にインストールし、主要機能・リンク・再起動後の保存を確認します。実施機種・正確なOSバージョン・日付を記録します。
3. 最新の正式版OSを搭載した実機で、ホーム画面からの起動に始まる動画を撮影します。日記保存と再表示、音声追加と試聴、1分タイマーの一時停止・再開・タブ移動・完了音・リセット、パスワード生成とコピー、ポリシー表示を含めます。終了音が動画にも記録されていることを確認します。
4. 自作の短い WAV を用意して実機で取込み・再生を確認します。動画と同じファイルを審査へ提供します。サンプル音声は本変更には同梱していません。
5. テキスト内のビルド・動画・端末とOS・テスト日・音声のプレースホルダーを実際の値で置換します。URLで提供する場合は、ログインやアクセス申請なしで取得・再生できることを確認します。
6. 審査メモを登録し、動画・音声を提供した後で返信文を使用します。サインイン必須をオフにし、地域設定・掲載情報と説明が一致することを確認して再提出します。

審査メモは4,000文字以内に収めていますが、プレースホルダー置換後も長さを確認してください。今回の追加リンクは、モバイルでは「ホーム」から、デスクトップではサイドバー下部から開きます。機能仕様は [v0.1.4](../../docs/specs/v0.1.4.md) に記録しています。

## 既存の掲載素材（バージョン 1.0）

以下の画像・撮影記録は旧ビルド `1.0 (1)` の素材です。[text.md](text.md) の掲載文は現行ソース `0.1.4` に更新しています。アプリ名は Prelis Mobile です。

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
| 概要 | 568 |
| このバージョンの最新情報 | 29 |
| キーワード | 34 |
| 著作権 | 14 |

現行の [text.md](text.md) にはバージョン `0.1.4`、著作権 `2026 KUPAC LLC`、既存のサポート URL・マーケティング URL を使用しています。両 URL とプライバシーポリシー URL は旧素材の作成日に HTTP 200 を確認しました。経路案内機能はないため、ルーティングアプリカバレッジファイルは不要です。初回版で最新情報の欄が表示されない場合は入力しません。審査用の担当者氏名・電話番号は App Store Connect で入力してください。

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
