# macOS 配布物のビルド・署名・公証

GitHub Releases 向けの Universal App ZIP・DMG をビルドし、Developer ID 署名・Apple 公証・動作確認を経て直接頒布する手順です。
コマンドは、特記がない限り Ubuntu 側のリポジトリルートで実行します。ビルドと Apple のツールによる検証は Mac 上で行い、成果物を Ubuntu へ回収します。
開発環境・ソース同期・通常の動作確認用ビルドは [デスクトップ開発](../../desktop.md)、ストア向けのビルド・提出は [Mac App Store での頒布](app-store.md)を参照してください。

## macOS 版の配布構成

| 用途 | 成果物 | 署名・提出方法 |
| --- | --- | --- |
| GitHub Releases などで直接頒布 | Universal App ZIP・DMG | Developer ID Application 署名と Apple 公証 |
| Mac App Store | App ZIP・提出用 PKG | Apple Distribution と Mac Installer Distribution による署名、App Store Connect へのアップロード |
| 開発・動作確認 | ホスト CPU 向けの App ZIP・DMG | `build-macos.sh` を使用。Developer ID 署名・公証は行わない |

直接頒布用は `tauri.conf.json` に `tauri.github.conf.json` を重ね、Hardened Runtime を有効にします。App Store 用の Sandbox と Provisioning Profile は含めません。
確認用ビルドの成功は配布用の署名・公証の完了を意味しません。

## 署名の準備

