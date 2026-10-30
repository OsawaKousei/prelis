# Prelis

[公式サイト（LP）](https://prelis.prj.kupac.co.jp/)

Prelis は、日記・タイマー・パスワード生成をひとつにまとめたデスクトップアプリです。

- **日記**: 日付ごとに文章をこのデバイスへ保存できます。別の端末との同期機能はありません。
- **タイマー**: 1〜180分を設定できます。終了音には MP3・WAV ファイルを追加できます。
- **パスワード生成**: 文字数と文字種を選べます。間違えやすい文字を除く設定にも対応し、生成した文字列はコピーできます。

## デスクトップ版のインストール

v0.1.2 の対象は Ubuntu 24.04（amd64）です。次のいずれかの方法でインストールできます。

| 方法 | 入手先・手順 | 更新方法 |
| --- | --- | --- |
| deb | [GitHub Release から取得](#github-release-deb) | 新しい deb を取得してインストール |
| AppImage | [GitHub Release から取得](#github-release-appimage) | 新しい AppImage に差し替え |
| APT | [KUPAC 公式 APT リポジトリを登録](#apt) | APT で更新 |
| Snap | [Snap Store の stable 版をインストール](#snap) | Snap による自動更新 |

### GitHub Release: deb

[v0.1.2 の GitHub Release](https://github.com/OsawaKousei/prelis/releases/tag/v0.1.2)から [PrelisDesktop_0.1.2_amd64.deb](https://github.com/OsawaKousei/prelis/releases/download/v0.1.2/PrelisDesktop_0.1.2_amd64.deb) をダウンロードします。ファイルがあるディレクトリで実行してください。

```sh
sudo apt install ./PrelisDesktop_0.1.2_amd64.deb
```

必要な依存パッケージも APT がインストールします。インストール後はアプリ一覧から Prelis を開けます。直接取得した deb の更新は、新しい版の deb をダウンロードして同じ方法で行います。

### GitHub Release: AppImage

[v0.1.2 の GitHub Release](https://github.com/OsawaKousei/prelis/releases/tag/v0.1.2)から [PrelisDesktop_0.1.2_amd64.AppImage](https://github.com/OsawaKousei/prelis/releases/download/v0.1.2/PrelisDesktop_0.1.2_amd64.AppImage) をダウンロードします。ファイルがあるディレクトリで実行権限を付けて起動します。

```sh
chmod +x PrelisDesktop_0.1.2_amd64.AppImage
./PrelisDesktop_0.1.2_amd64.AppImage
```

FUSE を利用できない環境では、次の方法で展開して起動できます。

```sh
./PrelisDesktop_0.1.2_amd64.AppImage --appimage-extract-and-run
```

更新時は新しい AppImage をダウンロードして差し替えてください。

### APT

KUPAC 公式 APT リポジトリ `https://packages.kupac.co.jp/apt/` を登録します。初回のみ公開鍵を取得し、主鍵の指紋が **`6E2711636C689C79E2283BD9FF5A37D5E9D0457A`** と一致することを確認してください。

```sh
curl -fsSLo /tmp/kupac-archive-keyring.gpg https://packages.kupac.co.jp/apt/kupac-archive-keyring.gpg
gpg --show-keys --with-fingerprint /tmp/kupac-archive-keyring.gpg
```

公式サイトなど、鍵の取得先とは別の経路でも指紋を照合してください。一致を確認したら、公開鍵と deb822 形式のソースを登録します。

```sh
sudo install -D -m 0644 /tmp/kupac-archive-keyring.gpg /etc/apt/keyrings/kupac-archive-keyring.gpg
sudo tee /etc/apt/sources.list.d/kupac.sources >/dev/null <<'EOF'
Types: deb
URIs: https://packages.kupac.co.jp/apt
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/kupac-archive-keyring.gpg
EOF
sudo apt update
sudo apt install prelis-desktop
```

登録は一度だけ行います。更新時は次を実行してください。`apt update` だけではアプリ本体は更新されません。

```sh
sudo apt update
sudo apt install prelis-desktop
```

### Snap

[Snap Store](https://snapcraft.io/prelis) の stable 版をインストールします。

```sh
sudo snap install prelis --channel=stable
```

インストール後はアプリ一覧から Prelis を開けます。以後は Snap の設定に従って自動更新されます。手動で更新する場合は `sudo snap refresh prelis` を実行してください。Snap 版では、ホームディレクトリ外や隠しファイルへのアクセスが制限されます。

## 開発者向け

構成と共通セットアップは [全体構成](docs/development/architecture.md)、デスクトップの開発・ビルドは [デスクトップ開発](docs/development/desktop.md)、Linux の配布物作成は [ビルド・署名手順](docs/development/dist/linux/sign.md)を参照してください。APT 管理者への成果物提出・公開依頼は [APT での頒布](docs/development/dist/linux/apt.md)、Snap の公開は [Snap での頒布](docs/development/dist/linux/snap.md)にまとめています。AI エージェント向けの作業規則は [AGENTS.md](AGENTS.md) にあります。

## ライセンス

本リポジトリの当方開発部分は [Apache License 2.0](LICENSE) で提供します。サードパーティ製ライブラリなどの第三者制作物には、それぞれのライセンスが適用されます。
