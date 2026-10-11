# Android 開発

コマンドはリポジトリのルートで実行します。
先に[共通セットアップ](workflow.md)を完了してください。iOS の開発手順は対応再開時に追加します。

## 必要な環境

JDK 17、Android Studio、Android SDK を用意します。ファイル監視には Watchman を使用しています。

| 項目 | このワークスペースで使用する値 |
| --- | --- |
| React Native | 0.87.1 |
| JDK | 17 |
| Android SDK Platform / compile SDK | API 37 |
| target SDK / min SDK | 36 / 24 |
| Android SDK Build-Tools | 37.0.0 |
| NDK (Side by side) | 27.1.12297006 |
| CMake | 3.22.1（開発環境整備時のビルドで使用） |
| Gradle wrapper | 9.4.1 |
| Android SDK Platform-Tools | adb を使用 |
| Android Emulator | エミュレーターを使う場合に必要 |
| Android SDK Command-line Tools | SDK を CLI で管理する場合に導入（latest） |

React Native のバージョンは [mobile/package.json](../../apps/mobile/package.json)、
SDK・NDK は [android/build.gradle](../../apps/mobile/android/build.gradle)、
Gradle は [wrapper の設定](../../apps/mobile/android/gradle/wrapper/gradle-wrapper.properties)が定義元です。
CMake は React Native Gradle Plugin の設定にも依存するため、依存更新時にビルドログと導入バージョンを再確認します。

Android Studio の SDK Manager で必要な SDK・ツールをインストールします。
SDK Tools の **Show Package Details** で個別バージョンを選択できます。
Gradle は wrapper が取得するため、システムへの個別インストールは不要です。
初回ビルドでは Gradle・Maven・Android SDK 配布先へのネットワークアクセスが必要です。
SDK のライセンス受諾状況によっては、追加コンポーネントを Gradle が自動取得します。

Android 15 / API 35 だけでは現在の compile SDK 要件を満たしません。
API 35 のエミュレーターはアプリの実行先として利用できます。

## SDK・JDK のパス

シェルの `JAVA_HOME` に JDK 17 の導入先、`ANDROID_HOME` に SDK の導入先を設定します。
`PATH` に JDK の `bin`、SDK の `platform-tools`・`emulator` を追加します。
Command-line Tools を利用する場合は、その `bin` も追加してください。

このマシンで使用した具体的な設定は[ローカル Linux 環境](../environment/local-linux.md)にあります。

```sh
java -version
adb version
watchman --version
```

Android Studio 側だけで SDK の場所を指定する場合は、
`apps/mobile/android/local.properties` に `sdk.dir=/実際の/Android/Sdk` を記載できます。
このファイルは Git 管理対象外です。

## 開発起動

1. Android Studio の Device Manager から AVD を起動するか、USB デバッグを有効にした端末を接続します。
2. `adb devices` で対象が `device` と表示されることを確認します。
3. 2つのターミナルを使って、Metro とアプリを起動します。

```sh
# ターミナル1: Metro（ポート8081）
npm run start:mobile

# ターミナル2: APK のビルド・インストール・起動
npm run android -- --no-packager
```

共有 core の変更は Metro が直接取り込みます。
Gradle・ネイティブ依存を変更したときは APK を再ビルドしてください。

## ビルドと検証

端末なしで debug APK をビルドする場合:

```sh
npm run build:android
```

出力は `apps/mobile/android/app/build/outputs/apk/debug/app-debug.apk` です。
通常の debug APK の起動には Metro が必要です。
追加の Gradle オプションは、例えば `npm run build:android -- --no-daemon` のように渡せます。

ネイティブビルドとは別に JavaScript の依存解決・バンドルを確認する場合は、Linux では次を実行できます。
出力先は一時ディレクトリです。他の OS では適切な一時パスへ変更してください。

```sh
npm exec -w apps/mobile -- react-native bundle \
  --platform android \
  --dev false \
  --entry-file index.js \
  --bundle-output /tmp/prelis-android.bundle \
  --assets-dest /tmp/prelis-android-assets \
  --max-workers 2
```

バンドル生成だけでは、ネイティブリンクや端末上の動作までは確認できません。
変更ごとの検証範囲は[作業・検証手順](workflow.md)を参照してください。
release は [app/build.gradle](../../apps/mobile/android/app/build.gradle) で debug key を使用する初期設定です。
ストア配布用の署名・release 検証は別タスクとして扱います。

## トラブルシュート

- **Metro に接続できない**: サーバーが動いているか確認し、対象端末へ `adb reverse tcp:8081 tcp:8081` を実行します。複数端末がある場合は `adb -s <serial> reverse tcp:8081 tcp:8081` を使います。
- **API 37 で接続許可が表示される**: 開発用 Metro への接続に必要なローカル接続を許可します。検証時には周辺デバイスへの接続許可が表示されました。
- **adb が `unauthorized` / `no permissions`**: 端末側の USB デバッグ許可と、Linux 側の udev 設定を確認します。このマシンの設定メモは[環境メモ](../environment/local-linux.md)にあります。
- **SDK・NDK が見つからない**: `ANDROID_HOME` または `local.properties` と、要求バージョンのインストール状況を確認します。
- **React の重複・Hooks エラー**: `npm ls react react-dom react-test-renderer --all` で解決先を確認します。バージョンと lockfile を修正したあと、Metro を停止して `npm run start:mobile -- --reset-cache` で再起動します。
- **Watchman の状態ディレクトリに書き込めない**: 実行環境の権限を確認します。一時的なサンドボックス制約を避けるためだけに、共有設定からファイル監視を削除しないでください。
