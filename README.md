# Prelis

デスクトップとモバイルで TypeScript のロジックを共有する npm workspaces モノレポです。
デスクトップは Tauri + React、モバイルは React Native を使用します。
現在の開発対象はデスクトップと Android で、iOS 対応は保留中です。
提供機能を共通にし、UI は各アプリで個別に開発します。
開発はデスクトップでの確認からモバイルへの反映へ進めます。方針は [基本原則](AGENTS.md) を参照してください。

| ディレクトリ | 役割 |
| --- | --- |
| [apps/desktop](apps/desktop/README.md) | デスクトップアプリ |
| [apps/mobile](apps/mobile/README.md) | モバイルアプリ |
| [packages/core](packages/core/package.json) | UI・OS に依存しない共有ロジック |
| [packages/icons](packages/icons/README.md) | 両アプリで使う PNG アイコン |
| [scripts](scripts/) | ワークスペース共通の補助スクリプト |
| [docs](docs/README.md) | 構成説明、仕様、開発手順、環境メモ |

## 開発を始める

- [共通セットアップと作業手順](docs/development/workflow.md)
- [デスクトップの開発手順](docs/development/desktop.md)
- [Windows 11 向けビルド手順](docs/development/windows.md)
- [Android の開発手順](docs/development/android.md)
- [ワークスペースの構成](docs/architecture.md)
- [デザインガイドライン](docs/design/guidelines.md)
- [ドキュメント索引](docs/README.md)

AI エージェント向けの入口は [AGENTS.md](AGENTS.md) です。
