# Prelis Mobile

Expo SDK 58 / React Native 0.88 の Android・iOS アプリです。画面は Expo Router、日記と音声一覧は Expo SQLite、音声本体は Expo FileSystem、ファイル選択・再生・乱数・コピーも Expo 公式モジュールを使用します。独自ネイティブモジュールはありません。

リポジトリのルートで `npm ci` を実行してから利用します。

```sh
npm run start:mobile
npm run android
npm run ios # Mac 上で実行
npm run check
```

署名付きビルドは従来どおり `npm run build:android:all` と `bash scripts/ios/build-all.sh` を使います。Android の Play 用 AAB・直接配布用 APK は既存の別々の keystore を使用し、iOS は既存の Apple 証明書・Provisioning Profile を使用します。Expo アカウント、EAS、クラウドへの鍵の登録は不要です。

`android/`・`ios/` は Git 管理するネイティブプロジェクトです。通常のビルドで `expo prebuild --clean` を実行すると手動の署名設定が失われます。Expo の設定変更は app.json と必要なネイティブ設定の両方へ反映してください。

旧実装は `../mobile-old/` に保存し、workspace・型チェック・ビルドから除外しています。旧日記 TXT・音声 JSON の移行や互換窓口は提供しません。

- [v0.1.3 の仕様・モバイル移植メモ](../../docs/specs/v0.1.3.md)
- [構成・検証・ネイティブワークフロー](../../docs/development/mobile-native.md)
