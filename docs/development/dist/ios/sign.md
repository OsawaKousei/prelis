# iOS 配布物のビルド・署名

App Store Connect 提出用の署名付き IPA と、Simulator 向けの ZIP を Mac で作成し、Ubuntu へ回収して検証・頒布する手順です。
コマンドは、特記がない限り Ubuntu 側のリポジトリルートで実行します。
開発環境・ソース同期・開発起動・バージョン更新は [モバイル開発](../../mobile.md)、IPA の提出とストア公開は [App Store での頒布](app-store.md)を参照してください。

## iOS 版の配布構成

| 配布形式 | 利用方法 | 署名 | 更新方法 |
| --- | --- | --- | --- |
| App Store Connect 用 IPA | アップロード後、TestFlight または App Store から実機へ配信する | Apple Distribution と App Store Connect 用 Provisioning Profile | TestFlight / App Store から更新する |
| Simulator 用 `.app` の ZIP | Mac の iOS Simulator へインストールする | 開発チームの署名なし | 新しい `.app` を Simulator へインストールする |
| `.xcarchive` の ZIP | アプリと dSYM をリリース単位で保管する | Archive 内の実機用アプリは Apple Distribution | 利用者向けのインストール形式ではない |

ビルドを担当するのは [build-all.sh](../../../../scripts/ios/build-all.sh) と [build-on-mac.sh](../../../../scripts/ios/build-on-mac.sh)です。
現行スクリプトは App Store Connect 用 IPA を生成します。Ad Hoc・Enterprise・代替配布向けの IPA は生成しません。

## 署名の準備

