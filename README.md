# Prelis

Tauri + React のデスクトップアプリと React Native の Android アプリで、
`packages/core` の TypeScript ロジックを共有する npm workspaces モノレポです。
iOS のネイティブ設定・ビルド検証は保留しています。

| ディレクトリ | 役割 |
| --- | --- |
| `apps/desktop` | Tauri 2 / React / Vite |
| `apps/mobile` | React Native 0.87.1 / Metro / Android |
| `packages/core` | UI・OS に依存しない共有ロジック |

## 初回セットアップ

Node.js 24.19.0（`.nvmrc`）と npm を使用します。依存のインストールは必ずリポジトリのルートで行います。

```sh
nvm use                    # nvm を使用している場合
npm ci
npm run check
```

React / React DOM / React Test Renderer は 19.2.3 に揃えています。
ルートの `overrides` と lockfile で推移的な React の重複も防いでいます。
React Native の renderer と一緒に検証し、アプリ単独で React のバージョンを変更しないでください。

## デスクトップ

Rust の stable toolchain と、OS ごとの [Tauri の前提条件](https://v2.tauri.app/start/prerequisites/) が必要です。
Linux では WebKitGTK 4.1、GTK 3 などの開発ライブラリを用意してください。

```sh
npm run dev:desktop          # Vite + Tauri を起動
npm run build:desktop:debug  # debug 実行ファイルをビルド（インストーラなし）
npm run build:desktop        # release ビルド・配布パッケージ生成
```

フロントエンドだけを確認する場合は `npm run dev -w apps/desktop`、
ビルドする場合は `npm run build -w apps/desktop` を使用します。
開発サーバーのポートは 1420 です。

## Android

JDK 17、Android Studio、Android SDK、Watchman を使用します。
`docs/android_develop_environment_doc.md` に記載された Linux 環境では、次をシェルに設定します。
別の環境ではインストール先に合わせて変更してください。

```sh
export JAVA_HOME="/opt/java/jdk-17.0.20.1+1"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
```

Android Studio の **SDK Manager** で、以下をインストールしてください。
SDK Tools は **Show Package Details** を有効にするとバージョンを選択できます。

| 項目 | バージョン |
| --- | --- |
| Android SDK Platform（compile SDK） | API 37 |
| Android SDK Build-Tools | 37.0.0 |
| NDK (Side by side) | 27.1.12297006 |
| CMake | 3.22.1 |
| Android SDK Platform-Tools | インストール必須（adb） |
| Android SDK Command-line Tools | latest（sdkmanager） |
| Android Emulator | エミュレーターを使用する場合 |

一般的なセットアップ案内の Android 15 / API 35 だけでは、このリポジトリのビルド要件を満たしません。
使用中の React Native 0.87.1 と `apps/mobile/android/build.gradle` に合わせています。
target SDK は 36、min SDK は 24 です。API 35 のエミュレーターも実行先として利用できます。
Gradle 9.4.1 は同梱の wrapper が取得するため、システムへの Gradle インストールは不要です。
初回ビルドでは Gradle / Maven / Android SDK 配布先へのネットワークアクセスが必要です。

1. Android Studio の Device Manager からエミュレーターを起動するか、USB デバッグを有効にした端末を接続します。
2. `adb devices` で対象が `device` と表示されることを確認します。
3. ルートから、ターミナルを2つ使って起動します。

```sh
# ターミナル1: Metro（ポート8081）
npm run start:mobile

# ターミナル2: APK のビルド・インストール・起動
npm run android -- --no-packager
```

端末なしで debug APK をビルドする場合:

```sh
npm run build:android
# 出力: apps/mobile/android/app/build/outputs/apk/debug/app-debug.apk
```

Metro につながらない場合は、対象端末に対して `adb reverse tcp:8081 tcp:8081` を実行してください。
API 37 の初回起動で周辺デバイスへの接続許可が表示された場合は、開発用 Metro への接続を許可してください。
SDK の場所を Android Studio 側だけで指定する場合は、
`apps/mobile/android/local.properties` に `sdk.dir=/実際の/Android/Sdk` を記載できます（Git 管理対象外）。
release の署名設定はテンプレートの debug key のままです。ストア配布用の署名は別途設定してください。

## 共有ロジックの開発

両アプリのサンプル画面は `@prelis/core` の `greet()` を使っています。
`packages/core/src/index.ts` を編集すると、Vite / Metro が TypeScript ソースを直接取り込みます。
アプリ開発時の core の事前ビルドや、追加の watch プロセスは不要です。

`browser` / `react-native` の package exports 条件を使ってソースを選択し、
通常の Node.js 向け import では `dist` を使用します。
Node.js 向けの成果物が必要な場合は `npm run build:core` を先に実行してください。
`dist` は生成物なので Git には含めません。

```sh
npm run check      # 全 workspace の型チェック + モバイル lint + Jest
npm run typecheck
npm run lint
npm test
```

共有ロジックには DOM / React Native / Tauri API を直接持ち込まず、
OS ごとの処理は各アプリから注入してください。
