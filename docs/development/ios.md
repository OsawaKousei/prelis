# iOS Simulator 開発

コマンドはリポジトリのルートで実行します。通常の動作確認は、Mac で Metro を起動し、Debug アプリを iOS Simulator で実行します。Linux で編集したソースを Mac へ同期する構成です。実機用 IPA や App Store 配布物は作成しません。

## 初回だけ必要な準備

- Mac に Xcode 本体をインストールし、初回起動時のライセンスと追加コンポーネントの設定を完了します。Xcode で利用する iOS Simulator ランタイムも導入します。
- Mac に Node.js（ルートの [`.nvmrc`](../../.nvmrc) と [エンジン条件](../../package.json)を満たす版）、npm、CocoaPods をインストールします。このワークスペースの Mac は fnm と Homebrew でこれらを利用できます。
- Linux 側から macOS 版と同じ `kousei@192.168.10.22` へ SSH 鍵認証で接続できるようにし、Mutagen、OpenSSH クライアント、`sha256sum`、`unzip` を用意します。Mac で「リモートログイン」を有効にします。

初回は下記の開発起動手順で `npm ci` と `pod install` による依存取得、CocoaPods workspace の生成を行います。CocoaPods の依存は [Podfile.lock](../../apps/mobile/ios/Podfile.lock) に固定します。依存のダウンロードに時間とネットワーク接続が必要です。Simulator での実行に署名証明書と Apple Developer Team の設定は不要です。

## 同期のみ実行する場合

```sh
./scripts/ios/create-ios-sync.sh
```

`kousei@192.168.10.22:prelis-ios-remote` に Mutagen の `one-way-safe` セッション `prelis-ios` で同期します。macOS 版とは同期先ディレクトリとセッションを分け、Mutagen のデータは Git 管理対象外の `.mutagen-ios/` に保存します。既存セッションの同期先が異なる場合は停止し、自動的な移行や削除は行いません。

同期対象はルートの npm 定義と `.nvmrc`、`apps/mobile` の共通コードと `ios/`、`packages/core`、`packages/icons`、`scripts/ios/build-on-mac.sh` です。Android・デスクトップ・ウェブ、他 OS のスクリプト、ドキュメント、依存、ビルド生成物、認証ファイルは除外します。Mac 側の `node_modules`、`Pods`、生成された CocoaPods workspace、`DerivedData` は Mac 側で生成・再利用します。

スクリプトは同期完了・競合なし・必要ファイルの存在と不要ディレクトリの不在を確認します。同期だけでは依存インストール、ビルド、Simulator の起動は行いません。

除外設定の変更は既存の Mutagen セッションには反映されないため、変更時はセッションの再作成が必要です。除外対象が同期先に残っている場合も検証で停止するため、既存の同期先は必要に応じて退避します。

2026-10-30 に新しい同期設定で初回同期と既存セッションの再利用を確認しました。両側とも 57 ファイル・約 729 KB、競合 0 件で、必要ファイルの存在と依存・ビルド生成物の除外を確認しています。この確認では依存インストール、ビルド、Simulator の起動は行っていません。

## Metro を使った開発起動