[共通セットアップ](../../architecture.md#共通セットアップ)・[iOS の環境準備](../../mobile.md#ios)・[バージョンの更新](../../mobile.md#バージョンを揃える)を完了し、`npm run check` を通します。Simulator 単独ビルドでは、以下の配布用証明書・プロファイルの準備は不要です。
配布ビルドでは Mac 上の `xcodebuild`・`codesign`・`security`・`lipo`・`ditto`・`shasum`・`python3`・`openssl`・`curl`、Ubuntu 上の `python3`・`ssh`・`scp`・`tar`・`unzip` を使います。依存の取得と Apple WWDR 中間証明書の取得にはネットワーク接続が必要です。

### 配布用の識別情報・証明書・プロファイル

| 内容 | 現行スクリプトが使用する値 |
| --- | --- |
| Bundle ID | `jp.co.kupac.prelis` |
| Team ID | `GLQCJ8YF9S` |
| 配布用証明書と秘密鍵 | Mac 上の `~/KUPACLLC-Apple-Distribution.p12` |
| 署名 ID | `Apple Distribution: KUPAC LLC (GLQCJ8YF9S)` |
| App Store Connect 用プロファイル | Mac 上の `~/kupacprelismobileiosappstore.mobileprovision` |
| プロファイル名 | `kupac-prelis-mobile-ios-appstore` |
| `.p12` のパスワード | Ubuntu の `scripts/ios/.env` の `PRELIS_IOS_DISTRIBUTION_P12_PASSWORD` |

設定は [.env.example](../../../../scripts/ios/.env.example)を `scripts/ios/.env` にコピーし、権限を `0600` にして用意します。接続先・Mac 作業パス・証明書とプロファイルのパス・Team ID・Bundle ID を iOS 用設定に集約しています。Team・Bundle ID・プロファイル名を変更する場合は、Xcode project の設定と Apple Developer 側の登録も揃えます。パスワードは SSH の標準入力で一時設定ファイルとして渡し、`.env` をシェルとして実行しません。リモートへ渡すのは実行する工程に必要な設定だけです。証明書・秘密鍵・パスワードをリポジトリや頒布物へ含めません。

移行期間は、iOS 用パスワード・API 情報が未指定なら、従来の `scripts/macos/.env` または環境変数にある値を利用できます。`PRELIS_MACOS_*` の接続先・作業パスは iOS へ適用しません。

プロファイルは上記の Team・App ID・配布証明書に対応し、有効期限内で、`get-task-allow=false` かつ端末 UDID の一覧を持たない App Store Connect 用を使います。実機開発用のプロファイルとは分けます。
既存アプリを更新する場合は同じアプリ登録と Bundle ID を使用し、証明書の更新時もプロファイルとの対応を確認します。

## 1. パッケージを作成する

Mac の Metro を停止してから実行します。同じ同期先で開発起動・依存準備・別の配布ビルドを同時実行しません。

### Simulator と提出用 IPA を一括生成する

```sh
./scripts/ios/build-all.sh
```

ソース同期後、Mac 上で配布証明書を一時キーチェーンへ読み込み、署名試行とプロファイルの検証を行います。続いて `npm ci`・固定版ツールによる Pod 準備、Release / Simulator のビルド、Release / iphoneos の Archive 作成を実行します。
`xcodebuild -exportArchive` の `method=app-store-connect`・`destination=export` で IPA を生成します。Simulator は arm64・x86_64、実機用は arm64 です。一時キーチェーンは終了時に削除し、既定キーチェーンと検索対象を復元します。

| 成果物 | Ubuntu への回収先（Mac 側も同じリポジトリ相対パス） |
| --- | --- |
| Simulator ZIP | `apps/mobile/ios/build/release/all/simulator/PrelisMobile-simulator.app.zip` |
| 提出用 IPA | `apps/mobile/ios/build/release/all/appstore/PrelisMobile.ipa` |
| dSYM を含む Archive ZIP | `apps/mobile/ios/build/release/all/appstore/PrelisMobile.xcarchive.zip` |
| Simulator の検証結果 | `apps/mobile/ios/build/release/all/simulator/verification.json` |
| IPA の検証結果 | `apps/mobile/ios/build/release/all/appstore/verification.json` |
| ビルド入力のハッシュとファイル一覧 | `apps/mobile/ios/build/release/all/build-inputs.json` |
| 上記6ファイルの SHA-256 一覧 | `apps/mobile/ios/build/release/all/ios-release-artifacts.sha256` |

検証済みの一式をステージング領域へ回収し、一覧の欠落・重複・想定外パス、各ファイルの SHA-256 と ZIP / IPA の整合性を確認して出力ディレクトリを置き換えます。置換に失敗した場合は以前の成果物へ戻します。一括生成と Simulator 単独ビルドは別の出力ディレクトリを使います。失敗した工程で停止し、Mac の `apps/mobile/ios/build/logs/` に工程別ログを残します。
作業用成果物は上記の `build/release/` に残し、同時に Ubuntu / Mac の `dist/ios/v<version>/build-<build>/all/` に配布・保管用の一式を保存します。バージョンとビルド番号は生成済みアプリの検証記録から取得します。別の版・ビルドは別ディレクトリになり、同じ版・ビルドの再実行は一式を検証してから置き換えます。コミット・タグ・動作確認記録も対象ビルドに紐付けて残します。

```text
dist/ios/v1.0.1/build-2/
├── all/
│   ├── appstore/
│   │   ├── PrelisMobile.ipa
│   │   ├── PrelisMobile.xcarchive.zip
│   │   └── verification.json
│   ├── simulator/
│   │   ├── PrelisMobile-simulator.app.zip
│   │   └── verification.json
│   ├── build-inputs.json
│   └── SHA256SUMS
└── simulator/                    # Simulator 単独ビルド
    ├── simulator/
    │   ├── PrelisMobile-simulator.app.zip
    │   └── verification.json
    ├── build-inputs.json
    └── SHA256SUMS
```

`dist/macos` と同様にバージョン別のディレクトリと `SHA256SUMS` を使います。iOS は同一公開バージョンでビルド番号を増やすため `build-<build>/` も設け、一括生成と Simulator 単独生成の入力が異なる場合に一式が混ざらないよう分離します。ログ、DerivedData、署名用の秘密情報は配布ディレクトリに含めません。生成物は Git 管理対象外です。

同期済みの Mac で直接一括生成する場合は、Mac の `~/prelis-ios-remote` で次を実行します。パスワードは Mac 側の iOS 設定・環境変数または対話入力で渡し、成果物は Mac 側に生成します。Ubuntu への回収は行いません。Mac 側の `dist/ios/` への配置は行います。

```sh
bash scripts/ios/build-on-mac.sh --all
```

### iOS Simulator の動作確認用ビルドを作る

Simulator 用だけ生成する場合は、Ubuntu 側で次を実行します。

```sh
./scripts/ios/build-ios-simulator.sh
```

同期・Mac 上の依存準備・署名なしの Release / Simulator ビルドを行い、JavaScript と画像を同梱した `.app` を ZIP 化して Ubuntu へ回収します。出力先は `apps/mobile/ios/build/release/simulator/` で、`simulator/` 内に ZIP と検証結果、直下に `build-inputs.json` と `ios-simulator-artifacts.sha256` を保存します。同時に `dist/ios/v<version>/build-<build>/simulator/` に ZIP・検証結果・入力記録・`SHA256SUMS` を保存します。一括生成時の成果物は置き換えません。回収時に SHA-256 と ZIP の整合性を検証します。
Ubuntu への回収を伴わず Mac で直接作る場合は、同期後に Mac の `~/prelis-ios-remote` で `bash scripts/ios/build-on-mac.sh` を実行します。

この成果物は Simulator 専用です。インストール・起動は [起動確認](#3-インストール起動を確認する)に従い、Metro を停止した状態で確認します。

## 2. 成果物と署名を確認する

一括生成した場合は、次を実行します。パスのバージョン・ビルド番号は対象に合わせます。

```sh
release_dir=dist/ios/v1.0.1/build-2/all
(cd "$release_dir" && sha256sum -c SHA256SUMS)
unzip -t "$release_dir/simulator/PrelisMobile-simulator.app.zip"
unzip -t "$release_dir/appstore/PrelisMobile.ipa"
unzip -t "$release_dir/appstore/PrelisMobile.xcarchive.zip"
cat "$release_dir/simulator/verification.json" "$release_dir/appstore/verification.json"
```

Simulator 用だけ生成した場合は、そのビルドの一覧と検証結果を使用します。

```sh
release_dir=dist/ios/v1.0.1/build-2/simulator
(cd "$release_dir" && sha256sum -c SHA256SUMS)
unzip -t "$release_dir/simulator/PrelisMobile-simulator.app.zip"
cat "$release_dir/simulator/verification.json"
```

[verify-release.py](../../../../scripts/ios/verify-release.py) がビルド時に検証した内容と、提出予定の設定・証明書を照合します。

- Bundle ID とプラットフォーム、CPU が配布形式に一致すること。
- `version`・`build` が提出予定の公開バージョン・ビルド番号に一致すること。スクリプトは Simulator・Archive・IPA 間の一致を検証しますが、App Store Connect の提出履歴は確認しません。
- `sourceSHA256` が同じ入力を示し、`build-inputs.json` のハッシュと一致すること。ビルドは開始時・工程間・終了時に入力の変更を検出すると成果物確定を停止します。
- JavaScript バンドル・共有 PNG・アプリアイコンが収録されていること。
- 実機用アプリの `codesign --verify --deep --strict` が成功し、署名証明書が埋め込みプロファイルに含まれること。レポートの `certificateSHA1`・`profileUUID` を使用した証明書・プロファイルと照合します。
- App ID・Team ID が一致し、開発用 Entitlement が有効になっていないこと。

SHA-256 の成功は回収後の内容が同じであることの確認です。Apple 側の検証・受理は [App Store Connect への提出手順](app-store.md)で別途確認します。

## 3. インストール・起動を確認する

ビルド後は Mac で対象 Simulator を起動し、生成されたアプリをインストール・起動します。Metro を停止した状態で確認します。

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

頒布対象の ZIP を確認する場合は、ZIP を展開した `.app` のパスを `simctl install` に指定します。
日記の保存・再読込、タイマーと音声ファイルの操作、パスワード生成・コピーを確認し、結果を対象ビルドに紐付けて残します。画面寸法の条件は [ウィンドウの互換性要件](../../mobile.md#ウィンドウの互換性要件)を参照してください。

App Store Connect 用 IPA は実機へ直接インストールする配布形式として扱いません。[TestFlight からの確認](app-store.md#3-testflight-からインストールして確認する)を実施します。Simulator や Debug アプリの確認だけでは、実機配信版の確認は完了しません。

## 4. Simulator ZIP を直接頒布する

GitHub Releases などへは、確認済みの `PrelisMobile-simulator.app.zip` とその SHA-256、対象バージョン・ビルド番号、必要な Mac / Simulator 環境、インストール方法を掲載します。Simulator 専用であることを明記します。
IPA と Archive ZIP は提出・保管用として管理します。一般の iPhone / iPad 向けには、TestFlight の参加案内または公開後の App Store 掲載 URL を案内します。

## 注意

- 一括ビルドは成果物の作成・ローカル検証・回収までを行います。GitHub Releases の公開、App Store Connect へのアップロード、審査提出は含みません。
- 旧資料の 2026-10-30 の記録では、旧 CLI 版 `1.0 (1)` の一括生成・署名・回収・Simulator のホーム表示を確認しています。この記録を現行 Expo 版の配布確認として扱いません。
- 本文書の手順やスクリプトの回帰テストは Apple 側の受理・公開を示す記録ではありません。配布確認と公開状況はリリースごとに記録します。

## スクリプト改修時の確認記録

2026-11-01 に Node.js 24.19.0 / Xcode 27.1 の開発用 Mac で、Simulator 単独ビルド、一括ビルドによる署名付き Archive / IPA の生成、Ubuntu への回収と成果物一式の SHA-256 検証を確認しました。生成物の公開バージョンは `1.0.1`、ビルド番号は `2` です。Simulator・Archive・IPA の入力ハッシュとバージョンが一致し、終了後にキーチェーン設定の復元とロック解除も確認しました。

二重起動の拒否、macOS / iOS 間の共通署名ロック、Xcode project 正規化の往復処理も実環境で確認しています。Apple 側への検証要求・アップロードは実行していません。

同日の専用 iPhone 18 Pro / iOS 27.0 Simulator で、日記の保存・再読込、パスワード生成・コピー、音声の追加・試聴・選択の再読込、1分タイマーの完了、音声削除後の再起動を含む UI テストが成功しました。テストの古い表示参照とキーボード・数値入力の操作を更新し、失敗時にも `summary.json` を残すようにしています。Ubuntu 上の回帰テスト26件、モバイルの Lint・型チェックも成功しています。


`dist/ios` 対応では、同じ `1.0.1 (2)` の検証済み成果物を Ubuntu / Mac の両方へ配置し、回収処理からの自動配置と全ファイルの SHA-256 を確認しました。改修後の回帰テスト31件と Shell / Python の構文確認も成功しています。この配置確認では再ビルドや Apple 側への送信は実行していません。

## 既存成果物の再配置

既存の検証済み成果物を再ビルドせずに `dist/ios/` へ配置し直す場合は、Ubuntu / Mac のそれぞれのリポジトリで次を実行できます。元のチェックサム、検証記録のバージョン・ビルド番号・入力ハッシュを確認してから配置します。

```sh
python3 scripts/ios/internal/artifacts.py distribute apps/mobile/ios/build/release/all all --destination dist/ios
python3 scripts/ios/internal/artifacts.py distribute apps/mobile/ios/build/release/simulator simulator --destination dist/ios
```
