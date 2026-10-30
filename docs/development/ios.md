# iOS 開発（Simulator・iPhone 実機）

コマンドはリポジトリのルートで実行します。通常の動作確認は、Mac で Metro を起動し、Debug アプリを iOS Simulator または iPhone 実機で実行します。Linux で編集したソースを Mac へ同期する構成です。配布には別途 Release ビルドを使用します。

## 初回だけ必要な準備

- Mac に Xcode 本体をインストールし、初回起動時のライセンスと追加コンポーネントの設定を完了します。Xcode で利用する iOS Simulator ランタイムも導入します。
- Mac に Node.js（ルートの [`.nvmrc`](../../.nvmrc) と [エンジン条件](../../package.json)を満たす版）、npm、Ruby 3.2 以降、Bundler 4.0.20 を用意します。このワークスペースの Mac は fnm と Homebrew を使用し、Ruby 4.0.7 で確認しています。CocoaPods 1.17.0 と xcodeproj 1.28.1 および間接依存は `apps/mobile/Gemfile.lock` に固定します。
- Linux 側から macOS 版と同じ `kousei@192.168.10.22` へ SSH 鍵認証で接続できるようにし、Mutagen、OpenSSH クライアント、`sha256sum`、`unzip` を用意します。Mac で「リモートログイン」を有効にします。

初回は下記の開発起動手順で `npm ci` と `prepare-pods-on-mac.sh` による依存取得、CocoaPods workspace の生成を行います。Pod の依存は [Podfile.lock](../../apps/mobile/ios/Podfile.lock)、Ruby ツールは [Gemfile.lock](../../apps/mobile/Gemfile.lock) に固定します。依存のダウンロードに時間とネットワーク接続が必要です。Simulator での実行に署名証明書と Apple Developer Team の設定は不要です。

## 同期のみ実行する場合

```sh
./scripts/ios/create-ios-sync.sh
```

`kousei@192.168.10.22:prelis-ios-remote` に Mutagen の `one-way-safe` セッション `prelis-ios` で同期します。macOS 版とは同期先ディレクトリとセッションを分け、Mutagen のデータは Git 管理対象外の `.mutagen-ios/` に保存します。既存セッションの同期先が異なる場合は停止し、自動的な移行や削除は行いません。

同期対象はルートの npm 定義と `.nvmrc`、`apps/mobile` の共通コードと `ios/`、`packages/core`、`packages/icons`、iOS の Mac 側ビルド・署名セットアップスクリプトです。Android・デスクトップ・ウェブ、他 OS のスクリプト、ドキュメント、依存、ビルド生成物、認証ファイルは除外します。Mac 側の `node_modules`、`Pods`、生成された CocoaPods workspace、`DerivedData` は Mac 側で生成・再利用します。

スクリプトは同期完了・競合なし・必要ファイルの存在と不要ディレクトリの不在を確認します。同期だけでは依存インストール、ビルド、Simulator の起動は行いません。

除外設定の変更は既存の Mutagen セッションには反映されないため、変更時はセッションの再作成が必要です。除外対象が同期先に残っている場合も検証で停止するため、既存の同期先は必要に応じて退避します。

2026-10-30 に新しい同期設定で初回同期と既存セッションの再利用を確認しました。両側とも 57 ファイル・約 729 KB、競合 0 件で、必要ファイルの存在と依存・ビルド生成物の除外を確認しています。この確認では依存インストール、ビルド、Simulator の起動は行っていません。

### Xcode 設定の並び替えによる競合を防ぐ

`project.pbxproj` の正本は Ubuntu 側で管理し、固定版 xcodeproj の保存形式に揃えます。Ubuntu で Xcode 設定を編集したら、次を実行して差分を確認し、同期します。初回は同期先に Bundler 用スクリプトと Gemfile.lock が必要です。

```sh
./scripts/ios/normalize-xcode-project.sh
git diff -- apps/mobile/ios/PrelisMobile.xcodeproj/project.pbxproj
./scripts/ios/create-ios-sync.sh
```

正規化は Ubuntu のファイルを Mac の一時ディレクトリへ渡して行い、設定値が同じことを検証して Ubuntu の書式だけ更新します。Mac の同期先プロジェクトは書き換えません。Mac で直接実行する場合はその Mac のプロジェクトを正規化するため、Ubuntu の正本を編集するときは Ubuntu から実行してください。

依存準備は必ず `bash scripts/ios/prepare-pods-on-mac.sh` を使います。内部の `bundle-on-mac.sh` は `Gemfile.lock` を frozen モードで使用し、必要な gem を `apps/mobile/vendor/bundle` に導入します。マシン固有の `.bundle/config` は参照しません。`bundle exec pod install --deployment` の前に書式を検証し、前後で `project.pbxproj` と `Podfile.lock` が変わった場合は停止します。実質的な変更は差分をレビューして Ubuntu 側へ反映し、競合を自動で上書きしません。同期中の競合も待ち続けず、その時点で報告します。

