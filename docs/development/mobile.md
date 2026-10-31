# モバイル開発

コマンドは、特記がない限り開発・ビルドする OS 上のリポジトリのルートで実行します。Android は Ubuntu、iOS は Ubuntu で編集したソースを Mac の `~/prelis-ios-remote` へ同期して開発する構成です。iOS の Metro・ビルド・Simulator は Mac 上で実行します。
現行のモバイル版は Expo SDK 58 / React Native 0.88 を使用します。デスクトップで確認した共通機能を、モバイルの UI と操作に合わせて反映します。
Android の署名付き成果物の作成・直接頒布は [ビルド・署名手順](dist/android/sign.md)、ストアへの提出・公開は [Google Play での頒布](dist/android/google-play.md)を参照してください。

## ウィンドウの互換性要件

- Android・iOS の最小サポートサイズは **360×640 論理単位**（Android は dp、iOS は pt）です。Safe Area 適用前のアプリウィンドウ全体を基準にし、ヘッダー・タブを含めて収めます。
- ホーム・日記・タイマー・パスワード生成の初期表示は、ページ全体のスクロールなしで内容と主要操作を確認・利用できるようにします。
- 日記本文・エラーなどの内部スクロールと、カレンダー・設定を展開した後の縦スクロールは許容します。スクロールを無効化して内容を隠す方法は使いません。
- キーボード表示時や文字拡大時も、入力・保存など必要な操作へ到達できることを確認します。仕様の詳細は [v0.1.3](../specs/v0.1.3.md#モバイルウィンドウサイズと表示)を参照してください。

### 360×640 の表示テスト

通常の `npm run check` は設定の開閉・状態保持を検証します。実際の画面寸法とスクロール範囲は、専用 Android エミュレーターと、起動中の Metro・ビルド済み Debug APK を使って次のコマンドで確認します。`ANDROID_SERIAL` は専用エミュレーターの番号に置き換えます。

```sh
ANDROID_SERIAL=emulator-5580 npm run test:mobile:window
```

テストは指定したエミュレーターに APK をインストールして実行時権限を付与し、表示を720×1280物理ピクセル・密度320 dpi（360×640 dp）・標準文字サイズへ一時変更します。全画面の初期スクロール動作と主要操作の可視性、設定展開後のスクロール、長文日記の内部スクロールを検証し、表示設定を最後に戻します。既存のデータを消去せず、日記の検証入力は保存しません。実機は対象にできません。APK の場所を変える場合は `PRELIS_ANDROID_APK`、各画面の PNG を保存する場合は `PRELIS_WINDOW_ARTIFACTS` に出力ディレクトリを指定します。

iOS も同じ React Native レイアウトを使用します。iOS Simulator では小さいウィンドウと Safe Area、キーボード表示を別途確認します。Android のテスト成功を iOS の実測結果として扱いません。

## 環境準備

Node.js・npm の準備と依存管理は [共通セットアップ](architecture.md#共通セットアップ)を参照してください。モバイル固有の条件は次のとおりです。ファイル監視には Watchman を使用します。
Metro は `apps/mobile/metro.config.js` で Watchman の使用を明示し、Linux で Node.js のディレクトリ監視を大量に追加して inotify の上限に達することを避けます。

Expo CLI の型付きルート生成は Node.js から Expo Router を読み込みます。ルート側のツールから参照できるよう、Expo Router と関連依存はルートの `node_modules` から解決できる配置を `package-lock.json` に記録しています。依存の取得にはリポジトリルートで `npm ci` を使用します。

iOS の `Podfile.lock` もこの配置に合わせ、ExpoRouter・RNReanimated・RNWorklets はルートの `node_modules` を参照します。依存の配置変更時は、Pod の参照パスと生成される podspec のチェックサムも揃えてから `pod install --deployment` で検証します。
Android の自動リンク設定もルートの `package-lock.json` を監視し、依存の配置変更時にネイティブライブラリの参照先を再生成します。

### Android

- このホストの JDK・SDK の導入先と署名鍵・設定ファイルは [Android の環境設定](../environment/android/signing-key.md)を参照してください。
- JDK 17、Android Studio、Android SDK を用意します。
- Android Studio の SDK Manager で、次の SDK・ツールをインストールします。SDK Tools の **Show Package Details** で個別バージョンを選択できます。

| 項目 | このワークスペースで使用する値 |
| --- | --- |
| Android SDK Platform / compile SDK | API 37 |
| target SDK / min SDK | 36 / 24 |
| Android SDK Build-Tools | 37.0.0 |
| NDK (Side by side) | 27.1.12297006 |
| CMake | 3.22.1（旧手順の開発環境で使用。依存更新時はビルドログで要求版を確認） |
| Gradle wrapper | 9.4.1 |
| Android SDK Platform-Tools | `adb` を使用 |
| Android Emulator | エミュレーターを使う場合に必要 |
| Android SDK Command-line Tools | SDK を CLI で管理する場合に導入 |

SDK・NDK の既定値は Expo の Gradle プラグインと React Native の version catalog から取得します。入口は [android/build.gradle](../../apps/mobile/android/build.gradle) と [settings.gradle](../../apps/mobile/android/settings.gradle)、Gradle の版は [wrapper の設定](../../apps/mobile/android/gradle/wrapper/gradle-wrapper.properties)で確認します。Gradle 自体の個別インストールは不要です。初回ビルドには依存の取得先へのネットワーク接続と SDK ライセンスの受諾が必要です。

`JAVA_HOME` に JDK 17、`ANDROID_HOME` に Android SDK の導入先を設定し、`PATH` に JDK の `bin`、SDK の `platform-tools`・`emulator` を追加します。Command-line Tools を使う場合は、その `bin` も追加します。

```sh
java -version
adb version
watchman --version
```

SDK の場所は、Git 管理対象外の `apps/mobile/android/local.properties` に `sdk.dir=/実際の/Android/Sdk` と記載することもできます。ビルド用の API 37 と、アプリを実行する端末・エミュレーターの API レベルは区別します。

### iOS

- Mac に Xcode 本体をインストールし、初回起動時のライセンス・追加コンポーネントの設定と、使用する iOS Simulator ランタイムの導入を完了します。
- Mac にも Node.js・npm を用意し、ルートの `.nvmrc` と `package.json` の条件を満たす版を使用します。
- Ruby 3.2 以降と Bundler 4.0.20 を用意します。CocoaPods 1.17.0・xcodeproj 1.28.1 と間接依存は [Gemfile.lock](../../apps/mobile/Gemfile.lock)、Pod の依存は [Podfile.lock](../../apps/mobile/ios/Podfile.lock) に固定します。
- Ubuntu に Mutagen・OpenSSH クライアント・`timeout`（coreutils）を用意し、Mac のリモートログインを有効にして SSH 鍵認証で接続できるようにします。現行の iOS スクリプトの接続先は `kousei@192.168.10.22`、同期先は `~/prelis-ios-remote` です。macOS デスクトップ版の同期先とは分けます。
- Simulator 用の確認ビルドを Ubuntu へ回収する場合は、Ubuntu に `sha256sum`・`unzip` も必要です。

Simulator の実行には署名証明書や Apple Developer Team の設定は不要です。iPhone 実機には開発署名が必要です。

#### iPhone 実機用の開発署名

Mac のホームに `KUPACLLC-Apple-Development.p12` と `kupacprelismobileiosdevelopment.mobileprovision` を用意します。プロファイルは iOS App Development、Team `GLQCJ8YF9S`、App ID `jp.co.kupac.prelis` 用で、使用する iPhone の UDID と `.p12` に対応する証明書を含めます。

Ubuntu 側の `scripts/macos/.env` に `PRELIS_APPSTORE_P12_PASSWORD` を設定し、次を実行します。ファイルがない場合は [.env.example](../../scripts/macos/.env.example)を基に作成します。

```sh
./scripts/ios/setup-device-signing.sh
```

スクリプトは同期後、Mac の開発用キーチェーン `~/Library/Keychains/prelis-ios-development.keychain-db` に証明書と秘密鍵を読み込み、プロファイルとの対応・Team・App ID・有効期限を検証して登録します。パスワードは SSH の標準入力で渡し、`.env` はシェルとして実行しません。

日常の起動に使う Mac のログインセッションで、キーチェーンを解除します。パスワードは `.p12` と同じです。6時間後の自動ロック時も同じ操作を行います。

```sh
security unlock-keychain ~/Library/Keychains/prelis-ios-development.keychain-db
```

プロファイルを更新した場合は、同じ名前で Mac のホームに保存し、セットアップスクリプトを再実行します。

## 開発起動と動作確認用ビルド

### Android で開発起動する

Android Studio の Device Manager から AVD を起動するか、USB デバッグを有効にした端末を接続し、`adb devices` で対象が `device` と表示されることを確認します。2つのターミナルで Metro とアプリを起動します。

```sh
# ターミナル1: Metro（ポート8081）
npm run start:mobile
```

```sh
# ターミナル2: Debug APK のビルド・インストール・起動
npm run android -- --no-bundler
```

現行の起動コマンドは Expo CLI を使用するため、Metro を別途起動するときは `--no-bundler` を指定します。モバイル UI と共有 core の変更は Fast Refresh で確認し、Gradle・ネイティブ依存を変更したときは再ビルドします。

Metro に接続できない場合は、起動状態を確認して `adb reverse tcp:8081 tcp:8081` を実行します。複数端末がある場合は `adb -s <serial> reverse tcp:8081 tcp:8081` で対象を指定します。


### iOS で開発起動する

まず Ubuntu 側で同期スクリプトを実行します。

```sh
./scripts/ios/create-ios-sync.sh
```

Mutagen セッション `prelis-ios` を作成または再利用し、Ubuntu から Mac へ `one-way-safe` で同期します。除外設定が変わった場合は、同期先のファイルを保持してセッションを作り直します。同期完了・接続状態・競合なし・必要ファイルの存在と不要ディレクトリの不在を確認して正常終了してから、次に進みます。Mutagen データは `.mutagen-ios/` に保存し、`MUTAGEN_SSH_PATH` は解除します。

同期対象はルートの npm 定義と `.nvmrc`、モバイルの共通コードと `ios/`、共有 core・アイコン、iOS の Mac 側スクリプトです。Android・旧モバイル・デスクトップ・ウェブ・ドキュメント・他 OS のスクリプト・認証情報・生成物は除外します。`node_modules`・`Pods`・CocoaPods workspace・`DerivedData` は Mac 側で生成して再利用します。

ソースは Ubuntu 側で編集します。`one-way-safe` は Mac 側の異なる内容を上書きしないため、競合時は差分を確認し、必要な変更を退避・反映して Ubuntu 側を正として揃えます。以前に同期した除外対象は自動削除されないため、不要ディレクトリが残って停止した場合は同期先を確認・整理します。

初回と依存変更時は、Metro を停止した状態で Mac 上の依存を準備します。

```sh
cd ~/prelis-ios-remote
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
npm ci
bash scripts/ios/prepare-pods-on-mac.sh
```

Pod の準備には必ず `prepare-pods-on-mac.sh` を使います。固定版の Ruby ツールで `pod install --deployment` を実行し、Xcode 設定や `Podfile.lock` が変わった場合は停止します。依存準備の最後には、この同期先の Watchman 監視を作り直します。

`npm run ios` も同じ `bundle-on-mac.sh` を通して Expo CLI を起動し、不足している gem があれば固定版をインストールします。`Gemfile.lock` は Mac 用の `ffi` を固定しているため、`BUNDLE_FORCE_RUBY_PLATFORM` は使用しません。以前の設定で `Could not find ffi-1.17.4 in locally installed gems` が発生した場合は、Ubuntu 側の修正を同期してから同じ起動コマンドを再実行してください。Ruby ツールの更新や `Gemfile.lock` の削除は不要です。

Mac の2つのターミナルで Metro と Simulator 用 Debug アプリを起動します。`SIMULATOR_UDID` には一覧の対象デバイスの UDID を設定します。

```sh
# Mac ターミナル1
cd ~/prelis-ios-remote
npm run start:mobile
```

```sh
# Mac ターミナル2
cd ~/prelis-ios-remote
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl list devices available
SIMULATOR_UDID='対象デバイスのUDID'
npm run ios -w apps/mobile -- --configuration Debug --device "$SIMULATOR_UDID" --no-bundler
```

画面の操作は Mac 実機または画面共有で行います。Ubuntu のモバイル UI・共有 core の変更は継続同期後に Fast Refresh で取り込みます。同期完了を明示的に待つ場合は同期スクリプトを再実行します。Swift・Objective-C・Xcode 設定の変更時は再ビルドし、依存変更時は Metro を停止して依存準備からやり直します。

Ubuntu で Xcode 設定を編集した場合は、固定版 xcodeproj の保存形式に正規化して差分を確認し、同期します。初回は Mac 側に必要なスクリプトと Gemfile.lock が同期されている必要があります。

```sh
./scripts/ios/normalize-xcode-project.sh
git diff -- apps/mobile/ios/PrelisMobile.xcodeproj/project.pbxproj
./scripts/ios/create-ios-sync.sh
```

### iPhone 実機で開発起動する

開発署名と依存準備を済ませ、iPhone を Mac に接続して信頼・ペアリングとデベロッパモードの有効化を行います。インストール・起動中は端末のロックを解除します。
iPhone と Mac を相互通信できる LAN に接続し、Mac のポート8081へ接続できるようにします。iPhone のローカルネットワーク許可も必要です。

Mac ターミナル1で Metro を起動したまま、ターミナル2の起動コマンドを次に置き換えます。

```sh
npm run ios -w apps/mobile -- --configuration Debug --device "iPhoneの名前" --no-bundler
```

Debug は JavaScript を同梱せず Metro から読み込みます。Mac のネットワークを変更した場合は、接続先を更新するため再ビルドします。接続できない場合は、iPhone の Safari で `http://MacのIPアドレス:8081/status` を開き、`packager-status:running` が返ることと、ローカルネットワーク許可を確認してアプリを Reload または再起動します。

### iOS Simulator の動作確認用ビルドを作る

Mac の Metro を停止してから、Ubuntu 側で次を実行します。

```sh
./scripts/ios/build-ios-simulator.sh
```

同期・Mac 上の依存準備・署名なしの Release / Simulator ビルドを行い、JavaScript と画像を同梱した `.app` を ZIP 化して Ubuntu へ回収します。出力は `apps/mobile/ios/build/simulator/PrelisMobile-simulator.app.zip`、SHA-256 一覧は `apps/mobile/ios/build/ios-simulator-artifacts.sha256` です。回収時に SHA-256 と ZIP の整合性を検証します。Ubuntu からの回収を伴わず Mac で直接作る場合は、同期後に `bash scripts/ios/build-on-mac.sh` を実行します。

ビルド後は Mac で対象 Simulator を起動し、生成されたアプリをインストール・起動します。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ~/prelis-ios-remote
xcrun simctl list devices available
SIMULATOR_UDID='対象デバイスのUDID'
xcrun simctl boot "$SIMULATOR_UDID" # 停止中のみ
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
xcrun simctl install "$SIMULATOR_UDID" apps/mobile/ios/DerivedData/Build/Products/Release-iphonesimulator/PrelisMobile.app
xcrun simctl launch "$SIMULATOR_UDID" jp.co.kupac.prelis
```

この成果物は Simulator 専用です。Metro を停止した状態での確認に使用します。

## バージョンを揃える

リリース時は、モバイル版の npm パッケージ・画面表示と、Android・iOS のネイティブ設定を確認します。

| ファイル | 更新する項目 |
| --- | --- |
| [apps/mobile/package.json](../../apps/mobile/package.json) | `version` |
| [package-lock.json](../../package-lock.json) | `packages["apps/mobile"].version` |
| [apps/mobile/src/app/index.tsx](../../apps/mobile/src/app/index.tsx) | ホーム画面の `v<version>` 表示 |
| [apps/mobile/app.json](../../apps/mobile/app.json) | `expo.version`・`android.versionCode`・`ios.buildNumber` |
| [apps/mobile/android/app/build.gradle](../../apps/mobile/android/app/build.gradle) | `defaultConfig.versionName`・`versionCode` |
| [apps/mobile/ios/PrelisMobile.xcodeproj/project.pbxproj](../../apps/mobile/ios/PrelisMobile.xcodeproj/project.pbxproj) | Debug / Release の `MARKETING_VERSION`・`CURRENT_PROJECT_VERSION` |
| [apps/mobile/ios/PrelisMobile/Info.plist](../../apps/mobile/ios/PrelisMobile/Info.plist) | `CFBundleShortVersionString`・`CFBundleVersion` |

現行では npm パッケージ・画面表示は `0.1.3`、ネイティブ設定は `1.0.1` / ビルド番号 `2` です。リリース時に採用する版を確認して更新します。ネイティブの表示バージョンは `expo.version` と Android の `versionName`、iOS の `MARKETING_VERSION`・`CFBundleShortVersionString` で揃えます。iOS の Info.plist はバージョンが直接記載されているため、Xcode 設定と両方を更新します。
Android の更新時は `versionCode`、iOS の再提出時はビルド番号を増やし、app.json と各ネイティブ設定を揃えます。ビルド後は画面表示と成果物内のバージョンを確認します。

## 設定の所在とアイコン更新

| 内容 | ファイル |
| --- | --- |
| Expo のアプリ名・識別子・向き・アイコン・プラグイン | `apps/mobile/app.json` |
| 起動コマンド・Expo / React Native の依存 | `apps/mobile/package.json` |
| Metro のファイル監視 | `apps/mobile/metro.config.js` |
| Android の Gradle プラグイン・SDK 設定の入口 | `apps/mobile/android/build.gradle`・`settings.gradle` |
| Android の識別子・バージョン・署名・ビルド種別 | `apps/mobile/android/app/build.gradle` |
| Android の権限・起動 Activity | `apps/mobile/android/app/src/main/AndroidManifest.xml` |
| Android の Hermes・ビルド対象 CPU・Gradle オプション | `apps/mobile/android/gradle.properties` |
| iOS のビルド・署名・最低対応 OS | `apps/mobile/ios/PrelisMobile.xcodeproj/project.pbxproj` |
| iOS の表示名・向き・ローカル接続など | `apps/mobile/ios/PrelisMobile/Info.plist` |
| iOS の Entitlements | `apps/mobile/ios/PrelisMobile/PrelisMobile.entitlements` |
| iOS の Pod 依存・Expo ネイティブ設定 | `apps/mobile/ios/Podfile`・`Podfile.lock`・`Podfile.properties.json` |
| CocoaPods / xcodeproj の固定版 | `apps/mobile/Gemfile`・`Gemfile.lock` |
| 画面構成・タブ・Safe Area | `apps/mobile/src/app/_layout.tsx` |

`android/`・`ios/` は Git 管理するネイティブプロジェクトです。app.json の変更は必要なネイティブ設定にも反映します。通常の開発では、手動の署名設定を失う `expo prebuild --clean` は実行しません。

アイコンの正本と更新・生成手順は [共有アイコン](../../packages/icons/README.md)を参照してください。Android のランチャー画像は `apps/mobile/android/app/src/main/res/`、iOS のアプリアイコンは `apps/mobile/ios/PrelisMobile/Images.xcassets/AppIcon.appiconset/` に生成します。Expo 側で参照する画像は app.json の設定も確認し、更新後はネイティブアプリを再ビルドします。
