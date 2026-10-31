# Android 配布物のビルド・署名

Ubuntu 上で Google Play 提出用の AAB と、直接頒布用の APK をビルドして署名し、検証・インストール確認・直接頒布まで行う手順です。
コマンドは、特記がない限り取得済みのリポジトリのルートで実行します。
開発環境の準備と開発起動は [モバイル開発](../../mobile.md)、AAB の提出とストア公開は [Google Play での頒布](google-play.md)を参照してください。

## Android 版の配布構成

| 配布形式 | 利用方法 | 署名に使う鍵 | 更新方法 |
| --- | --- | --- | --- |
| Google Play 用 AAB | Play Console へ提出し、Google Play が生成した APK を配信する | ローカルではアップロード鍵。配信 APK は Play アプリ署名鍵 | Google Play から更新する |
| 直接頒布用 APK | GitHub Releases などから取得してインストールする | アプリ署名鍵 | 新しい APK を取得して上書きインストールする |

ビルドを担当するのは [build-release.mjs](../../../../scripts/android/build-release.mjs) と [build-all.sh](../../../../scripts/android/build-all.sh) です。
Expo アカウントや EAS は使わず、Git 管理している `apps/mobile/android/` を Gradle wrapper でビルドします。Release には Expo CLI を通して JavaScript と画像を同梱するため、利用者側で Metro を起動する必要はありません。
開発用の Debug APK と、デバッグ鍵で署名する `standalone` APK は頒布に使いません。

## 署名の準備

