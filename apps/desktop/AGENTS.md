# デスクトップのエージェント向け案内

対象は `apps/desktop/` の React UI、Vite 設定、`src-tauri/` の Rust・Tauri 設定です。
機能開発の先行対象です。[基本原則](../../AGENTS.md)に沿って、モバイルにも提供する共通機能をデスクトップで実装・確認します。

- [共通の開発規則](../../docs/development/rules.md)
- [構成と責務の境界](../../docs/architecture.md)
- [デスクトップの環境・起動・ビルド手順](../../docs/development/desktop.md)
- [変更内容に応じた検証](../../docs/development/workflow.md)
- [機能仕様の索引](../../docs/specs/README.md)

共有ロジックも変更する場合の入口は [core の指示](../../packages/core/AGENTS.md) です。
