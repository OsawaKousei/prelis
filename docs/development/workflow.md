# 共通セットアップと作業・検証手順

以下のコマンドは、特記がない限りリポジトリのルートで実行します。
ネイティブ開発の前提環境は[デスクトップ](desktop.md)・[Android](android.md)を参照してください。

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

## 共通の検証コマンド

定義元はルートの [package.json](../../package.json) です。

| コマンド | 確認範囲 |
| --- | --- |
| `npm run check` | 全 workspace の型チェック → モバイル lint → モバイル Jest |
| `npm run typecheck` | 全 workspace の TypeScript。デスクトップの Vite 設定も対象 |
| `npm run lint` | モバイルの ESLint |
| `npm test` | モバイルの Jest（直列実行） |
| `npm run build:core` | Node.js 向けの core の JavaScript・型宣言生成 |
| `npm run build -w apps/desktop` | デスクトップの型チェックと Vite ビルド |
| `npm run build:desktop:debug` | デスクトップの debug ネイティブビルド |
| `npm run build:android` | Android debug APK のビルド |

`npm run check` にネイティブビルドは含まれません。
現在、デスクトップ・core 専用の単体テストスクリプトはありません。
モバイルの既存テストは、入力に応じて共有 core の挨拶が更新されることを確認します。

## 変更内容に応じた検証

| 変更対象 | 基本の検証 | 追加確認が必要な場合 |
| --- | --- | --- |
| 文書のみ | 相対リンク、参照先、記載コマンドと設定の整合、`git diff --check` | アプリの再ビルドは不要 |
| デスクトップ UI | デスクトップのフロントエンドビルド、画面の動作確認 | Tauri API を使う変更はネイティブ起動も確認 |
| モバイル UI | `npm run check`、Android 上で変更した操作を確認 | native module の追加は APK の再ビルドも実施 |
| core のロジック・公開 API | `npm run check`、デスクトップビルド、Android 向け JS バンドル | 両アプリの利用箇所・変更した振る舞いも確認 |
| core exports・Vite・Metro・React の依存 | 型チェック、両バンドラーでの解決、依存ツリー | 両アプリの起動と core の変更反映を確認 |
| Rust・Tauri 設定 | デスクトップの debug ビルドと起動 | 配布設定変更は対象 OS の配布ビルドも確認 |
| Gradle・Android native 設定 | APK ビルドと Android 起動 | release 固有の変更は release の検証を別途実施 |

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
