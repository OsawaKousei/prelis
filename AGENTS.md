# 開発の基本原則とドキュメント案内

## 基本原則

- 提供する機能はデスクトップとモバイルで共通にします。
- 開発はデスクトップを優先し、デスクトップで動作を確認した機能をモバイルへ反映して進めます。
- UI はデスクトップとモバイルで別々に開発します。共通の機能を提供しつつ、モバイルの特徴に合わせて画面構成や操作方法を変更して構いません。
- ウェブ版も共通機能を提供し、ブラウザー固有の制約は仕様書に記録します。

## 関連ドキュメント

| 作業対象 | 参照先 |
| --- | --- |
| 共通 | [開発規則](docs/development/rules.md)、[作業・検証手順](docs/development/workflow.md)、[デザインガイドライン](docs/design/guidelines.md) |
| ワークスペース構成 | [アーキテクチャ](docs/architecture.md) |
| デスクトップ | [apps/desktop/AGENTS.md](apps/desktop/AGENTS.md) |
| ウェブ | [apps/web/AGENTS.md](apps/web/AGENTS.md) |
| モバイル | [apps/mobile/AGENTS.md](apps/mobile/AGENTS.md) |
| 共有ロジック | [packages/core/AGENTS.md](packages/core/AGENTS.md) |
| 仕様・環境メモ | [ドキュメント索引](docs/README.md) |
