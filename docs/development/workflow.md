# 共通セットアップと作業・検証手順

以下のコマンドは、特記がない限りリポジトリのルートで実行します。
ネイティブ開発の前提環境は[デスクトップ](desktop.md)・[Android](android.md)・[iOS](ios.md)を参照してください。

## 初回セットアップ

Node.js の基準は [.nvmrc](../../.nvmrc) の 24.19.0 です。
許容範囲と npm の要件はルートの [package.json](../../package.json) の `engines` を参照してください。

```sh
# nvm を使う場合
nvm install
nvm use

npm ci
npm run check
```

`npm ci` はルートの lockfile に従って依存をインストールします。
既存の `node_modules/` は再作成されるため、開発サーバーを停止した状態で実行します。

## 通常の作業

1. 作業ツリーの変更と、対象の仕様・構成・開発規則を確認します。
2. 各アプリの開発手順に従ってサーバーや実行先を起動します。
3. ソースを変更し、変更の影響に応じた検証を実行します。
4. 必要な文書を更新し、差分と生成物の混入を確認します。

```sh
git status --short
git diff --check
```

## 機能開発の順序

[基本原則](../../AGENTS.md)に従って、機能開発は次の順に進めます。

1. 両アプリで提供する共通機能と受け入れ条件を仕様書に整理します。
2. 共通ロジックを core に、デスクトップ UI を `apps/desktop` に実装します。
3. デスクトップで機能の動作と受け入れ条件を確認し、確認結果を記録します。
4. 確認済みの機能をモバイルへ反映します。UI は `apps/mobile` で別途実装し、画面サイズ・タッチ操作などに合わせて構成や操作方法を調整します。
5. Android で共通の受け入れ条件とモバイル固有の操作を確認し、反映状況を更新します。
6. ウェブ版にも対象機能を反映し、ブラウザー固有の保存・操作条件を確認します。

デスクトップ先行の段階で区切る場合は、仕様書に「デスクトップ確認済み・モバイル反映待ち」と残し、
未反映の内容を明示します。モバイルへの反映まで完了した状態とは区別してください。
仕様の確定状況と、各アプリの実装・確認状況は[仕様書](../specs/README.md)で分けて管理します。

先行開発中も core や依存の変更については、下記の表に従って既存の両アプリへの影響を確認します。
モバイル固有の不具合修正や環境整備は、対象の変更に必要な検証を行います。

## 共通の検証コマンド

定義元はルートの [package.json](../../package.json) です。

| コマンド | 確認範囲 |
| --- | --- |
| `npm run check` | 全 workspace の型チェック → モバイル lint → モバイル Jest（Watchman 不使用）→ ウェブの仕様テスト |
| `npm run typecheck` | 全 workspace の TypeScript。デスクトップとウェブの Vite 設定も対象 |
| `npm run lint` | モバイルの ESLint |
| `npm test` | モバイルの Jest（直列実行） |
| `npm run test:web` | ウェブのタイマー完了仕様テスト |
| `node --test apps/mobile/tests/metro-assets.test.cjs` | 一時 HTTP サーバーで共有 PNG 全11枚の iOS・Android 向け配信を確認。バンドル・ソースマップの URL とクエリの維持も検証 |
| `npm run build:core` | Node.js 向けの core の JavaScript・型宣言生成 |
| `npm run build -w apps/desktop` | デスクトップの型チェックと Vite ビルド |
| `npm run build:web` | ウェブの型チェックと Vite ビルド |
| `npm run build:desktop:debug` | デスクトップの debug ネイティブビルド |
| `./scripts/windows/build-windows.sh` | SSH トンネルと Mutagen 同期、VNC での署名付き Windows ビルド、署名検証結果と NSIS・MSI の回収（[手順](windows.md)） |
| `./scripts/macos/build-macos.sh` | Mac への同期、署名なしの `.app` ビルド、ZIP・DMG の回収と SHA-256 照合（[手順](macos.md)） |
| `./scripts/macos/build-appstore.sh` | Mac への同期、Apple Distribution 署名済み `.app` と Mac Installer Distribution 署名済み提出用 `.pkg` の作成・回収、署名・Entitlements・SHA-256 の検証（[手順](macos.md)） |
| `./scripts/macos/build-github.sh` | Mac への同期、Universal `.app` の Developer ID 署名、署名済み DMG と App ZIP の生成・回収、SHA-256 の検証（[手順](macos.md)） |
| `./scripts/macos/notarize-github.sh` | 既存の GitHub 向け App ZIP と DMG を別々に公証し、チケット付き成果物を回収（[手順](macos.md)） |
| `./scripts/ios/build-ios-simulator.sh` | Mac への同期、署名なしの iOS Simulator `.app` ビルド、ZIP の回収と SHA-256 照合（[手順](ios.md)） |
| `./scripts/ios/setup-device-signing.sh` | Mac の開発用キーチェーンと iOS 開発用プロファイルを初回設定。日常の実機起動は Metro と `run-ios --mode Debug --device` を使用（[手順](ios.md)） |
| `npm run build:android` | Android debug APK のビルド |
| `npm run build:android:standalone` | JavaScript と画像を同梱した Android 動作確認用 APK のビルド |
| `npm run build:android:play` | アップロード鍵で署名した Google Play 用 AAB の作成と検証 |
| `npm run build:android:github` | アプリ署名鍵で署名した GitHub Releases 用 APK の作成と検証 |
| `./scripts/android/build-all.sh` | Android の Play 用 AAB と GitHub 用 APK を続けて作成・検証 |