[環境準備](../../desktop.md#環境準備)・[バージョンの更新](../../desktop.md#バージョンを揃える)・[ビルド前の検証](../../desktop.md#検証)を完了してから進めます。
Ubuntu 側には Mutagen・OpenSSH クライアント・Node.js・Python 3・`sha256sum` が必要です。Mac 側には Xcode 本体・Node.js・npm・Rust に加え、`security`・`codesign`・`ditto`・`hdiutil`・`shasum`・`unzip`・OpenSSL・curl・Python 3・`lipo` を用意します。
Apple の中間証明書取得・署名のタイムスタンプ付与・公証にはネットワーク接続を使います。

### 接続設定・署名ファイル・出力先

接続先・Mac 側の作業パス・証明書の所在・署名 ID・Team ID は、Git 管理と通常のソース同期から除外する `scripts/macos/.env` に設定します。[.env.example](../../../../scripts/macos/.env.example) はキーだけのテンプレートです。スクリプトへの環境固有の値の記入は不要です。

| 変数 | 用途 |
| --- | --- |
| `PRELIS_MACOS_SSH_HOST` | `user@host` 形式の SSH 接続先 |
| `PRELIS_MACOS_REMOTE_ROOT` | Mac のホーム相対、または絶対パスの作業ディレクトリ（空白なし） |
| `PRELIS_MACOS_GITHUB_CERTIFICATE`・`PRELIS_MACOS_GITHUB_SIGNING_IDENTITY` | Developer ID Application の `.p12` と署名 ID |
| `PRELIS_MACOS_APPSTORE_CERTIFICATE`・`PRELIS_MACOS_APPSTORE_SIGNING_IDENTITY` | Apple Distribution の `.p12` と署名 ID |
| `PRELIS_MACOS_INSTALLER_CERTIFICATE`・`PRELIS_MACOS_INSTALLER_SIGNING_IDENTITY` | Mac Installer Distribution の `.p12` と署名 ID |
| `PRELIS_MACOS_APPSTORE_PROFILE` | App Store 用 Provisioning Profile |
| `PRELIS_MACOS_TEAM_ID` | 署名・Profile に対応する Team ID |
| `PRELIS_MACOS_DEVELOPER_DIR` | Xcode の Developer ディレクトリ。未指定なら OS の選択に従う |

証明書と Profile のパスは絶対パスか `~/` で指定します。`.env` 内で `$HOME` などの変数展開は行いません。Bundle ID はアプリの Tauri 設定から取得し、App Store の Team ID を含む Entitlements はビルド時に Git 管理対象外の `signing/` へ生成します。
接続先や作業パスを変更して既存の同期セッションと一致しなくなった場合は、安全のため停止します。旧セッションの同期元・同期先を確認し、そのセッションを終了してから再実行してください。

必要な秘密鍵を含む証明書を `.p12` として Mac に用意し、権限を `0600` にします。署名 ID と検証に使う識別情報は、その証明書とアプリの登録内容に一致させます。
現行スクリプトは既定の `apps/desktop/src-tauri/target/` を前提にしています。`CARGO_TARGET_DIR` と Cargo の `build.target-dir` を設定している場合は、ビルド環境で既定の出力先に戻してください。
公証前と確認用の成果物は `target/` に保持します。公証後の直接頒布用 ZIP・DMG・`SHA256SUMS` は `dist/macos/v<version>/` に集約します。成果物と署名用の生成物は Git 管理対象外です。

### パスワードと API キー

初回だけ、Ubuntu 側で設定ファイルを作成します。既存の `.env` がある場合は上書きせず、必要なキーを追記します。

```sh
cp scripts/macos/.env.example scripts/macos/.env
chmod 600 scripts/macos/.env
```

| 変数 | 用途 |
| --- | --- |
| `PRELIS_GITHUB_P12_PASSWORD` | Developer ID Application の `.p12` のパスワード |
| `PRELIS_APPSTORE_P12_PASSWORD` | Apple Distribution の `.p12` のパスワード |
| `PRELIS_APPSTORE_INSTALLER_P12_PASSWORD` | Mac Installer Distribution の `.p12` のパスワード。未指定なら Apple Distribution 用の値を使用 |
| `PRELIS_APPSTORE_API_KEY_ID` | 公証・App Store Connect アップロード用の Key ID |
| `PRELIS_APPSTORE_API_ISSUER_ID` | 同じ API キーの Issuer ID |

実行する工程で必要な値を設定します。[読み込み処理](../../../../scripts/macos/read-config.py)は環境変数を優先し、`.env` をシェルコードとして実行せず、許可したキーだけを読み込みます。`.env` が存在する場合は権限 `0600` が必要です。設定とパスワードは、実行するスクリプトとともに SSH の標準入力で Mac へ渡し、Mac の一時 `.env` から読み込みます。一時ファイルはその処理の終了時に削除します。設定値をリモートコマンドの引数に埋め込みません。

公証にはチーム用の App Store Connect API キーを用意します。現行スクリプトは Key ID・Issuer ID と、Mac 上の `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` を使います。秘密鍵の内容を `.env` に複製したり Ubuntu にコピーしたりする必要はありません。
`.p12`・`.p8`・`.env` は Git 管理とソース同期から除外します。

署名時は一時キーチェーンへ `.p12` を読み込み、署名アクセスを設定します。終了時には既定キーチェーンと検索対象を復元し、一時キーチェーンを削除します。方式の背景は [Tauri の macOS 署名手順](https://v2.tauri.app/distribute/sign/macos/#signing-in-cicd-platforms)を参照してください。

## 1. Developer ID 署名済み ZIP・DMG を作成する

```sh
./scripts/macos/build-github.sh
```

ソース同期後、Mac 上で Developer ID G2 中間証明書を取得・確認し、Developer ID Application の証明書を一時キーチェーンへ読み込みます。Rust の `aarch64-apple-darwin`・`x86_64-apple-darwin` target を準備し、`npm ci` と `tauri build --bundles app --target universal-apple-darwin` を実行します。

同じ `.app` から ZIP と DMG を作成します。SSH セッションで Finder の AppleScript が応答待ちになることを避けるため、DMG は `hdiutil` で生成し、アプリと `Applications` へのリンクを収録して Developer ID 署名を付けます。
App の署名・Team ID・Hardened Runtime・タイムスタンプ・Bundle ID、実行ファイルの `arm64` と `x86_64`、App Sandbox と埋め込み Profile の不在を確認します。ZIP の整合性、DMG の署名と整合性も検証し、回収後に SHA-256 を照合します。

| 公証前の成果物 | Ubuntu 側の回収先 |
| --- | --- |
| App ZIP | `apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/github/PrelisDesktop_<version>_universal.app.zip` |
| DMG | `apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/github/PrelisDesktop_<version>_universal.dmg` |
| SHA-256 一覧 | 同じ `github/` の `SHA256SUMS` |

`<version>` は共通の `tauri.conf.json` の値です。Mac 側には同じ相対パスの成果物と、`apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/macos/PrelisDesktop.app` が残ります。この段階では公証が完了していません。

## 2. Apple 公証とチケット付与を行う

```sh
./scripts/macos/notarize-github.sh
```

スクリプトはソース同期や再ビルドを行わず、Ubuntu と Mac にある公証前 ZIP・DMG の SHA-256 が一致することを確認します。Mac 側の同じ ZIP から App を展開して処理するため、ビルド用ディレクトリの `.app` の上書きには依存しません。
[Apple の公証手順](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)に従い、ZIP と DMG を `notarytool` でそれぞれ申請し、両方の結果を約20秒ごとに確認します。両方が `Accepted` になった後、App にチケットを付与して ZIP を作り直し、DMG にもチケットを付与します。
`stapler validate`・署名検証・DMG の整合性・App の `spctl --assess` が成功した後、最終成果物を Ubuntu へ回収して SHA-256 を照合します。

Mac 側の作業用成果物は前節の `github/notarized/` に残します。Ubuntu 側では、元のビルドとの対応と全ファイルの SHA-256 を確認してから、同名の ZIP・DMG と `SHA256SUMS` を `dist/macos/v<version>/` に保存します。その後、同じ3ファイルを Mac 側のリポジトリの `dist/macos/v<version>/` にも自動配置します。Mac でも転送後の SHA-256 を照合し、一式を置き換えます。配置に失敗した場合は以前の一式を復元します。公証前のファイルは `target/` の `github/` に保持します。
通信断や処理失敗後は、再ビルドせず同じコマンドを再実行します。Mac 側の `notarized/` にハッシュに対応した申請 ID を保存しているため、同じ入力なら保存済み申請を再利用します。同じビルドの公証済み成果物が揃い、ハッシュとチケット検証が通る場合は再申請を省きます。Apple が拒否した場合は、表示された公証ログを確認して修正・再ビルドします。

## 3. 公証済み成果物と起動を確認する

公証後の Mac への配置だけを再実行する場合や、既存の公証済み成果物を検証用 Mac に配置する場合は、Ubuntu 側で次を実行します。接続先は `.env` の設定に従います。公証・再ビルド・ソース同期は行いません。

```sh
./scripts/macos/sync-release.sh
```

引数を省略すると現在の `tauri.conf.json` の版を使います。過去版は `sync-release.sh <version>` と指定します。Ubuntu の `dist/macos/v<version>/` にある ZIP・DMG・`SHA256SUMS` が必要です。公証後の Mac への配置に失敗しても、Ubuntu 側に保存済みの成果物は残るため、このコマンドで再転送できます。

Ubuntu 側で、公開する ZIP・DMG のハッシュを確認します。

```sh
version="$(node -p 'require("./apps/desktop/src-tauri/tauri.conf.json").version')"
bundle="dist/macos/v$version"
(cd "$bundle" && sha256sum -c SHA256SUMS)
```

自動配置した成果物を Mac で確認します。別の検証用 Mac を使う場合も `.env` の接続先・作業パスをその Mac に合わせ、上記のコマンドで配置できます。以下は、Mac 側のリポジトリルートで実行する例です。

```sh
version="$(node -p 'require("./apps/desktop/src-tauri/tauri.conf.json").version')"
bundle="dist/macos/v$version"
verification_dir="$(mktemp -d)"
ditto -x -k "$bundle/PrelisDesktop_${version}_universal.app.zip" "$verification_dir"
app="$verification_dir/PrelisDesktop.app"
dmg="$bundle/PrelisDesktop_${version}_universal.dmg"
codesign --verify --deep --strict "$app"
codesign -dv --verbose=4 "$app"
lipo -archs "$app/Contents/MacOS/desktop"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=4 "$app"
codesign --verify --strict "$dmg"
xcrun stapler validate "$dmg"
hdiutil verify "$dmg"
open "$app"
```

意図した署名者・Team ID・バージョンと、両 CPU の収録を確認します。可能ならビルド用とは別の Apple Silicon・Intel Mac で、実際のダウンロード経路から取得した ZIP・DMG を使って確認します。

- ZIP から展開したアプリと、DMG から `Applications` にコピーしたアプリが起動すること。
- 日記の保存・再読込、タイマー完了時の音声、パスワード生成とコピーが動作すること。
- サイドバーのバージョン、Finder・Dock のアイコンが正しいこと。
- 旧版から更新した後も起動し、保存済みデータを利用できること。

## 4. 直接頒布する

1. ビルド元のコミットとバージョンを確認し、対象の `v<version>` タグを付けて push します。
2. GitHub Releases に、動作確認した公証済み ZIP・DMG と対応する `SHA256SUMS` を添付します。
3. リリースノートに対応 CPU、確認した macOS、インストール方法、既知の問題を記載します。

公開資料は [GitHub Releases の公開資料](../../../../dist/github-release/README.md)の構成に合わせます。公開する成果物は `dist/macos/v<version>/` に保持し、秘密鍵・`.p12`・`.p8`・`.env` は公開物に含めません。公開済みの同じ版を内容だけ変えて再頒布せず、修正時はバージョンを上げて作り直します。

## トラブルシュート

| 症状 | 確認・対処 |
| --- | --- |
| 証明書や署名 ID が見つからない | `.p12` の所在・パスワード、スクリプトの署名 ID と検証条件を確認する |
| 公証前成果物の SHA-256 が一致しない | Ubuntu と Mac の成果物が同じビルドか確認する。別のビルドで上書きした場合は対応する ZIP・DMG を回収し直す |
| 公証が途中で止まった | 同じコマンドを再実行する。Mac 側の保存済み申請 ID を保持する |
| 公証が拒否された | 公証ログの指摘を修正し、新しい成果物をビルドする |
| SSH 経由で DMG 作成が止まる | Tauri に DMG を直接作らせず、`build-github.sh` の `hdiutil` による生成を使う |

## 同時実行とローカル検証

Ubuntu 側はリポジトリ内の `.mutagen-macos/build.lock`、Mac 側はユーザーの `~/.prelis-macos-build.lock` を使い、ビルド・公証・アップロードの重複起動を拒否します。通常終了・エラー・中断ではロックと一時ファイルを片付けます。強制終了などでロックが残った場合は、関連する処理が終了していることを確認してから空のロックディレクトリを `rmdir` で削除します。

ビルド前に Cargo の実際の出力先が既定の `src-tauri/target` と一致すること、Node.js が同期した `.nvmrc` の版であることを確認します。ビルド後は App 内のバージョンも照合します。fnm を使う場合は、事前に `.nvmrc` の版をインストールしてください。

以下のテストは SSH・署名・Apple への送信を代替し、実機のビルドや公証を行いません。

```sh
python3 scripts/macos/build-workflow.test.py
python3 scripts/macos/create-macos-sync.test.py
```

設定の安全な読み込み、二重起動の拒否、Cargo 出力先と App の版の不整合、公証後の集約、改変された成果物の拒否、配置失敗時の復元、PKG の検証・送信に使うコピーの一致を確認します。

## 確認状況

旧資料の 2026-10-30 の記録では、`0.1.1` の Universal App ZIP・DMG の生成、Developer ID 署名、Hardened Runtime・タイムスタンプ、両 CPU の収録、Profile の不在、DMG の整合性、回収後の SHA-256 を確認しています。公証申請と別の Mac での起動は未確認です。
今回の変更は上記のローカルテストで確認しています。署名付きビルド・公証・実機操作は再実行していません。
