# Prelis v0.1.2

Prelis Desktop は、日記・タイマー・パスワード生成をひとつにまとめたデスクトップアプリです。日記は日付ごとにこのデバイスへ保存され、別の端末とは同期されません。

このリリースでは、Ubuntu（amd64）向けの deb と AppImage を配布します。このリリースの Assets から、利用する形式のファイルをダウンロードしてください。

## この版の変更点

- パスワード生成に「間違えやすい文字を除く」設定を追加しました。有効にすると、英大文字の `I`・`O`、英小文字の `l`、数字の `0`・`1` を生成候補から除きます。
- 「間違えやすい文字を除く」設定を切り替えると、前の生成結果を消去します。新しい条件で生成してからコピーできます。
- パスワード生成画面の見出し横にアイコンを追加しました。
- 日記・タイマー・パスワード生成の見出し横のアイコンと背景の枠を、傾けずに表示するようにしました。

## ダウンロードするファイル

| 対象 | 形式 | ファイル名 | 用途 |
| --- | --- | --- | --- |
| Ubuntu（amd64） | deb | `PrelisDesktop_0.1.2_amd64.deb` | システムにインストールする |
| Ubuntu（amd64） | AppImage | `PrelisDesktop_0.1.2_amd64.AppImage` | ファイルから直接起動する |

deb と AppImage のどちらかを選び、本体と同じ名前に `.asc` を付けた分離署名もダウンロードしてください。検証用の公開鍵 `prelis-release-signing-key.asc` と、チェックサム一覧 `sha256sums.txt` も Assets に含めます。

## 署名とチェックサムを検証する

公開鍵のフィンガープリントは **`5985489712B7621E3FD07DEC77B8FD8948B3E363`** です。公開鍵を取り込む前に、指紋を表示して一致することを確認してください。公開鍵と指紋は、このリリースの案内に加えて信頼できる別経路でも照合してください。

```sh
gpg --show-keys --with-fingerprint prelis-release-signing-key.asc
```

一致を確認したら公開鍵を取り込みます。

```sh
gpg --import prelis-release-signing-key.asc
```

ダウンロードした形式の署名を検証します。両方をダウンロードした場合は両方を実行してください。

```sh
# deb を利用する場合
gpg --verify PrelisDesktop_0.1.2_amd64.deb.asc PrelisDesktop_0.1.2_amd64.deb

# AppImage を利用する場合
gpg --verify PrelisDesktop_0.1.2_amd64.AppImage.asc PrelisDesktop_0.1.2_amd64.AppImage
```

`Good signature` と表示され、署名鍵の指紋が上記の値と一致することを確認してください。鍵の信頼度に関する警告と、署名が不正というエラーは別です。署名が不正、または指紋が異なる場合は、そのファイルをインストール・実行しないでください。

チェックサムは、ファイルをダウンロードしたディレクトリで確認できます。`--ignore-missing` は未取得の形式を検証対象から除きます。取得した本体・署名・公開鍵について `OK` と表示されることを確認してください。

```sh
sha256sum --check --ignore-missing sha256sums.txt
```

チェックサムは取得ファイルの破損確認に使い、配布元の確認には GPG 署名と公開鍵の指紋を使用してください。

## インストール方法

### Ubuntu: deb

署名を検証したファイルがあるディレクトリで実行します。必要な依存パッケージも APT がインストールします。

```sh
sudo apt install ./PrelisDesktop_0.1.2_amd64.deb
```

インストール後はアプリ一覧から Prelis を開けます。既存の deb 版を更新する場合も同じコマンドを使用します。`apt install` は上記の分離署名を自動検証しないため、先に GPG で検証してください。

### Ubuntu: AppImage

署名を検証したファイルに実行権限を付けて起動します。

```sh
chmod +x PrelisDesktop_0.1.2_amd64.AppImage
./PrelisDesktop_0.1.2_amd64.AppImage
```

FUSE を利用できない環境では、次の方法で展開して起動できます。

```sh
./PrelisDesktop_0.1.2_amd64.AppImage --appimage-extract-and-run
```

更新するときは新しい AppImage と署名を取得して検証し、ファイルを差し替えてください。
