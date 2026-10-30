# Prelis

[公式サイト（LP）](https://prelis.prj.kupac.co.jp/)

Prelis は、日記・タイマー・パスワード生成をひとつにまとめたアプリです。デスクトップ版、Android 版、ウェブ版に加え、開発中の iOS Simulator 版があります。**iOS 版は正常に動作しません。**

- **日記**: 日付ごとに文章を端末内へ保存できます。別の端末との同期機能はありません。
- **タイマー**: 1～180 分の時間を設定できます。終了音には MP3・WAV ファイルを追加できます。
- **パスワード生成**: 文字数と使用する文字種を選び、生成したパスワードをコピーできます。

## デスクトップ版のインストール

お使いの OS に合う方法を選んでください。GitHub Release の配布ファイルは [リリース一覧](https://github.com/OsawaKousei/prelis/releases)から取得できます。Ubuntu 向け deb・AppImage は [v0.1.2 のインストール案内](dist/github-release/v0.1.2/release-notes.md#インストール方法)、その他の形式は [v0.1.1 のインストール案内](dist/github-release/v0.1.1/release-notes.md#インストール方法)を参照してください。

deb と AppImage には署名ファイル（`.asc`）が付きます。インストール前に署名を確認する方法も [v0.1.2 のリリースノート](dist/github-release/v0.1.2/release-notes.md)に記載しています。

| OS | 方法 | インストールと更新 |
| --- | --- | --- |
| Ubuntu（amd64） | APT | 以下の手順でリポジトリを登録。以後は APT で更新できます。 |
| Ubuntu（amd64） | Snap | `sudo snap install prelis`。以後は Snap の設定に従って更新されます。 |
| Ubuntu（amd64） | deb | リリースから `.deb` を取得し、`sudo apt install ./ファイル名.deb`。更新時は新しいファイルを取得します。 |
| Ubuntu（amd64） | AppImage | リリースから `.AppImage` を取得し、実行権限を付けて起動。更新時は新しいファイルに差し替えます。 |
| Windows 11（x64） | NSIS または MSI | リリースから `-setup.exe` または `.msi` を取得して実行します。 |
| macOS（Apple Silicon） | DMG または `.app` ZIP | リリースの Assets に添付された場合に入手できます。署名・公証なしの開発用です。 |

### Ubuntu: APT でインストール

初回のみ、公開鍵をダウンロードして指紋が **`6E2711636C689C79E2283BD9FF5A37D5E9D0457A`** と一致することを確認してください。一致しない場合は以降のコマンドを実行しないでください。

```sh
curl -fsSLo /tmp/prelis-archive-keyring.gpg https://prelis-apt-packages.prj.kupac.co.jp/apt/prelis-archive-keyring.gpg
gpg --show-keys --with-fingerprint /tmp/prelis-archive-keyring.gpg
```

一致を確認したら、リポジトリを登録してインストールします。

```sh
sudo install -D -m 0644 /tmp/prelis-archive-keyring.gpg /etc/apt/keyrings/prelis-archive-keyring.gpg
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/prelis-archive-keyring.gpg] https://prelis-apt-packages.prj.kupac.co.jp/apt stable main' | sudo tee /etc/apt/sources.list.d/prelis.list >/dev/null
sudo apt update
sudo apt install prelis-desktop
```

更新するときは `sudo apt update && sudo apt upgrade` を実行します。既に同じリポジトリを登録している場合、登録を重複させずに更新コマンドだけを実行してください。

### Ubuntu: Snap でインストール

Snap Store の stable チャンネルで公開されている版は、次のコマンドでインストールできます。

```sh
sudo snap install prelis
```

インストール後はアプリ一覧から「Prelis Desktop」を開けます。手動で更新する場合は `sudo snap refresh prelis` を実行してください。Snap 版では、ホームディレクトリ外や隠しファイルへのアクセスが制限されます。

## Android 版のインストール

Android 7.0 以降の端末には、[GitHub の v0.1.1 リリース](https://github.com/OsawaKousei/prelis/releases/tag/v0.1.1)に添付された `prelis-github.apk` をダウンロードしてインストールできます。APK を開き、端末の案内に従ってダウンロード元からのインストールを許可してください。Android アプリの表示上のバージョンは 1.0 です。

公開中の APK の SHA-256、署名証明書の指紋、更新方法は [v0.1.1 のリリースノート](dist/github-release/v0.1.1/release-notes.md) を参照してください。

## iOS Simulator 版

開発中の iOS 版は正常に動作しません。`PrelisMobile-simulator.app.zip` は [v0.1.1 の GitHub Release](https://github.com/OsawaKousei/prelis/releases/tag/v0.1.1)に添付された場合に入手できます。Xcode の Simulator 専用で、iPhone・iPad にはインストールできません。詳しくは [リリースノート](dist/github-release/v0.1.1/release-notes.md)を参照してください。

## 開発者向け

構成、仕様、セットアップ、ビルド手順は [docs/](docs/README.md) を参照してください。AI エージェント向けの作業規則は [AGENTS.md](AGENTS.md) にあります。
ウェブ版のローカル起動とビルドは [ウェブ版の開発手順](docs/development/web.md) を参照してください。`app-prelis.prj.kupac.co.jp` への[配信インフラ](infra/web-frontend/README.md)は Terraform 適用前です。

## ライセンス

本リポジトリの当方開発部分は [Apache License 2.0](LICENSE) で提供します。サードパーティ製ライブラリなどの第三者制作物には、それぞれのライセンスが適用されます。
