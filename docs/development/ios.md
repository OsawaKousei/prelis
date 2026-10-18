# iOS Simulator ビルド

コマンドはリポジトリのルートで実行します。現在の対象は署名なしの iOS Simulator 用 `.app` です。実機用 IPA や App Store 配布物は作成しません。

## 初回だけ必要な準備

- Mac に Xcode 本体をインストールし、初回起動時のライセンスと追加コンポーネントの設定を完了します。Xcode で利用する iOS Simulator ランタイムも導入します。
- Mac に Node.js（ルートの [`.nvmrc`](../../.nvmrc) と [エンジン条件](../../package.json)を満たす版）、npm、CocoaPods をインストールします。このワークスペースの Mac は fnm と Homebrew でこれらを利用できます。
- Linux 側から `kousei@192.168.1.80` へ SSH 鍵認証で接続できるようにし、Mutagen、OpenSSH クライアント、`sha256sum`、`unzip` を用意します。Mac で「リモートログイン」を有効にします。

初回の `npm ci` と `pod install` による依存取得、CocoaPods workspace の生成はビルドスクリプトが実行します。CocoaPods の依存は [Podfile.lock](../../apps/mobile/ios/Podfile.lock) に固定します。依存のダウンロードに時間とネットワーク接続が必要です。署名証明書と Apple Developer Team の設定は、この段階では不要です。

## 毎回のビルド

```sh
./scripts/ios/build-ios-simulator.sh
```

スクリプトは [macOS 同期](macos.md)を実行した後、Mac で `npm ci`、`pod install`、署名を無効にした Release / iOS Simulator ビルドを実行します。Release は JavaScript と画像を `.app` に同梱します。完成した `.app` を ZIP 化・検証し、Linux 側へ回収して SHA-256 を照合します。

| 成果物 | ローカルの出力先 |
| --- | --- |
| Simulator 用 `.app` の ZIP | `apps/mobile/ios/build/simulator/PrelisMobile-simulator.app.zip` |
| SHA-256 一覧 | `apps/mobile/ios/build/ios-simulator-artifacts.sha256` |

ZIP は Simulator 専用です。実機へのインストール、TestFlight、App Store 配布には使えません。

2026-10-18 に Xcode 27.1、CocoaPods 1.17.0、Node.js 24.22.0 の Mac で Release / Simulator ビルドと JS バンドルの同梱、ZIP の整合性、回収後の SHA-256 を確認しました。アプリ本体には開発チームの署名がありません。同日に iPhone 18 Pro Simulator へのインストール、起動、ホーム画面の表示を確認しました。

## Simulator で操作する

一括ビルド後、Mac のターミナルで実行します。SSH から `simctl` を実行する場合も、同じコマンドを使用できます。`boot` はデバイスが停止しているときだけ実行してください。表示画面を操作するには、Mac の画面で Device Hub を開いて起動済みのシミュレーターを選ぶか、画面共有を使います。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ~/prelis-remote
xcrun simctl list devices available
xcrun simctl boot "iPhone 18 Pro"                  # 停止中のみ
xcrun simctl bootstatus "iPhone 18 Pro" -b
xcrun simctl install "iPhone 18 Pro" apps/mobile/ios/DerivedData/Build/Products/Release-iphonesimulator/PrelisMobile.app
open /Applications/Xcode.app/Contents/Applications/DeviceHub.app
xcrun simctl launch "iPhone 18 Pro" org.reactjs.native.example.PrelisMobile
```

画面が見えない場合は、`xcrun simctl io "iPhone 18 Pro" screenshot /tmp/prelis-ios.png` でスクリーンショットを保存できます。現在の Bundle ID は Xcode テンプレート値です。変更したら `simctl launch` の引数も合わせてください。

画面上では次を確認します。

1. Diary で日記を保存し、別の日付に移動して戻った後に内容が再表示される。
2. Password で生成とコピーを行う。
3. Timer の音声設定で MP3/WAV を追加し、選択・試聴・削除する。タイマー完了後の反復再生はリセットで止める。

Simulator へのインストールとホーム表示は確認済みです。上記の各操作はまだ実機能として検証していません。iOS のバックグラウンド実行では、タイマー完了の処理がアプリ復帰まで遅れることがあります。

## Mac で直接ビルドする場合

ソースを同期してから、Mac 上で次を実行します。

```sh
cd ~/prelis-remote
bash scripts/ios/build-on-mac.sh
```

Mac の `xcode-select` が Command Line Tools を指している場合も、スクリプトは `/Applications/Xcode.app` を使用します。生成先は Mac 側の `apps/mobile/ios/build/` です。

## ネイティブ処理

[iOS の `PrelisNative`](../../apps/mobile/ios/PrelisMobile/PrelisNative.m) は [Android 版](../../apps/mobile/android/app/src/main/java/com/prelismobile/PrelisModule.kt) と同じ [JavaScript API](../../apps/mobile/src/native.ts) を提供します。日記と終了音はアプリ内の Application Support に保存します。音声は iOS のファイル選択画面から MP3/WAV を 10 MB 以下で取り込みます。ビルド成功とホーム表示だけでは、各 API の操作確認は完了しません。
