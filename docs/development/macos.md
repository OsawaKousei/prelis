# macOS 向けデスクトップビルド

コマンドは、指定がない限りリポジトリのルートで実行します。共通の環境と設定は[デスクトップ開発](desktop.md)を参照してください。

## Mac App Store 向け署名済み App と提出用 PKG

```sh
# 初回のみ
cp scripts/macos/.env.example scripts/macos/.env
chmod 600 scripts/macos/.env
# scripts/macos/.env に PRELIS_APPSTORE_P12_PASSWORD を記入
# 2 枚の .p12 のパスワードが異なる場合だけ
# PRELIS_APPSTORE_INSTALLER_P12_PASSWORD も記入
./scripts/macos/build-appstore.sh
```

`kousei@192.168.10.22` へソースを同期し、Apple Distribution と Mac Installer Distribution の既存 `.p12` を一時キーチェーンに読み込みます。ローカルの `scripts/macos/.env` をシェルとして実行せず、許可したパスワード変数だけを読み込みます。環境変数が設定されている場合はそちらを優先し、パスワードを SSH の標準入力で Mac へ渡します。インストーラ用のパスワードが未指定なら Apple Distribution 用の値を使います。`.env` は Git 管理と Mac 同期から除外し、権限 `0600` を必須とします。Mac 側で直接スクリプトを実行する場合は、パスワード入力を求めます。

Mac のホームに `KUPACLLC-Apple-Distribution.p12`、`KUPACLLC-Mac-Installer-Distribution.p12`、`kupacprelisdesktopmacosappstore.provisionprofile` が必要です。`.p12` の権限は `0600` にします。Apple WWDR G3 中間証明書を Mac のログインキーチェーンへインストールしておきます。ビルド後、一時キーチェーンは削除されます。

