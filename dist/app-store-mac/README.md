# Mac App Store 掲載素材と審査資料

## v0.1.4 再審査用の資料

現行ソースは Prelis Desktop `v0.1.4` です。プライバシーポリシーへのリンクはデスクトップ共通のサイドバー下部に実装済みで、macOS も対象です。Tauri Opener の初期化・URLを開く権限をソース上で確認していますが、Mac App Store 向け Sandbox ビルドでの実動作は未確認です。

| 資料 | 用途 |
| --- | --- |
| [app-review-notes.txt](app-review-notes.txt) | Guideline 2.1 の6項目に回答する英文審査メモ |
| [app-review-reply.txt](app-review-reply.txt) | レビューへの英文返信案 |
| [review-video.md](review-video.md) | Mac実機での検証・動画撮影・再提出手順 |
| [review-tone.wav](review-tone.wav) | 音声取込み・試聴・タイマー完了を確認するために合成した音声。16 kHz / 16-bit / mono / 0.8秒、25,644 bytes。第三者の録音は含みません |
| [text.md](text.md) | 現行版の日本語掲載文・審査情報の入力先 |

英文は未提出のテンプレートです。Mac で提出対象の Sandbox ビルドを検証・撮影し、角括弧のビルド番号・動画・機種とチップ・OS・テスト日・音声提供先を埋めてから使用してください。macOS のビルド番号には実際の `CFBundleVersion` を使用し、iOS の番号 `3` を流用しません。

今回の準備ではアプリコード・バージョン・署名権限は変更していません。Macのビルド・実機テスト・撮影・App Store Connectの編集・返信・審査提出も行っていません。先の Linux 検証を Mac 実機での検証として報告しません。

## 既存の画像（旧 v0.1.1 の記録）

| アップロード順 | 画像 | 内容 | サイズ |
| --- | --- | --- | --- |
| 1 | [01-diary.png](screenshots/01-diary.png) | 日記の入力と日付選択 | 1,440 × 900 px、PNG |
| 2 | [02-timer.png](screenshots/02-timer.png) | タイマーの時間設定と操作 | 1,440 × 900 px、PNG |
| 3 | [03-password.png](screenshots/03-password.png) | パスワードの生成条件 | 1,440 × 900 px、PNG |
| 4 | [04-home.png](screenshots/04-home.png) | 3機能を選ぶホーム | 1,440 × 900 px、PNG |

最初の3枚で主な機能が分かる順序にしています。4枚とも RGB で透過のない PNG です。アプリプレビュー動画は任意のため用意していません。

これらは [Microsoft Store 用スクリーンショット](../microsoft-store/README.md)と同じ、Linux 上の Prelis Desktop v0.1.1 を仮想ディスプレイで起動して撮影したアプリ画面です。Mac 上の App Store 提出ビルドを撮影した画像ではありません。再提出用には Mac の提出対象 Sandbox ビルドで撮り直してください。旧画像には日記の私的な内容と生成済みパスワードは写していません。

アプリアイコンは [デスクトップのバンドル](../../apps/desktop/src-tauri/icons/icon.icns)に含まれています。App Store Connect の「含まれるアセット」に表示されるため、ここでは別の画像をアップロードしません。Game Center も使用していません。

旧資料の作成時は App Store Connect 画面のバージョン `1.0`、選択済みビルド `0.1.1 (0.1.1)` との記録でした。現在の App Store Connect の状態を示すものではありません。再提出時のバージョン記録・選択ビルド・アプリ内表示を確認して揃えてください。審査用の担当者氏名・電話番号は [text.md](text.md) の指示に従って入力し、サポート URL の公開状態も確認してください。

参考: [Apple のスクリーンショット仕様](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)、[プロダクトページ情報の仕様](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)、[App Sandbox 情報](https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-sandbox-information/)。
