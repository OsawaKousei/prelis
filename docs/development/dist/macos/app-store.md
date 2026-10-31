# Mac App Store での頒布

Mac App Store 向けの署名済み `.app` と提出用 `.pkg` を作成し、App Store Connect の検証・アップロードを経て審査に提出する手順です。
コマンドは、特記がない限り Ubuntu 側のリポジトリルートで実行します。
開発環境・ソース同期は [デスクトップ開発](../../desktop.md)、直接頒布用の署名・公証は [macOS 配布物のビルド・署名・公証](sign.md)を参照してください。

## 必要な環境と設定

[環境準備](../../desktop.md#環境準備)・[バージョンの更新](../../desktop.md#バージョンを揃える)・[ビルド前の検証](../../desktop.md#検証)を完了します。
接続先・署名ファイル・既定の出力先・`.env` の準備は [署名の準備](sign.md#署名の準備)に従います。Mac 側には、共通のビルド・署名ツールに加えて `productbuild`・`pkgutil` と、Xcode 付属の `xcrun altool` が必要です。

- Mac に秘密鍵を含む Apple Distribution と Mac Installer Distribution の `.p12`、対象アプリの配布用 Provisioning Profile を用意します。`.env` の入力パス・署名 ID・Team ID を証明書と Profile に揃えます。
- Ubuntu の `scripts/macos/.env` に `PRELIS_APPSTORE_P12_PASSWORD` を設定します。インストーラー用証明書のパスワードが異なる場合は `PRELIS_APPSTORE_INSTALLER_P12_PASSWORD` も設定します。
- Apple 側の検証・アップロードには `PRELIS_APPSTORE_API_KEY_ID`・`PRELIS_APPSTORE_API_ISSUER_ID` と、Mac 上の `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` を用意します。秘密鍵の内容は `.env` に書き込みません。
- App Store Connect に対象アプリを登録し、アップロード・審査提出に必要な権限と契約状況を確認します。

配布先別の設定は次のとおりです。

| 内容 | 設定元 |
| --- | --- |
| 製品名・バージョン・共通ビルド設定 | `apps/desktop/src-tauri/tauri.conf.json` |
| App Store 用 Bundle ID・最低対応 macOS・埋め込み Profile | `apps/desktop/src-tauri/tauri.appstore.conf.json` |
| App Sandbox・ネットワーククライアント権限のテンプレート | `apps/desktop/src-tauri/Entitlements.appstore.plist` |
| Team ID・App ID を加えたビルド用 Entitlements | `apps/desktop/src-tauri/signing/Entitlements.appstore.plist`（ビルド時に生成） |
| ビルド時にコピーする Profile | `apps/desktop/src-tauri/signing/Prelis.provisionprofile`（Git 管理・同期対象外） |

Profile・署名証明書・Entitlements・App Store Connect のアプリ登録で識別情報を揃えます。通常のデスクトップ設定の Bundle ID は変更せず、App Store 用設定を重ねて使います。
現行ビルドはホスト CPU 向けで、Universal ビルドではありません。App Store 用の最低対応 macOS と `MACOSX_DEPLOYMENT_TARGET` は `12.0` に揃えています。Apple Silicon 専用ビルドの条件は [Tauri の App Store 手順](https://v2.tauri.app/distribute/app-store/#build)を参照してください。

## 1. 署名済み App と提出用 PKG を作成する

```sh
./scripts/macos/build-appstore.sh
```

ソース同期後、Mac 上で Apple WWDR G3 中間証明書を取得・確認し、2種類の `.p12` を一時キーチェーンへ読み込みます。スクリプトが中間証明書を取り込むため、ログインキーチェーンへの手動インストールは不要です。
Profile をビルド用の `signing/` へコピーし、`npm ci` と `tauri build --bundles app --config src-tauri/tauri.appstore.conf.json` を実行します。

署名済み App に対して次を確認します。

- `codesign --verify --deep --strict` が成功すること。
- App Sandbox・App ID・Team ID、Bundle ID、最低対応 macOS、埋め込み Profile が設定と一致すること。
- アプリ内のファイルとディレクトリを一般ユーザーが読み取れること。

続いて Mac Installer Distribution の署名 ID を使い、`productbuild --component` で `/Applications` 向けの PKG を作成します。`pkgutil --check-signature` と PKG の展開により、署名・識別子・バージョン・インストール先・App と Profile の収録・読み取り権限・展開後の App の署名を確認します。
App ZIP と PKG、およびそれぞれの SHA-256 を Ubuntu へ回収し、ハッシュの一致を確認して保存します。ビルドだけでは Apple 側の検証・アップロードは行いません。

| 成果物 | 出力先 |
| --- | --- |
| 署名済み `.app` | Mac 側: `apps/desktop/src-tauri/target/release/bundle/macos/PrelisDesktop.app` |
| App ZIP | Ubuntu 側: `apps/desktop/src-tauri/target/release/bundle/appstore/PrelisDesktop_<version>_<arch>_appstore.app.zip` |
| 提出用 PKG | Ubuntu 側: `apps/desktop/src-tauri/target/release/bundle/appstore/PrelisDesktop_<version>_<arch>_appstore.pkg` |
| SHA-256 | App ZIP・PKG と同名のファイルに `.sha256` を付けたもの |

`<version>` は共通の `tauri.conf.json` の値、`<arch>` は Apple Silicon で `aarch64`、Intel Mac で `x64` です。Mac 側にも同じ相対パスの ZIP・PKG・SHA-256 が残ります。
同期済みの Mac で直接ビルドする場合は、Mac 側のリポジトリルートで `bash scripts/macos/internal/build-appstore-on-mac.sh` を実行します。この場合も、Mac 側の `scripts/macos/.env` または環境変数に証明書・Profile・署名 ID・パスワードを設定します。

## 2. 提出する成果物を確認する

以下では Apple Silicon 向けの回収済み PKG を指定します。別の CPU 向けではファイル名を実際の成果物に合わせます。

```sh
version="$(node -p 'require("./apps/desktop/src-tauri/tauri.conf.json").version')"
pkg="apps/desktop/src-tauri/target/release/bundle/appstore/PrelisDesktop_${version}_aarch64_appstore.pkg"
test -f "$pkg"
test -f "$pkg.sha256"
test "$(sha256sum "$pkg" | awk '{print $1}')" = "$(cat "$pkg.sha256")"
```

`.sha256` はハッシュ文字列だけを持つ形式で、直接頒布用の `SHA256SUMS` とは形式が異なります。
App ZIP から展開したアプリを Mac 上で起動し、Sandbox 内での日記の保存・再読込、タイマーの音声と終了音ファイルの操作、パスワード生成・コピーを確認します。サイドバーのバージョンとアイコンも確認します。開発版・直接頒布版の動作確認だけで代用しないでください。

## 3. App Store Connect で検証する

前節の `pkg` を指定し、アップロードせず Apple 側の検証だけを実行します。この工程も App Store Connect と通信します。

```sh
./scripts/macos/upload-appstore.sh --validate-only "$pkg"
```

スクリプトはローカルの `.pkg.sha256` と PKG のハッシュを確認し、Mac 側の同名 PKG を実行専用の一時領域へコピーし、そのコピーとも一致することを確認します。Mac 側の PKG がビルド後に上書きされて内容が変わっている場合は停止します。
PKG の署名、展開後の App の署名・Bundle ID・最低対応 macOS・一般ユーザーの読み取り権限を確認した後、[Apple のアップロード手順](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)に沿って `xcrun altool --validate-app` を実行します。
検証とアップロードには同じ一時コピーを使います。ソース同期・再ビルド・PKG の転送・再署名は行わないため、対応する Mac 側の PKG とローカルの `.sha256` を保持してください。

## 4. 検証した PKG をアップロードする

```sh
./scripts/macos/upload-appstore.sh "$pkg"
```

同じ確認と `altool` による検証を再実行し、成功した場合だけ検証済みの一時コピーをアップロードします。元のビルド用 PKG が途中で変わっても、送信対象のコピーは変わりません。指定した PKG を使用し、ビルドや同期は実行しません。
アップロード成功後も、Apple 側の処理が完了し、App Store Connect に対象ビルドが表示されることを確認します。アップロード完了と審査提出完了は別です。

## 5. 掲載情報を確認して審査に提出する

[Mac App Store 掲載素材](../../../../dist/app-store-mac/README.md)の文面・画像を対象リリースに合わせて確認します。

- App Store Connect のバージョン記録と、提出するビルドのバージョンを揃え、対象ビルドを選択する。
- スクリーンショット・説明・サポート URL・プライバシー情報が、提出する Sandbox 版の表示と動作に一致することを確認する。
- 暗号化輸出規制・App Sandbox の申告、審査用の連絡先と操作説明を確認する。
- 掲載情報を保存して審査に提出し、処理・審査結果と公開状態を確認する。

掲載素材には他 OS で撮影した画面も含まれるため、Mac の提出用ビルドと照合して更新します。ビルド・アップロード用スクリプトは、掲載情報の編集・審査開始・公開操作を行いません。

## トラブルシュート

| 症状 | 確認・対処 |
| --- | --- |
| Profile・App ID・署名 ID が一致しない | 証明書・アプリ登録・Tauri 設定・Entitlements と、スクリプトの検証条件を揃える |
| PKG 内の読み取り権限で拒否される | ビルド時の `umask` と App 内のファイル・ディレクトリ権限を確認して再ビルドする。既存スクリプトは一般ユーザーの読み取りを検証する |
| arm64 専用 App の最低対応 macOS で拒否される | App Store 用設定と `MACOSX_DEPLOYMENT_TARGET`、生成物の `Info.plist` と実行ファイルの最低対応バージョンを確認する |
| ローカルと Mac の PKG のハッシュが一致しない | 同じビルドの PKG と `.sha256` を揃える。別ビルドのファイルを混在させない |
| アップロード後にビルドが表示されない | App Store Connect の処理状態・通知・エラーを確認する |

## 確認状況

旧資料の 2026-10-29〜30 の記録では、`0.1.1` の署名済み App ZIP・PKG の生成、App Sandbox・署名・Profile・識別情報・読み取り権限・最低対応 macOS・回収後の SHA-256 を確認しています。読み取り権限と arm64 専用 App の最低対応 macOS の指摘を修正後、`altool --validate-app` はエラー 0 件でした。
同記録では Sandbox 内の機能操作とアップロード・審査は未確認です。