一時キーチェーンへの証明書の読み込みと秘密鍵の署名アクセス設定は、[Tauri の CI 向け署名手順](https://v2.tauri.app/distribute/sign/macos/#signing-in-cicd-platforms)と同じ方式です。スクリプトは実行中だけ既定キーチェーンと検索先を切り替え、終了時に元へ戻します。

Mac 側では `tauri.appstore.conf.json` を重ね、Bundle ID `jp.co.kupac.prelis`、App Sandbox、ネットワーククライアント権限、埋め込み Provisioning Profile を適用します。Apple Silicon 専用の App Store ビルドは [Tauri の手順](https://v2.tauri.app/distribute/app-store/)に従って最低対応 macOS を `12.0` に設定します。通常のデスクトップ設定の Bundle ID と最低対応 macOS は変えません。アプリ内のファイルを一般ユーザーが読める権限にし、`codesign --verify --deep --strict`、署名 Entitlements、Bundle ID、最低対応 macOS、埋め込み Profile を確認します。続いて [Apple の手順](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)に従い、Mac Installer Distribution の署名 ID で `productbuild --component` を実行します。展開した PKG 内の権限と署名を再確認し、ZIP と PKG を回収してそれぞれ SHA-256 を照合します。

| 成果物 | 出力先 |
| --- | --- |
| 署名済み `.app` | Mac: `~/prelis-remote/apps/desktop/src-tauri/target/release/bundle/macos/PrelisDesktop.app` |
| 回収した `.app` の ZIP | ローカル: `apps/desktop/src-tauri/target/release/bundle/appstore/PrelisDesktop_<version>_<arch>_appstore.app.zip` |
| 提出用 `.pkg` | ローカル: `apps/desktop/src-tauri/target/release/bundle/appstore/PrelisDesktop_<version>_<arch>_appstore.pkg` |

`apps/desktop/src-tauri/signing/` は Git 管理と Mac 同期から除外します。Profile は Mac のホームからビルド時にコピーします。App Store Connect のアプリ登録、暗号化輸出規制の申告内容、Sandbox 内での機能操作、提出用 `.pkg` のアップロードは別途確認が必要です。

2026-10-29 に macOS 27.0.1、Xcode 27.1、Apple Silicon で `0.1.1` の署名済み `.app` を作成しました。`scripts/macos/.env` を読み込む非対話ビルドでも再生成しています。`codesign --verify --deep --strict`、App Sandbox と App ID の Entitlements、Bundle ID、埋め込み Profile、回収後の SHA-256 照合が通っています。アプリの起動・機能操作と App Store Connect への提出は今回未確認です。

2026-10-30 に同じ環境で `0.1.1` の提出用 `.pkg` を生成しました。`pkgutil --check-signature` は「3rd Party Mac Developer Installer: KUPAC LLC (GLQCJ8YF9S)」を表示し、展開した `PackageInfo` の識別子 `jp.co.kupac.prelis`、バージョン `0.1.1`、インストール先 `/Applications` を確認しています。ローカル回収後の SHA-256 も一致しました。App Store Connect へのアップロードと受理は未確認です。

同日の App Store Connect 検証で、初回の PKG は一般ユーザーが読めないアプリ内ファイル（90255）と、arm64 専用ビルドの最低対応 macOS 10.13（90869）により拒否されました。`umask` とアプリ内の権限、App Store 専用設定の最低対応 macOS を修正して再ビルドし、`Info.plist` と実行ファイルの最低対応 `12.0`、一般ユーザーが読めないファイル 0 件を確認しました。修正後の PKG は `altool --validate-app` で `VERIFY SUCCEEDED with no errors` となりました。

## App Store Connect へのアップロード

アップロードはビルドとは別のコマンドで行います。引数には `build-appstore.sh` が回収した PKG を明示します。

```sh
./scripts/macos/upload-appstore.sh \
  apps/desktop/src-tauri/target/release/bundle/appstore/PrelisDesktop_0.1.1_aarch64_appstore.pkg
```

アップロードせず App Store Connect の検証だけ行う場合は、同じコマンドの先頭引数に `--validate-only` を追加します。

スクリプトはローカルの `.pkg.sha256` と PKG のハッシュを比較し、同名の Mac 側 PKG とも一致することを確認します。`scripts/macos/.env` の `PRELIS_APPSTORE_API_KEY_ID` と `PRELIS_APPSTORE_API_ISSUER_ID` を読み込み、Mac 上の `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` を直接使います。実際の `.p8` の内容は `.env` に複製しません。PKG の署名、Bundle ID、最低対応 macOS、一般ユーザーの読み取り権限を確認してから、[Apple が案内する](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds) `xcrun altool` の検証とアップロードを実行します。ビルドやソース同期は実行しません。Mac 側に対応する PKG がない場合は、先にビルドしてください。

2026-10-30 に修正後の PKG を `--validate-only` で検証し、エラー 0 件を確認しました。アップロードは未実行です。アップロード成功後も App Store Connect での処理完了と審査提出は別途確認します。

## GitHub Releases 向け Developer ID 署名

```sh
./scripts/macos/build-github.sh
```

`scripts/macos/.env` の `PRELIS_GITHUB_P12_PASSWORD` を読み込み、Mac のホームにある既存の `KUPACLLC-Developer-ID-Application.p12` を一時キーチェーンへ読み込みます。`tauri.github.conf.json` だけを重ねて、Developer ID Application 署名と Hardened Runtime を適用します。App Store 用の Sandbox と Provisioning Profile は含めません。ビルドは `universal-apple-darwin` を対象に一度だけ実行します。

SSH セッションでは Tauri の DMG 作成が Finder の AppleScript で止まるため、Tauri で Universal `.app` を生成し、同じアプリから `hdiutil` で DMG を作って Developer ID 署名を加えます。App ZIP と DMG は Mac 上で署名・アーキテクチャ・構造を検証し、SHA-256 を照合してローカルへ回収します。この段階の成果物は公証前です。

| 公証前の成果物 | ローカルの出力先 |
| --- | --- |
| App ZIP | `apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/github/PrelisDesktop_<version>_universal.app.zip` |
| DMG | `apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/github/PrelisDesktop_<version>_universal.dmg` |
| SHA-256 一覧 | `apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/github/SHA256SUMS` |

2026-10-30 に macOS 27.0.1、Xcode 27.1、Apple Silicon で `0.1.1` の Universal App ZIP と DMG を作成しました。実行ファイルに `arm64` と `x86_64` が含まれ、App と DMG の署名は `Developer ID Application: KUPAC LLC (GLQCJ8YF9S)`、Team ID は `GLQCJ8YF9S` です。App の Hardened Runtime と両署名のタイムスタンプ、App Store 用 Profile の不在、DMG の整合性、回収後の SHA-256 照合を確認しました。Apple 公証と別の Mac での起動は未確認です。

## GitHub Releases 向け公証

ビルド後、別のコマンドで実行します。

```sh
./scripts/macos/notarize-github.sh
```

公証スクリプトは `.env` の `PRELIS_APPSTORE_API_KEY_ID` と `PRELIS_APPSTORE_API_ISSUER_ID`、Mac 上の `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` を使います。[Apple の手順](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)に従い、ZIP を `notarytool` で公証し、アプリにチケットを付与して ZIP を作り直します。次に DMG を別途公証してチケットを付与します。両方の結果が `Accepted` となり、`stapler validate` と署名検証が通ったときだけ、最終 ZIP・DMG・SHA-256 一覧を `github/notarized/` に回収します。公証前のファイルは `github/` に保持し、同じビルドの公証が完了している場合は Apple への再申請を省きます。個人用 API キーは `notarytool` に使えないため、[チーム用 API キー](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)が必要です。

2026-10-30 時点で公証スクリプトは作成と構文確認のみで、Apple への公証申請は実行していません。公証後の ZIP と DMG を別の Mac で開いて起動確認してから GitHub Releases に公開します。

## 一括ビルド

```sh
./scripts/macos/build-macos.sh
```

`kousei@192.168.10.22` にソースを同期し、Mac 上で `npm ci`、Tauri の release `.app` ビルド、`.app` の ZIP 化、DMG 作成を行います。ZIP と DMG をローカルの `apps/desktop/src-tauri/target/release/bundle/` に回収し、Mac 側で作った SHA-256 一覧と照合します。SSH 鍵認証とローカルの Mutagen、OpenSSH クライアント、Python 3、`sha256sum` が必要です。

| 成果物 | ローカルの出力先 |
| --- | --- |
| アプリの ZIP | `apps/desktop/src-tauri/target/release/bundle/macos/PrelisDesktop_<version>_<arch>.app.zip` |
| DMG | `apps/desktop/src-tauri/target/release/bundle/dmg/PrelisDesktop_<version>_<arch>.dmg` |
| SHA-256 一覧 | `apps/desktop/src-tauri/target/release/bundle/macos-artifacts.sha256` |

現在のビルドは Developer ID 署名と公証を行いません。DMG は Finder の外観設定を省き、`hdiutil` で作成します。アプリと `Applications` へのリンクが入ります。ダウンロードして配布した場合の Gatekeeper の通過は確認していません。

## 同期のみ実行する場合

```sh
./scripts/macos/create-macos-sync.sh
```

`kousei@192.168.10.22:prelis-remote` に Mutagen の `one-way-safe` セッション `prelis-macos` で同期します。スクリプトは同期完了・競合なし・必要ファイルの存在と不要ディレクトリの不在を確認します。Windows 用の SSH ラッパーを使わないよう、Mutagen のデータは `.mutagen-macos/` に分けています。

同期対象はルートの npm 定義、`apps/desktop`、`packages/core`、`packages/icons`、Mac 側のビルドスクリプトです。Android・iOS・ウェブのアプリ、インフラ、LP、ドキュメント、他 OS のスクリプト、アイコン生成スクリプト、サンプル画像、Git 管理情報、依存、`*.tsbuildinfo` と `src-tauri/gen` を含むビルド生成物、認証ファイルは除外します。Mac 側の `node_modules` と Rust の `target` は Mac で生成して再利用します。

2026-10-30 に同期先を削除してから再作成し、86 ファイル・1.2 MB、競合 0 件を確認しました。この同期先から `npm ci` は 39 パッケージを導入し、App Store 向けの署名済み `.app` を再ビルドしています。

## Mac 側で直接ビルドする場合

Mac に Xcode 本体、Rust、Node.js と npm を用意します。この Mac では Node.js は fnm にあり、SSH の非対話シェルには Homebrew の PATH が入らず、`xcode-select` は Command Line Tools を指しています。スクリプトがインストール済みの Node.js と Xcode を選びます。

```sh
ssh kousei@192.168.10.22
cd ~/prelis-remote
bash scripts/macos/build-on-mac.sh
```

Mac 側では `.app` と、上記の ZIP・DMG・SHA-256 一覧を生成します。ソース変更後は先に同期スクリプトを再実行してください。

## 確認状況

2026-10-18 に macOS 27.0.1、Xcode 27.1、Apple Silicon、Node.js 24.22.0、Rust 1.99.1 でフロントエンドと Rust の release ビルド、arm64 の `.app`・ZIP・DMG 作成を確認しました。`unzip` と `hdiutil verify`、回収後の SHA-256 照合も通っています。起動・機能操作、Developer ID 署名、公証は未確認です。

Tauri に DMG も直接作らせると、SSH セッションでは Finder の外観設定用 AppleScript (`osascript`) が応答待ちになりました。そのため一括スクリプトは Tauri に `.app` のみ作らせ、DMG は `hdiutil` で作ります。