`npm run check` にネイティブビルドは含まれません。
現在、デスクトップ・core 専用の単体テストスクリプトはありません。
モバイルの Jest は日記の保存操作、パスワードの文字種条件、タイマー完了時の音声呼び出しを確認します。

## 変更内容に応じた検証

| 変更対象 | 基本の検証 | 追加確認が必要な場合 |
| --- | --- | --- |
| 文書のみ | 相対リンク、参照先、記載コマンドと設定の整合、`git diff --check` | アプリの再ビルドは不要 |
| デスクトップ UI | デスクトップのフロントエンドビルド、画面の動作確認 | Tauri API を使う変更はネイティブ起動も確認 |
| ウェブ UI・保存・タイマー | `npm run check`、`npm run build:web`、ブラウザーで変更した操作を確認 | 保存・音声・画面切り替えを含む変更は実ブラウザーで確認 |
| モバイル UI | `npm run check`、Android 上で変更した操作を確認 | native module の追加は APK の再ビルドも実施 |
| core のロジック・公開 API | `npm run check`、デスクトップ・ウェブビルド、Android 向け JS バンドル | 各アプリの利用箇所・変更した振る舞いも確認 |
| core exports・Vite・Metro・React の依存 | 型チェック、両バンドラーでの解決、依存ツリー | 両アプリの起動と core の変更反映を確認 |
| Rust・Tauri 設定 | デスクトップの debug ビルドと起動 | 配布設定変更は対象 OS の配布ビルドも確認 |
| Gradle・Android native 設定 | APK ビルドと Android 起動 | release 固有の変更は release の検証を別途実施 |
| Xcode・iOS native 設定 | Simulator 向けビルドと起動（[手順](ios.md)） | 実機開発の変更は開発署名・実機起動・Metro 接続・Fast Refresh も確認。変更した機能は画面で操作を確認 |

Android 向け JS バンドルのコマンドは [Android 開発手順](android.md) に記載しています。
環境制約で実行できない項目は、静的確認の結果と実行未確認の範囲を分けて記録します。

## 依存更新

依存追加はルートから対象を指定します。以下は書式例で、実際のパッケージ名に置き換えます。

```sh
npm install <package> -w apps/desktop
npm install <package> -w apps/mobile
npm install -D <package> -w packages/core
```

React 関連の変更時は宣言・ルートの `overrides`・lockfile を揃え、解決結果を確認します。

```sh
npm ls react react-dom react-test-renderer --all
```

通常のアプリ開発は core の生成物に依存しません。
Node.js から core を使う作業では、ソース変更後に `npm run build:core` を実行します。
