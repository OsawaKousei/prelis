# ローカル Linux 環境メモ

このマシンでの導入先・確認履歴です。一般的な必要条件は
[Android 開発](../development/android.md)・[デスクトップ開発](../development/desktop.md)を参照してください。

以下は **2026-10-11 の開発環境整備時の記録**です。今回の文書整理では環境の再構築・再検証は行っていません。
旧 `docs/android_develop_environment_doc.md` の内容をここへ統合しています。

## ツール・導入先

| 項目 | 記録 |
| --- | --- |
| Node.js / npm | 24.19.0 / 11.17.0 |
| JDK | Temurin 17.0.20.1+1、`/opt/java/jdk-17.0.20.1+1` |
| Android SDK | `$HOME/Android/Sdk` |
| SDK Platform | `android-35` と `android-37.0` を確認 |
| Android SDK Build-Tools | 既存の 36.0.0 に加え、整備時に 37.0.0 を導入 |
| NDK | 整備時に 27.1.12297006 を導入 |
| CMake | 整備時に 3.22.1 を導入 |
| Watchman | インストール済み、`/home/linuxbrew/.linuxbrew/bin/watchman` |
| AVD | `Medium_Phone_API_37.0` |
| Gradle | wrapper が 9.4.1 を取得 |

Command-line Tools の `sdkmanager` は整備開始時にコマンドとして検出されませんでした。
Android Studio の SDK Manager と Gradle による取得を利用しました。

## シェルの設定例

このマシンの導入先に対応する値です。

```sh
export JAVA_HOME="/opt/java/jdk-17.0.20.1+1"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"

# Command-line Tools をこの場所へ追加導入した場合
# export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
```

元メモの Android 15 導入済みという記述は API 35 の存在に対応します。
現在のビルドは API 37 を使用しています。

## USB 接続・udev

元メモには以下の設定手順が記載されていました。
文書整理時にはインストール・適用状況を確認していません。実機を使用するときに確認してください。

```sh
sudo apt update
sudo apt install android-sdk-platform-tools-common
sudo udevadm control --reload-rules
```

設定後は USB 接続と端末側のデバッグ許可を確認し、`adb devices` で認識状況を確認します。

## 確認履歴

2026-10-11 の環境整備時に確認した範囲:

- 全 workspace の型チェック、モバイル lint、共有関数を利用するモバイルの Jest。
- デスクトップの Vite ビルド、Linux debug 実行ファイルの生成、仮想画面上の開発起動。
- Android 向け JS バンドルと、単一の React 19.2.3・core の TypeScript ソースの取り込み。
- Android debug APK のビルドと、既存 API 37 AVD へのインストール・起動。
- Android の画面に `Hello, Prelis!` が表示されること。
- core の文言変更が APK の再ビルドなしで画面に反映されること。確認後はソースを復元。

確認に使用した仮想画面・エミュレーター・開発サーバーは終了しています。
iOS、Windows・macOS のネイティブビルド、ストア配布用署名はこの履歴に含まれません。

## 環境由来の記録

Android SDK の既存 `package.xml` や重複配置に関する警告がビルド時に出ていました。
整備時の APK ビルド・起動は成功しましたが、既存 SDK 全体の整理は行っていません。
また、制限された実行環境では Watchman の状態ディレクトリや Gradle キャッシュへの書き込みが制限され、
通常のユーザー環境で検証を行いました。
