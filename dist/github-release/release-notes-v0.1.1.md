# Prelis v0.1.1

Prelis は、日記・タイマー・パスワード生成を使えるアプリです。日記は日付ごとに端末内へ保存され、別の端末とは同期されません。

このリリースでは、Ubuntu amd64 向けの deb・AppImage、Windows 11 x64 向けの NSIS・MSI インストーラー、Android 向けの APK を配布します。deb と AppImage には GPG の分離署名（`.asc`）が付きます。Windows のインストーラーには発行元 KUPAC LLC の署名が付いています。Android の APK はアプリ署名鍵で署名しています。

## この版の変更点

- Ubuntu 向けに deb と AppImage を用意しました。
- アプリのアイコンを更新しました。
- Windows 向け MSI をユーザーごとのインストールに対応させました。
- Android 向けに、アプリ内に JavaScript を同梱した APK を用意しました。

## ダウンロードするファイル

| OS | 形式 | ファイル名 | 用途 |
| --- | --- | --- | --- |
| Ubuntu（amd64） | deb | `PrelisDesktop_0.1.1_amd64.deb` | Ubuntu にインストールする |
| Ubuntu（amd64） | AppImage | `PrelisDesktop_0.1.1_amd64.AppImage` | ファイルから直接起動する |
| Windows 11（x64） | NSIS | `PrelisDesktop_0.1.1_x64-setup.exe` | 画面の案内に沿ってインストールする |
| Windows 11（x64） | MSI | `PrelisDesktop_0.1.1_x64_en-US.msi` | Windows Installer でインストールする |
| Android 7.0 以降 | APK | `prelis-github.apk` | 端末に直接インストールする |

このリリースの Assets から、お使いの OS に合うファイルをダウンロードしてください。Ubuntu では deb と AppImage のどちらかを選べます。Windows では NSIS と MSI のどちらかを選べます。Android では `prelis-github.apk` を選びます。Android アプリの表示上のバージョンは **1.0**（versionCode 1）で、リリースタグの v0.1.1 とは別です。

Android APK の SHA-256 は **`da378fda8fccdba0653853c8156222417d18d75f17bba18ffb3fc133c9e91090`**、署名証明書の SHA-256 は **`53ca47077d747340766b79ad78346b5d84312b45388a71de1e6f7c48a3ffbe92`** です。これらは `dist/android/prelis-github.apk` の検証値です。異なる APK を添付する場合は、この値を再確認してください。

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

### Android: APK

[v0.1.1 のリリース](https://github.com/OsawaKousei/prelis/releases/tag/v0.1.1)の Assets にある `prelis-github.apk` を Android 端末へダウンロードします。ファイルを開き、端末に表示される案内に沿って、このダウンロード元からのインストールを許可してインストールしてください。更新時も同じ署名鍵で署名された新しい APK を入手してインストールします。

PC でダウンロードした APK のハッシュを確認する場合は、ファイルのあるディレクトリで `sha256sum prelis-github.apk` を実行し、上記の値と照合してください。

## ほかの Ubuntu 向けインストール方法

APT リポジトリと Snap Store の stable チャンネルを使う方法は、[README のインストール案内](https://github.com/OsawaKousei/prelis#デスクトップ版のインストール)に記載しています。これらの方法でインストールした場合は、それぞれ APT と Snap の仕組みで更新できます。