[共通セットアップ](../../architecture.md#共通セットアップ)・[Android の環境準備](../../mobile.md#android)・[バージョンの確認](../../mobile.md#バージョンを揃える)を完了し、`npm run check` を通します。
JDK 17 の `java`・`jar`・`keytool`・`jarsigner`、Android SDK Build-Tools 37.0.0 の `apksigner`、Command-line Tools の `apkanalyzer`、`unzip`・`sha256sum` を使います。`JAVA_HOME` と `ANDROID_HOME`、各ツールへのパスを設定してください。スクリプトは `JAVA_HOME` が設定されていれば、その `bin/` の JDK ツールを使用します。
初回ビルドや依存更新時には、Gradle・Maven・Android SDK の取得先へのネットワーク接続が必要です。

### 識別子とバージョン

| 内容 | 設定元・現行値 |
| --- | --- |
| パッケージ名 | `apps/mobile/android/app/build.gradle` の `applicationId`：`jp.co.kupacllc.prelis` |
| ストア向けバージョン | 同ファイルの `versionName`：`1.0.1`。`apps/mobile/app.json` の `expo.version` と一致させる |
| Android ビルド番号 | 同ファイルの `versionCode`：`2`。app.json の `android.versionCode` と一致させる |
| 頒布バージョン | `apps/mobile/package.json` の `version`：`0.1.3`。ホーム画面・仕様書と揃え、出力ディレクトリ・ファイル名にも使用する |
| SDK・対象 CPU | `apps/mobile/android/build.gradle`・`settings.gradle`・`gradle.properties`。SDK の現行値は [モバイル開発](../../mobile.md#android)を参照 |

[v0.1.3 のビルド・署名仕様](../../../specs/v0.1.3.md#ビルド署名)に従い、今回の頒布版は `v0.1.3` です。出力の版は `apps/mobile/package.json` の `version` を使います。ストア向けのバージョンは旧版 `1.0` に続く `1.0.1`、`versionCode` は `2` として別に管理します。Play Console や既存 APK の履歴を確認し、それより新しい提出・公開がある場合はストア向けの番号を更新します。
以降の更新では `versionCode` を増やします。同じ版の AAB と APK を作る間は、ソース・頒布バージョン・`versionName`・`versionCode` を変更しません。スクリプトは app.json と Gradle のストア向けバージョン・ビルド番号が一致しなければビルド前に停止します。

`android/` を保守する構成のため、app.json だけ変更しても既存の Gradle 設定は更新されません。設定は両方で確認し、通常の頒布作業で `expo prebuild --clean` は実行しません。

### 署名鍵とパスワード

| 用途 | キーストアの既定パス | 別名の既定値 | パスワード変数 |
| --- | --- | --- | --- |
| Play 用アップロード鍵 | `~/keys/play-upload.jks` | `play-upload` | `PRELIS_PLAY_STORE_PASSWORD`・`PRELIS_PLAY_KEY_PASSWORD` |
| 直接頒布用アプリ署名鍵 | `~/keys/app-signing.jks` | `app-signing` | `PRELIS_APP_STORE_PASSWORD`・`PRELIS_APP_KEY_PASSWORD` |

既存アプリに対応する鍵を用意します。更新のたびに新しい鍵を生成しません。鍵とパスワードはバックアップして保管し、リポジトリや頒布物へ含めません。
Play Console のアップロード証明書・アプリ署名証明書と照合するため、公開済み APK と各キーストアの証明書 SHA-256 を記録しておきます。

```sh
keytool -list -v -keystore "$HOME/keys/play-upload.jks" -alias play-upload
keytool -list -v -keystore "$HOME/keys/app-signing.jks" -alias app-signing
```

パスワードはプロンプトで入力します。パス・別名を変更している場合は実際の値に置き換えます。

[.env.example](../../../../scripts/android/.env.example) から設定ファイルを用意します。既存ファイルがある場合はその内容を使用します。

```sh
if [ ! -f scripts/android/.env ]; then
  cp scripts/android/.env.example scripts/android/.env
fi
chmod 600 scripts/android/.env
```

エディターで `scripts/android/.env` を開き、必要な配布先のパスワード2項目を記入します。一括ビルドには4項目すべてが必要です。キーストアと鍵のパスワードが同じ場合も両方へ記入します。
鍵のパス・別名を変える場合は `PRELIS_PLAY_KEYSTORE` / `PRELIS_PLAY_KEY_ALIAS` または `PRELIS_APP_KEYSTORE` / `PRELIS_APP_KEY_ALIAS` を指定します。パスには絶対パスを使い、`~`・`$HOME` は展開済みの値を書きます。

スクリプトは `.env` をシェルとして実行せず、上記の対応変数だけを文字列として読み込みます。変数展開やコマンド実行は行いません。既に設定された環境変数が優先されます。`.env` とキーストアは Git 管理対象外です。

両方の配布先の設定をビルドなしで確認する場合:

```sh
node scripts/android/build-release.mjs check
```

必要な JDK・APK 検証ツール、Gradle wrapper の実行権限、出力先の作成・書込みを確認します。各秘密鍵で小さな検証用 JAR に署名し、署名検証も行うため、秘密鍵のパスワード誤りや証明書だけのエントリーも事前に検出します。検証用ファイルは一時ディレクトリに作成して削除し、既存の成果物は変更しません。通常のビルドでも対象の配布先について同じ事前チェックを行い、一括ビルドでは両方が通ってから Gradle を実行します。

### Play と直接頒布の更新互換性

Google Play と直接頒布の間でも更新できるようにするには、パッケージ名に加えて、配信 APK の署名証明書を揃える必要があります。Play アプリ署名には既存のアプリ署名鍵を登録し、AAB のアップロードには別のアップロード鍵を使います。[Android 公式の署名手順](https://developer.android.com/studio/publish/app-signing)を参照してください。

Play Console が Google 生成のアプリ署名鍵を使用している場合、ローカルの `app-signing.jks` で作った APK と同じ署名になるとは限りません。Console のアプリ署名証明書と APK の SHA-256 を照合し、実際の更新を確認してから相互更新を案内します。ローカルの検証スクリプトは、Play Console の登録内容までは確認しません。

## 1. パッケージを作成する

両方の成果物を同じソースから作る場合:

```sh
npm run build:android:all
```

一括スクリプトは両方のキーストアを事前確認し、AAB・APK を一時ディレクトリへ作成します。両方のビルドと署名検証が成功した後に、`dist/android/v<version>/` へディレクトリ単位で配置します。既存の同版を置き換える場合は旧版一式を一時退避し、配置に失敗した場合は旧版一式へ戻します。復元も失敗した場合は、旧版の退避先を表示して保持します。
片方だけ作る場合は、次を使います。

```sh
# Play 提出用 AAB
npm run build:android:play

# 直接頒布用 APK
npm run build:android:github
```

単独ビルドも指定した形式だけの新しい一式へ差し替えます。同じ版の既存ディレクトリに反対側の形式があっても引き継ぎません。AAB と APK の両方を残す場合は `build:android:all` を使います。

各ビルドは Gradle の `clean` と `:app:bundleRelease` または `:app:assembleRelease` を実行します。前のネイティブ成果物は消えるため、以降の確認・頒布にはコピー済みの `dist/android/v<version>/` を使います。これらのビルドは同時実行しません。
AAB は `jarsigner -verify -strict` にキーストアと期待する別名を指定し、自己署名のアップロード証明書も明示的に信頼して検証します。さらに [verify-jar.java](../../../../scripts/android/verify-jar.java) で署名メタデータ以外の全ファイルを末尾まで読み、ダイジェスト、署名漏れ、複数の署名者、期待する証明書との不一致、有効期限を確認します。APK は `apksigner` で署名を検証し、指定キーストアの証明書 SHA-256 と照合します。署名付きビルドの成功は、ストア提出や公開の完了を意味しません。

| 成果物 | Gradle の生成元 | 最終出力先 |
| --- | --- | --- |
| AAB | `apps/mobile/android/app/build/outputs/bundle/release/app-release.aab` | `dist/android/v<version>/PrelisMobile_<version>_play.aab` |
| APK | `apps/mobile/android/app/build/outputs/apk/release/app-release.apk` | `dist/android/v<version>/PrelisMobile_<version>_github.apk` |
| SHA-256 一覧 | 検証した成果物から生成 | `dist/android/v<version>/SHA256SUMS` |

表の `<version>` は `apps/mobile/package.json` の `version` です。現行設定なら `dist/android/v0.1.3/` に出力します。別バージョンのディレクトリは保持し、同じ版で再実行した場合はその版の一式を置き換えます。検証記録も版ごとに保存してください。出力先に管理対象外のファイルがある場合は、誤削除を避けるためビルド前に停止します。
環境変数 `PRELIS_ANDROID_OUTPUT_DIR` を設定すると、単独・一括ビルドとも、そのディレクトリの下の `v<version>/` を出力先にします。これは出力ルートの指定であり、以前の単独ビルドのような最終ディレクトリの直接指定ではありません。`.env` には書かず環境変数として渡します。以前の固定名の `dist/android/prelis-play.aab`・`prelis-github.apk` は移動・削除しないため、新しい手順では版付きディレクトリ内のファイルを使ってください。
出力ルートは `apps/mobile/android/` の外に置きます。`clean` が消すビルド領域への出力を防ぐため、シンボリックリンク経由も含めて同プロジェクト内の指定は事前に拒否します。

## 2. 成果物と署名を確認する

```sh
version="$(node -p 'require("./apps/mobile/package.json").version')"
release_dir="dist/android/v${version}"
apk="${release_dir}/PrelisMobile_${version}_github.apk"
aab="${release_dir}/PrelisMobile_${version}_play.aab"
sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
test -n "$sdk_root"
apksigner="$sdk_root/build-tools/37.0.0/apksigner"

"$apksigner" verify --verbose --print-certs "$apk"
# 既定の鍵・別名の例。変更している場合は実際の値に置き換える
jarsigner -verify -strict -keystore "$HOME/keys/play-upload.jks" "$aab" play-upload
keytool -printcert -jarfile "$aab"
unzip -t "$apk"
unzip -t "$aab"
apkanalyzer apk summary "$apk"
apkanalyzer manifest min-sdk "$apk"
apkanalyzer manifest target-sdk "$apk"
apkanalyzer manifest debuggable "$apk"
apkanalyzer manifest permissions "$apk"
sha256sum "$apk" "$aab"
(cd "$release_dir" && sha256sum -c SHA256SUMS)
```

- APK の証明書が既存のアプリ署名鍵、AAB の証明書が登録済みアップロード鍵の SHA-256 と一致すること。
- APK のパッケージ名が `jp.co.kupacllc.prelis`、バージョンが意図した `versionName`・`versionCode`、`debuggable` が `false` であること。AAB 内の識別子・バージョン・SDK は、Play Console へアップロードした後にも確認します。
- 最終マニフェストの権限が機能と申告内容に合い、録音権限 `android.permission.RECORD_AUDIO` が含まれていないこと。ソースの Manifest だけでなく依存をマージした成果物で確認します。

確認コマンドの仕様は [apksigner](https://developer.android.com/tools/apksigner) と [apkanalyzer](https://developer.android.com/tools/apkanalyzer) を参照してください。キーストア証明書との照合と、Console の登録証明書との照合は別々に行います。

React Native / Expo のネイティブライブラリを含むため、[16 KB ページサイズの確認手順](https://developer.android.com/guide/practices/page-sizes)に従い、ELF と ZIP のアラインメント、16 KB 環境での実行も確認します。ZIP の確認例は次のとおりです。これだけで ELF や実行時の適合まで判定しません。

```sh
"$sdk_root/build-tools/37.0.0/zipalign" -c -P 16 -v 4 "$apk"
```

## 3. Android でインストール・起動を確認する

検証専用の端末またはエミュレーターを使います。通常の開発 APK は同じパッケージ名でも署名が異なるため、そのままでは更新できません。既存データを残す必要がある端末を検証用にアンインストールせず、専用環境を用意します。

```sh
adb devices
serial='検証対象のシリアル'
version="$(node -p 'require("./apps/mobile/package.json").version')"
adb -s "$serial" install -r "dist/android/v${version}/PrelisMobile_${version}_github.apk"
adb -s "$serial" shell am start -W -n jp.co.kupacllc.prelis/.MainActivity
```

Metro を停止した状態で、以下を確認します。Play 配信 APK の確認は [Google Play のテスト手順](google-play.md#3-google-play-からインストールして確認する)で別途行います。

- 新規インストール・ランチャーからの起動、アイコン、端末のアプリ情報に表示される公開バージョンが正しいこと。ホームの内部管理用バージョンは `0.1.3` と区別します。
- 日記の保存・日付移動・再起動後の再読込、日本語・絵文字、未保存本文の扱いが正しいこと。
- タイマーのリング表示・一時停止・再開・タブ切替中の計時・完了音・リセット、音声の追加・試聴・選択の再読込ができること。バックグラウンド中の正確な終了音は保証しない仕様を確認します。
- パスワードの文字種・文字数・コピーが正しいこと。
- 360×640 dp でヘッダーとタブを含む全4画面の初期表示が収まり、ページ全体のスクロールが不要であること。内部スクロール、設定・カレンダー展開後のスクロール、キーボード表示時の操作も確認します。
- 旧版から同じ署名・増加した `versionCode` で更新できること。現行 Expo 版同士の更新では保存した日記・音声を引き継げること。

360×640 の自動テストは [モバイル開発の表示テスト](../../mobile.md#360640-の表示テスト)も実施します。このテストは Debug APK と Metro を使うため、上記 Release の実機確認とは検証範囲が異なります。

旧 React Native CLI 版から Expo 版への保存データの自動移行は提供しない仕様です。旧版の日記・音声がそのまま新実装に表示されるとは扱わず、更新時の制約を確認記録とリリースノートに記載します。仕様は [Expo 移植方針](../../../specs/v0.1.3.md#移植方針)を参照してください。

実施日、端末名・Android / API・CPU・画面寸法、更新元と更新先、操作結果、ビルド元コミットとタグ、成果物の SHA-256、証明書 SHA-256 を記録します。署名検証や Debug の表示テストだけで Release の動作確認済みとはしません。

## 4. 直接頒布する

1. ビルド元の変更をコミットし、対応するタグとコミット SHA を確定・記録します。公開バージョン・`versionCode`・内部管理用バージョンも記録します。
2. 動作確認した `PrelisMobile_<version>_github.apk` と `SHA256SUMS` をそのまま GitHub Releases などの Assets に添付します。AAB は Play Console へ提出するファイルで、直接インストール用のファイルではありません。チェックサム一覧に AAB の行もある場合は、Play 提出用のファイルであることを案内します。
3. APK の SHA-256 とアプリ署名証明書の SHA-256、対応 Android・CPU、インストール方法、確認した動作、既知の問題をリリースノートに記載します。旧 CLI 版からのデータ自動移行がないことも案内します。
4. 公開先から APK を取得し直し、ハッシュ・署名とインストール・起動を確認します。

リリース本文などの公開資料は [GitHub Releases の公開資料](../../../../dist/github-release/README.md)の構成に従い頒布版ごとに保存します。今回のリリースタグは `v0.1.3` とし、ストア向けのバージョン・`versionCode` も別途明記します。成果物本体は `dist/android/v<version>/` に保持します。

利用者には、端末で APK を開き、必要に応じて取得に使ったブラウザーやファイル管理アプリの「不明なアプリのインストール」を許可する手順を案内します。更新時は同じ署名の新しい APK を上書きインストールします。署名不一致をアンインストールで回避する案内は、保存データの削除を伴うため通常の更新手順には含めません。

公開後に同じ版のファイルを内容だけ変えて差し替えず、修正時はバージョン・`versionCode` を更新して作り直します。APK には Android の署名が埋め込まれており、Linux 用 GPG 鍵や `.asc` はこのビルドでは使用・生成しません。

## 注意

- スクリプトの回帰テストは `npm run test:android:scripts` で実行できます。JDK 17 と一時鍵を使用し、Gradle と APK 検証ツールはテスト用の代替を使います。実際の鍵・端末・ストアへはアクセスしません。
- 差替え中の強制終了後に `.v<version>-stage-*/previous/` が残っている場合は、旧成果物の保管先です。表示先と内容を確認して復元してから再実行します。
- `dist/android/` 内の生成物は Git 管理対象外です。署名鍵・`.env` とともにコミットしません。
- 署名エラー時は `.env` の対象変数、環境変数による上書き、キーストアの絶対パス・別名・パスワードを確認します。Debug 鍵への切替で頒布ビルドを通しません。
- `INSTALL_FAILED_UPDATE_INCOMPATIBLE` は既存アプリと署名が異なる場合に発生します。`INSTALL_FAILED_VERSION_DOWNGRADE` は既存より古いビルド番号などを確認します。公開済み APK の証明書と番号を調べ、正しい鍵と増加した `versionCode` で作り直します。