[React Native の Simulator 起動手順](https://reactnative.dev/docs/running-on-simulator-ios)に沿って、Metro と Simulator の両方を Mac 上で実行します。Metro は Mac のポート 8081 を使います。

1. Linux で `./scripts/ios/create-ios-sync.sh` を実行してソースを同期します。
2. 初回、または依存を変更したときは、Metro を停止した状態で Mac 上の依存を準備します。

```sh
# Mac: 初回セットアップ（Node.js と CocoaPods が PATH に入ったターミナル）
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ~/prelis-ios-remote
npm ci
(cd apps/mobile/ios && pod install --deployment)
```

3. Mac の2つのターミナルで Metro と Debug アプリを起動します。`--udid` には一覧に表示された対象デバイスの UDID を指定します。

```sh
# Mac ターミナル1: Metro（起動したままにする）
cd ~/prelis-ios-remote
npm run start:mobile
```

```sh
# Mac ターミナル2: Simulator 用 Debug アプリのビルド・インストール・起動
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ~/prelis-ios-remote
xcrun simctl list devices available
SIMULATOR_UDID='対象デバイスのUDID'
npm run ios -w apps/mobile -- --mode Debug --udid "$SIMULATOR_UDID" --no-packager
```

`--no-packager` は CLI による Metro の自動起動を止める指定です。アプリはターミナル1で起動した Metro から JavaScript を読み込みます。[AppDelegate.swift](../../apps/mobile/ios/PrelisMobile/AppDelegate.swift) は Debug 時に Metro の URL を使う構成です。画面の操作は Mac 上、または画面共有で行います。

4. Linux でモバイル UI や共有 core を編集し、Mac への同期後に Fast Refresh で変更が反映されることを確認します。Mutagen のセッションは起動後も変更を監視します。同期完了を明示的に待つ場合は同期スクリプトを再実行してください。
5. Swift・Objective-C・Xcode 設定を変更したときは、ターミナル2のコマンドで再ビルドします。依存を変更したときは、Metro を停止して依存準備からやり直します。

Metro 設定を変更した場合は、Mac の Metro を `Ctrl+C` で停止して `npm run start:mobile -- --reset-cache` で起動し直し、Simulator の開発メニューから Reload してください。設定ファイルの変更は Fast Refresh では反映されません。

共有アイコンはプロジェクトルート外にあります。Metro 設定はその画像 URL を `/assets/` と `unstable_path` クエリへ変換し、URL の正規化によって画像配信に失敗する問題を回避します。

2026-10-30 にユーザーが Metro を使った Simulator 起動を確認しました。調査でも Metro とアプリの接続、Watchman の監視、Fast Refresh の有効設定を確認しています。Ubuntu での編集から画面更新までの一連の操作と、下記の各機能操作は未確認です。

同日に画像 URL の変換設定を追加し、Ubuntu と Mac の一時 Metro サーバーで、共有 PNG 全11枚を iOS・Android 向けの生 URL と正規化済み URL の両方から取得できることを回帰テストで確認しました。両 OS の Release バンドル生成と画像11枚の同梱も Ubuntu で確認しています。起動中の Metro は設定変更後に再起動が必要で、変更後の Simulator 画面上の表示は未確認です。

## Metro を使わない Release ビルド

```sh
./scripts/ios/build-ios-simulator.sh
```

スクリプトは上記の iOS 専用同期を実行した後、Mac の `~/prelis-ios-remote` で `npm ci`、`pod install`、署名を無効にした Release / iOS Simulator ビルドを実行します。Release は JavaScript と画像を `.app` に同梱します。完成した `.app` を ZIP 化・検証し、Linux 側へ回収して SHA-256 を照合します。Metro を使う通常の開発起動には、このスクリプトは使いません。

| 成果物 | ローカルの出力先 |
| --- | --- |
| Simulator 用 `.app` の ZIP | `apps/mobile/ios/build/simulator/PrelisMobile-simulator.app.zip` |
| SHA-256 一覧 | `apps/mobile/ios/build/ios-simulator-artifacts.sha256` |

ZIP は Simulator 専用です。実機へのインストール、TestFlight、App Store 配布には使えません。

2026-10-18 に Xcode 27.1、CocoaPods 1.17.0、Node.js 24.22.0 の Mac で Release / Simulator ビルドと JS バンドルの同梱、ZIP の整合性、回収後の SHA-256 を確認しました。アプリ本体には開発チームの署名がありません。同日に iPhone 18 Pro Simulator へのインストール、起動、ホーム画面の表示を確認しました。

## Release 成果物を Simulator で起動する

一括ビルド後、Mac のターミナルで実行します。SSH から `simctl` を実行する場合も、同じコマンドを使用できます。`boot` はデバイスが停止しているときだけ実行してください。表示画面を操作するには、Mac の画面で Device Hub を開いて起動済みのシミュレーターを選ぶか、画面共有を使います。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ~/prelis-ios-remote
xcrun simctl list devices available
xcrun simctl boot "iPhone 18 Pro"                  # 停止中のみ
xcrun simctl bootstatus "iPhone 18 Pro" -b
xcrun simctl install "iPhone 18 Pro" apps/mobile/ios/DerivedData/Build/Products/Release-iphonesimulator/PrelisMobile.app
open /Applications/Xcode.app/Contents/Applications/DeviceHub.app
xcrun simctl launch "iPhone 18 Pro" org.reactjs.native.example.PrelisMobile
```

画面が見えない場合は、`xcrun simctl io "iPhone 18 Pro" screenshot /tmp/prelis-ios.png` でスクリーンショットを保存できます。現在の Bundle ID は Xcode テンプレート値です。変更したら `simctl launch` の引数も合わせてください。

## 画面上の機能操作

Metro を使った Debug 実行でも、Release 成果物の実行でも、画面上では次を確認します。

1. Diary で日記を保存し、別の日付に移動して戻った後に内容が再表示される。
2. Password で生成とコピーを行う。
3. Timer の音声設定で MP3/WAV を追加し、選択・試聴・削除する。タイマー完了後の反復再生はリセットで止める。

過去の確認は Release アプリの Simulator へのインストールとホーム表示までです。上記の各操作はまだ実機能として検証していません。iOS のバックグラウンド実行では、タイマー完了の処理がアプリ復帰まで遅れることがあります。

## Mac で直接 Release ビルドする場合

ソースを同期してから、Mac 上で次を実行します。

```sh
cd ~/prelis-ios-remote
bash scripts/ios/build-on-mac.sh
```

Mac の `xcode-select` が Command Line Tools を指している場合も、スクリプトは `/Applications/Xcode.app` を使用します。生成先は Mac 側の `apps/mobile/ios/build/` です。

## ネイティブ処理

[iOS の `PrelisNative`](../../apps/mobile/ios/PrelisMobile/PrelisNative.m) は [Android 版](../../apps/mobile/android/app/src/main/java/com/prelismobile/PrelisModule.kt) と同じ [JavaScript API](../../apps/mobile/src/native.ts) を提供します。日記と終了音はアプリ内の Application Support に保存します。音声は iOS のファイル選択画面から MP3/WAV を 10 MB 以下で取り込みます。ビルド成功とホーム表示だけでは、各 API の操作確認は完了しません。
