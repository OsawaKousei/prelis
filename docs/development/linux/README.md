# Linux 版デスクトップ

Prelis Desktop の Linux 向け開発・ビルド・頒布の入口です。現在の配布対象は Ubuntu amd64 で、deb と AppImage を作成し、deb から Snap も作成します。arm64 向けのビルドと動作は未検証です。共通のデスクトップ開発環境と起動方法は[デスクトップ開発](../desktop.md)を参照してください。

| 配布形式 | 利用方法 | 更新方法 |
| --- | --- | --- |
| deb | `.deb` を直接インストールする | 新しい `.deb` を取得してインストールする |
| AppImage | ファイルに実行権限を付けて起動する | 新しい AppImage に差し替える |
| APT リポジトリ | `stable` / `main` のソースから `prelis-desktop` をインストールする | 通常の APT 更新を使う |
| Snap Store | `prelis` をインストールする | Snap Store のチャンネルに従う |

Linux 版は Tauri の WebKitGTK 4.1 と GTK 3 に依存します。ビルド環境にはこれらの開発ライブラリが必要です。配布先の依存関係は deb の `Depends` と対象 Ubuntu でのインストール試験で確認します。

| 作業 | 手順 |
| --- | --- |
| deb・AppImage をビルドし、署名・動作を確認する | [deb・AppImage のビルド](build.md) |
| 公開版を Ubuntu にインストールする | [APT のインストール手順](apt.md#公開版をインストールする) |
| deb を APT リポジトリに登録・公開し、更新を確認する | [APT での頒布](apt.md) |
| deb から Snap を作成し、Store に公開する | [Snap での頒布](snap.md) |
| S3・CloudFront・Terraform の配信基盤を管理する | [APT での頒布](apt.md#配信基盤の設定) |

ビルドした deb は直接頒布するほか、同じファイルを APT リポジトリに登録できます。AppImage は直接頒布します。直接頒布する deb・AppImage の分離署名と、APT の `InRelease` / `Release.gpg` の署名には別の鍵を使います。鍵と検証方法は各手順を参照してください。

リポジトリルートの `scripts/linux/build-ubuntu.sh` がビルドを担当し、`dist/apt-repo/` がローカル APT リポジトリの管理原本です。`infra/apt-repo/publish-apt.sh` にビルド済み deb と AWS profile を指定すると、APT への登録・検証・S3 への公開を順に実行します。ビルドと公開は別々の操作です。