`npm ci` で大量のファイルを置き換えた後に Watchman の索引が古いままになることがあるため、依存準備の最後にはこの同期先だけ監視を作り直します。他プロジェクトの監視は変更しません。依存準備中は Metro を停止してください。

## Metro を使った開発起動

[React Native の Simulator 起動手順](https://reactnative.dev/docs/running-on-simulator-ios)に沿って、Metro と Simulator の両方を Mac 上で実行します。Metro は Mac のポート 8081 を使います。

1. Linux で `./scripts/ios/create-ios-sync.sh` を実行してソースを同期します。
2. 初回、または依存を変更したときは、Metro を停止した状態で Mac 上の依存を準備します。

```sh
# Mac: 初回セットアップ（Node.js・Ruby・Bundler が PATH に入ったターミナル）
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ~/prelis-ios-remote
npm ci
bash scripts/ios/prepare-pods-on-mac.sh
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

2026-10-30 に固定版 CocoaPods で依存準備を2回実行し、Xcode 設定と Podfile.lock に差分がなく、その後の同期も競合0件で正常終了することを確認しました。iPhone 18 Pro Simulator の Debug アプリで、Ubuntu の見出し変更とその復元が、同期の強制実行・再ビルド・手動 Reload なしで描画済みテキストへ反映されることも確認しています。検証前に Watchman の `UserDropped` 警告があったため、この iOS 同期先だけ監視を作り直しました。JavaScript / TypeScript は Fast Refresh の対象ですが、Swift・Objective-C・Xcode 設定の変更には再ビルドが必要です。検証用の Metro は確認後に停止します。

2026-10-30 にユーザーが Metro を使った Simulator 起動を確認しました。調査でも Metro とアプリの接続、Watchman の監視、Fast Refresh の有効設定を確認しています。実機での編集反映は次節に記録し、下記の各機能操作とは区別します。

同日に画像 URL の変換設定を追加し、Ubuntu と Mac の一時 Metro サーバーで、共有 PNG 全11枚を iOS・Android 向けの生 URL と正規化済み URL の両方から取得できることを回帰テストで確認しました。両 OS の Release バンドル生成と画像11枚の同梱も Ubuntu で確認しています。起動中の Metro は設定変更後に再起動が必要です。今回の Simulator 検証では画面上の共有アイコンの表示も確認しました。

## iPhone 実機で Metro を使う

### 初回の開発署名セットアップ

Mac のホームに次の2ファイルを用意します。プロファイルは iOS App Development、Team `GLQCJ8YF9S`、App ID `jp.co.kupac.prelis` 用で、使用する iPhone の UDID と `.p12` に対応する証明書を含めます。

- `~/KUPACLLC-Apple-Development.p12`
- `~/kupacprelismobileiosdevelopment.mobileprovision`

Ubuntu のリポジトリルートで実行します。

```sh
./scripts/ios/setup-device-signing.sh
```

スクリプトは `scripts/macos/.env` の `PRELIS_APPSTORE_P12_PASSWORD` を既存の読み取り処理で取得し、SSH の標準入力で Mac に渡します。`.env` をシェルとして実行したり、パスワードをログへ表示したりしません。Mac の開発専用キーチェーン `~/Library/Keychains/prelis-ios-development.keychain-db` に証明書と秘密鍵を読み込み、`codesign` のアクセスを許可します。キーチェーンのパスワードも `.p12` と同じです。証明書とプロファイルの対応、Team・App ID・有効期限を検証し、プロファイルを Xcode の保存先へ登録します。配布用の署名設定と既定のキーチェーンは変更しません。

Mac で直接セットアップする場合は、同期後に `bash scripts/ios/setup-device-signing.sh` を実行してパスワードを入力します。Ubuntu からセットアップした場合も、日常の起動に使う Mac のログインセッションで、一度キーチェーンを解除してください。

```sh
security unlock-keychain ~/Library/Keychains/prelis-ios-development.keychain-db
```

解除時は `.p12` と同じパスワードを入力します。キーチェーンが再度ロックされた場合もこのコマンドで解除します。自動ロックの間隔は6時間です。プロファイルを更新した場合は、同じ名前でホームへ保存してセットアップスクリプトを再実行します。

### 毎回の実機起動

1. iPhone を Mac に接続して信頼・ペアリングを完了し、デベロッパモードを有効にします。インストール・起動の間はロックを解除します。
2. iPhone と Mac を相互通信できる LAN に接続します。Mac のポート8081へ接続できる必要があります。iPhone のローカルネットワーク許可は許可してください。
3. Mac の2つのターミナルで、リポジトリルートから次を実行します。必要なら両ターミナルで `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を設定します。

```sh
# Mac ターミナル1
npm run start:mobile
```

```sh
# Mac ターミナル2（実際の端末名に置き換える）
npm run ios -w apps/mobile -- --mode Debug --device "iPhoneの名前" --no-packager
```

Debug / iphoneos は Xcode プロジェクトに記録した開発用署名とプロファイルを使います。Debug は `SKIP_BUNDLING=YES` のため JavaScript を同梱せず、Metro から読み込みます。ビルド時に生成する `ip.txt` の Mac アドレスを使うので、Mac のネットワークを変更した場合は再ビルドしてください。

`No script URL provided` が初回に出た場合は、ローカルネットワーク許可と Metro の稼働を確認して Reload またはアプリの再起動を行います。接続先の確認には、iPhone の Safari で `http://MacのIPアドレス:8081/status` を開き、`packager-status:running` が返ることを確認します。

Ubuntu の UI・共有 core の編集は、Mutagen の継続同期後に Fast Refresh で取り込みます。Swift・Objective-C・Xcode 設定の変更時はターミナル2のコマンドで再ビルドします。

Watchman が `MustScanSubDirs UserDropped` を報告して変更が反映されない場合は、Metro を停止し、この同期先だけ監視を作り直して再起動します。再起動後はアプリも Reload または再起動してください。

```sh
# Mac
watchman watch-del "$HOME/prelis-ios-remote/apps/mobile"
watchman watch-del "$HOME/prelis-ios-remote"
npm run start:mobile -- --reset-cache
```

2026-10-30 に iPhone SE（第3世代）/ iOS 27.0.1 で、上記の通常の `run-ios` による開発署名・インストール・起動、Metro からの JavaScript 読み込み、共有アイコンの表示を確認しました。Watchman の監視を作り直した後、Ubuntu の見出しを一時変更し、再ビルドや手動 Reload をせず実機の描画済みテキストとスクリーンショットへ反映されることを確認しています。文言を元に戻した際の Fast Refresh も確認済みです。同じ設定による iPhone 18 Pro Simulator の Debug ビルド・起動と、署名セットアップの再実行も確認しました。日記・音声など各機能の実機操作確認は別途行います。

## Metro を使わない Release ビルド

### Simulator と App Store 提出用を一括生成する

Mac の Metro を停止してから、Ubuntu で実行します。

```sh
./scripts/ios/build-all.sh
```

Mac のホームに `KUPACLLC-Apple-Distribution.p12` と `kupacprelismobileiosappstore.mobileprovision` を配置します。後者は Team `GLQCJ8YF9S`、App ID `jp.co.kupac.prelis`、名前 `kupac-prelis-mobile-ios-appstore` の App Store Connect 用プロファイルです。パスワードは macOS 版と共通の `scripts/macos/.env` の `PRELIS_APPSTORE_P12_PASSWORD` を読み、SSH の標準入力で渡します。

共通の同期・`npm ci`・`pod install --deployment` の後に、Release / Simulator と Release / iphoneos Archive を別々にビルドします。Simulator は arm64・x86_64、実機用は arm64 です。バージョンとビルド番号は Xcode の Release 設定の `MARKETING_VERSION`・`CURRENT_PROJECT_VERSION` を両方で使います。再提出時はビルド番号を更新してください。
Pod の導入には上記の `prepare-pods-on-mac.sh` を使用し、ツールの固定と設定ファイルの前後検証も共通で行います。

実機用は一時キーチェーンへ配布証明書を読み込み、Archive を作成して `xcodebuild -exportArchive` の `app-store-connect` / `destination=export` で IPA を生成します。キーチェーンの既定値と検索対象は終了時に復元し、一時キーチェーンは削除します。開発用署名は既存の Debug 設定を使います。

| 成果物 | Ubuntu への回収先 |
| --- | --- |
| GitHub Releases 向け Simulator ZIP | `apps/mobile/ios/build/simulator/PrelisMobile-simulator.app.zip` |
| App Store Connect 提出用 IPA | `apps/mobile/ios/build/appstore/PrelisMobile.ipa` |
| dSYM を含む保管用 Archive ZIP | `apps/mobile/ios/build/appstore/PrelisMobile.xcarchive.zip` |
| ビルド内容・署名の検証結果 | `apps/mobile/ios/build/{simulator,appstore}/verification.json` |
| 全成果物の SHA-256 一覧 | `apps/mobile/ios/build/ios-release-artifacts.sha256` |

アプリの Bundle ID、プラットフォーム、CPU、バージョンの一致、JavaScript・共有 PNG・アプリアイコンの収録、実機用の署名・証明書とプロファイルの対応・開発用 Entitlement の不在を検証します。回収後も SHA-256 と ZIP/IPA の整合性を検証してから保存します。失敗した工程で停止し、Mac の `apps/mobile/ios/build/logs/` にログを残します。

Simulator ZIP と IPA は Metro を使わずに実行するための成果物です。GitHub Release の公開、App Store Connect へのアップロード、Apple 側の検証・審査提出はこのスクリプトでは行いません。Archive の作成・IPA のローカル検証成功と、Apple 側の受理・審査合格は別に確認します。[Apple の配布手順](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)も参照してください。

2026-10-30 に Xcode 27.1 / Mac 標準 Bash 3.2 で一括生成を実行し、version `1.0` / build `1` の Simulator ZIP、Apple Distribution 署名済み IPA、dSYM を含む Archive ZIP を Ubuntu へ回収しました。全5ファイルの SHA-256、ZIP/IPA の整合性、共有 PNG 全11枚とアプリアイコンの同梱、署名とプロファイルの対応を確認済みです。ZIP 内のアプリを iPhone 18 Pro Simulator へインストールし、Metro が停止した状態でホーム画面とアプリ内アイコンの表示を確認しました。ビルド後の既定キーチェーンと検索対象の復元も確認しています。App Store Connect へのアップロード・Apple 側の検証・審査は未実施です。

### Simulator 用だけ生成する

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

## App Store Connect へのアップロード

macOS 版と同様に、ビルドとは別のコマンドで回収済み IPA を明示します。

```sh
./scripts/ios/upload-appstore.sh \
  apps/mobile/ios/build/appstore/PrelisMobile.ipa
```

アップロードせず Apple 側の検証だけ行う場合は、先頭引数に `--validate-only` を追加します。このモードも App Store Connect と通信します。

```sh
./scripts/ios/upload-appstore.sh --validate-only \
  apps/mobile/ios/build/appstore/PrelisMobile.ipa
```

`build-all.sh` が回収したディレクトリ構成と `ios-release-artifacts.sha256` を保持してください。スクリプトは一覧の IPA の SHA-256 と指定ファイルを比較し、Mac の `~/prelis-ios-remote/apps/mobile/ios/build/appstore/PrelisMobile.ipa` のコピーとも一致することを確認します。指定した IPA のビルド後に Mac で再ビルドして内容が変わっている場合は停止します。ビルド、ソース同期、IPA の転送、再署名は行いません。

認証は macOS 版と共通の `scripts/macos/.env` の `PRELIS_APPSTORE_API_KEY_ID`・`PRELIS_APPSTORE_API_ISSUER_ID` と、Mac 上の `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` を使用します。秘密鍵の内容を Ubuntu へコピーしません。スクリプト本体は SSH の標準入力で送るため、アップロード用スクリプトの事前同期は不要です。

Mac で IPA を一時コピーし、実機用 arm64、Bundle ID、バージョン、JavaScript・アセット、署名、プロファイルの有効期限、証明書とプロファイルの対応、配布用 Entitlements を確認します。そのコピーを [Apple が案内する](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) `xcrun altool` で検証し、検証成功後にアップロードします。エラー時は停止し、自動再試行は行いません。

アップロード後の Apple 側の処理完了、提出するビルドの選択、メタデータの入力、審査開始は App Store Connect で別途行います。アップロード成功と審査提出完了は区別してください。

2026-10-30 にスクリプトを追加し、シェルと埋め込み Python の構文、差分を静的確認しました。ユーザーの指示によりスクリプトの実行、Apple 側の検証、アップロードは行っていません。

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
xcrun simctl launch "iPhone 18 Pro" jp.co.kupac.prelis
```

画面が見えない場合は、`xcrun simctl io "iPhone 18 Pro" screenshot /tmp/prelis-ios.png` でスクリーンショットを保存できます。Bundle ID は実機と同じ `jp.co.kupac.prelis` です。

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

# Simulator ZIP と提出用 IPA / Archive の一括生成（パスワードは対話入力）
bash scripts/ios/build-on-mac.sh --all
```

Mac の `xcode-select` が Command Line Tools を指している場合も、スクリプトは `/Applications/Xcode.app` を使用します。生成先は Mac 側の `apps/mobile/ios/build/` です。

## ネイティブ処理

[iOS の `PrelisNative`](../../apps/mobile/ios/PrelisMobile/PrelisNative.m) は [Android 版](../../apps/mobile/android/app/src/main/java/com/prelismobile/PrelisModule.kt) と同じ [JavaScript API](../../apps/mobile/src/native.ts) を提供します。日記と終了音はアプリ内の Application Support に保存します。音声は iOS のファイル選択画面から MP3/WAV を 10 MB 以下で取り込みます。ビルド成功とホーム表示だけでは、各 API の操作確認は完了しません。
