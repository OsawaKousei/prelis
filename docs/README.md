# ドキュメント索引

Prelis の構成説明、仕様、開発手順、環境メモを管理します。

| 目的 | 文書 |
| --- | --- |
| 機能共有・開発順序・UI の基本方針を確認する | [基本原則](../AGENTS.md) |
| ワークスペースと共有ロジックの仕組みを知る | [アーキテクチャ](architecture.md) |
| コードを配置・変更するときの規則を確認する | [開発規則](development/rules.md) |
| 両アプリの視覚・操作デザインの基準を確認する | [デザインガイドライン](design/guidelines.md) |
| 共通セットアップや変更後の検証を行う | [作業・検証手順](development/workflow.md) |
| デスクトップを開発する | [デスクトップ開発](development/desktop.md) |
| ウェブ版を開発・ビルドする | [ウェブ版開発](development/web.md) |
| Linux 版デスクトップのビルド・頒布を調べる | [Linux 版デスクトップ](development/linux/README.md) |
| Windows 11 向けパッケージをビルドする | [Windows ビルド手順](development/windows.md) |
| macOS 向けデスクトップアプリをビルドする | [macOS ビルド手順](development/macos.md) |
| Microsoft Store 向け MSI の配信 URL を用意する | [MSI 配信インフラ](../infra/ms-store/README.md) |
| ウェブ版の配信インフラを用意する | [ウェブ版配信インフラ](../infra/web-frontend/README.md) |
| Android を開発する | [Android 開発](development/android.md) |
| この Linux マシンの設定・確認履歴を調べる | [ローカル環境メモ](environment/local-linux.md) |
| 機能の仕様を調べる・追加する | [仕様書索引](specs/README.md) |

## 文書の分担

- ルートと各アプリの README は、人間向けの概要と入口です。
- トップの AGENTS.md は、開発の基本原則と参照先の案内です。詳細な規則・手順・仕様は docs に置きます。
- 各 workspace の AGENTS.md は、基本原則を踏まえた作業対象と参照先の案内です。
- 構成の説明は `architecture.md`、デザインの基準は `design/`、規則・手順は `development/` に置きます。
- 必要な環境条件は開発手順に、このマシンの導入先・確認履歴は `environment/` に置きます。
- 機能仕様は `specs/` に置きます。Diary・Timer・Password の仕様を管理します。

文書は日本語で記述します。同じ仕様・手順を複数箇所へ転記せず、相対リンクで参照します。
バージョンやコマンドを記載するときは根拠となる設定ファイルも示し、設定変更時に対応する文書を更新します。
コード・設定と文書の不一致を発見した場合は、現状と意図した仕様を区別して確認・修正します。
