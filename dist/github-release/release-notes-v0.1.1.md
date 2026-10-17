# Prelis Desktop v0.1.1

Prelis Desktop は、日記・タイマー・パスワード生成を使えるデスクトップアプリです。日記は日付ごとに端末内へ保存され、別の端末とは同期されません。

このリリースでは、Ubuntu amd64 向けの deb・AppImage と、Windows 11 x64 向けの NSIS・MSI インストーラーを配布します。deb と AppImage には GPG の分離署名（`.asc`）が付きます。Windows のインストーラーには発行元 KUPAC LLC の署名が付いています。

## この版の変更点

- Ubuntu 向けに deb と AppImage を用意しました。
- アプリのアイコンを更新しました。
- Windows 向け MSI をユーザーごとのインストールに対応させました。

## ダウンロードするファイル

| OS | 形式 | ファイル名 | 用途 |
| --- | --- | --- | --- |
| Ubuntu（amd64） | deb | `PrelisDesktop_0.1.1_amd64.deb` | Ubuntu にインストールする |
| Ubuntu（amd64） | AppImage | `PrelisDesktop_0.1.1_amd64.AppImage` | ファイルから直接起動する |
| Windows 11（x64） | NSIS | `PrelisDesktop_0.1.1_x64-setup.exe` | 画面の案内に沿ってインストールする |
| Windows 11（x64） | MSI | `PrelisDesktop_0.1.1_x64_en-US.msi` | Windows Installer でインストールする |

このリリースの Assets から、お使いの OS に合うファイルをダウンロードしてください。Ubuntu では deb と AppImage のどちらかを選べます。Windows では NSIS と MSI のどちらかを選べます。

## deb・AppImage の署名を検証する

Ubuntu 向けファイルを検証する場合は、本体と同じ名前に `.asc` を付けた署名ファイル、および `prelis-release-signing-key.asc` を Assets から同じディレクトリにダウンロードしてください。公開鍵の指紋は **`5985489712B7621E3FD07DEC77B8FD8948B3E363`** です。これは APT リポジトリの署名鍵とは別の鍵です。

まず公開鍵の指紋を表示し、この値と一致することを確認します。公開鍵と指紋は同じリリースの案内だけを根拠にせず、信頼できる別経路でも照合してください。

```sh
gpg --show-keys --with-fingerprint prelis-release-signing-key.asc
```

指紋が一致した場合に公開鍵を取り込みます。

```sh
gpg --import prelis-release-signing-key.asc
```

続いて、ダウンロードした形式の署名を検証します。両方ダウンロードした場合は両方を実行してください。

```sh
gpg --verify PrelisDesktop_0.1.1_amd64.deb.asc PrelisDesktop_0.1.1_amd64.deb
gpg --verify PrelisDesktop_0.1.1_amd64.AppImage.asc PrelisDesktop_0.1.1_amd64.AppImage
```

`Good signature` と表示されることを確認してください。鍵を自分で信頼済みに設定していない場合は、鍵の信頼度に関する警告が併せて出ることがあります。署名が不正、または鍵の指紋が異なる場合は、そのファイルをインストール・実行しないでください。`sudo apt install ./...deb` はこの分離署名を自動では検証しません。

## インストール方法

### Ubuntu: deb

ダウンロードしたファイルがあるディレクトリで、次を実行します。必要な依存パッケージも APT がインストールします。

```sh
sudo apt install ./PrelisDesktop_0.1.1_amd64.deb
```

インストール後はアプリ一覧から「PrelisDesktop」を開けます。直接ダウンロードした deb を更新するときは、新しい版の deb を取得して同じ方法でインストールしてください。

### Ubuntu: AppImage

ダウンロードしたファイルがあるディレクトリで実行権限を付け、起動します。

```sh
chmod +x PrelisDesktop_0.1.1_amd64.AppImage
./PrelisDesktop_0.1.1_amd64.AppImage
```

更新するときは新しい AppImage をダウンロードして差し替えてください。起動時に FUSE 2 が必要と表示される Ubuntu 環境では、`sudo apt install libfuse2` を実行してください。

### Windows 11: NSIS（setup.exe）

`PrelisDesktop_0.1.1_x64-setup.exe` をダブルクリックし、画面の案内に沿ってインストールします。更新時は新しい版のインストーラーを実行してください。

### Windows 11: MSI

`PrelisDesktop_0.1.1_x64_en-US.msi` をダブルクリックし、画面の案内に沿ってインストールします。この MSI はユーザーごとにインストールされ、通常は管理者権限を必要としません。更新時は新しい版の MSI を実行してください。

以前のマシン全体向け MSI から切り替える場合は、旧版を管理者権限でアンインストールしてから、この MSI をインストールしてください。

## ほかの Ubuntu 向けインストール方法

APT リポジトリと Snap Store の stable チャンネルを使う方法は、[README のインストール案内](https://github.com/OsawaKousei/prelis#デスクトップ版のインストール)に記載しています。これらの方法でインストールした場合は、それぞれ APT と Snap の仕組みで更新できます。
