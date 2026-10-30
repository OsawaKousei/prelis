# Linux 配布物のビルド・署名

Ubuntu（amd64）向けの deb・AppImage をビルドして署名し、検証・インストール確認・直接頒布まで行う手順です。
コマンドは、特記がない限り取得済みのリポジトリのルートで実行します。
開発環境の準備とアプリの動作確認は [デスクトップ開発](../../desktop.md)を参照してください。
AppImage 作成ツールの取得にはネットワーク接続を使います。

## Linux 版の配布構成

| 配布形式 | 利用方法 | 更新方法 |
| --- | --- | --- |
| deb | `.deb` を直接インストールする | 新しい `.deb` を取得してインストールする |
| AppImage | ファイルに実行権限を付けて起動する | 新しい AppImage に差し替える |
| APT リポジトリ | `stable` / `main` から `prelis-desktop` をインストールする | APT で更新する |
| Snap Store | `prelis` をインストールする | Snap Store のチャンネルに従って更新する |

ビルドを担当するのは `scripts/linux/build-ubuntu.sh` です。
作成した deb は直接頒布するほか、同じファイルを APT リポジトリに登録したり、Snap の作成元に使ったりできます。AppImage は直接頒布します。
この文書は deb・AppImage の作成と直接頒布までを扱います。作成した deb の登録・公開は [APT での頒布](apt.md)、Snap の作成・Store 公開は [Snap での頒布](snap.md)を参照してください。

## 署名の準備

[環境準備](../../desktop.md#環境準備)、[バージョンの更新](../../desktop.md#バージョンを揃える)、[ビルド前の検証](../../desktop.md#検証)を完了してから進めます。
`package-lock.json`・`Cargo.lock` と画面内のバージョン表示も、同じ更新手順で揃えてください。
署名・パッケージ検証用のツールを用意します。

```sh
sudo apt install gnupg dpkg coreutils
```

### 署名鍵と出力先

署名付き配布パッケージの作成には GPG 秘密鍵が必要です。
鍵の識別情報、ホスト OS 上の所在・権限、登録確認コマンドは [Linux 配布用の署名鍵](../../../environment/signing-key.md)にまとめています。
同文書の確認コマンドで `RELEASE_KEY_FPR` を設定し、秘密鍵が利用できることを確認してください。
開発起動と署名を伴わない debug ビルドにはこの鍵は不要です。

現在の配布スクリプトは `apps/desktop/src-tauri/target/` から成果物を探します。出力先を揃えるため、別の出力先を指定している場合は解除します。

```sh
unset CARGO_TARGET_DIR
```

Cargo のユーザー設定やプロジェクト設定で `build.target-dir` を指定している場合も、配布スクリプトを使う際は既定の出力先に戻してください。
スクリプトは Cargo の出力先を確認し、既定値と異なる場合はビルド前に停止します。

## 1. パッケージを作成する

```sh
./scripts/linux/build-ubuntu.sh
```

スクリプトは指定された秘密鍵を確認し、Tauri CLI で deb と AppImage をビルドします。
Tauri の `beforeBuildCommand` によりフロントエンドもビルドされます。初回は Rust の依存コンパイルに時間がかかります。

AppImage には `LDAI_SIGN=1` と `LDAI_SIGN_KEY` で GPG 埋め込み署名を付けます。
生成後、`--appimage-signature` が正常終了し、出力に署名が存在することを確認します。この確認は埋め込み署名の暗号学的な検証ではありません。
さらに deb と AppImage の両方に分離署名（`.asc`）を付け、`gpg --verify` で検証します。
各分離署名は一時ファイルに作成し、検証成功後に既存の `.asc` を置き換えます。
別の鍵を使う場合は `RELEASE_KEY_FPR=<40桁のフィンガープリント> ./scripts/linux/build-ubuntu.sh` と指定します。

両方の分離署名の検証が成功すると、最終成果物を `dist/linux/v<version>/` にコピーします。
同じバージョンで再実行した場合は、そのディレクトリ内の同名ファイルを置き換えます。

| 成果物 | 出力先 |
| --- | --- |
| deb | `dist/linux/v<version>/PrelisDesktop_<version>_amd64.deb` |
| deb の分離署名 | `dist/linux/v<version>/PrelisDesktop_<version>_amd64.deb.asc` |
| AppImage | `dist/linux/v<version>/PrelisDesktop_<version>_amd64.AppImage` |
| AppImage の分離署名 | `dist/linux/v<version>/PrelisDesktop_<version>_amd64.AppImage.asc` |

パッケージのメタデータと Linux 固有の設定は次のとおりです。

| 内容 | 設定元・確認方法 |
| --- | --- |
| 発行元・カテゴリ・説明・deb セクション | `apps/desktop/src-tauri/tauri.conf.json` の `bundle` |
| Maintainer | `Cargo.toml` の `package.authors` |
| 製品名・deb パッケージ名 | `tauri.conf.json` の `productName`。deb の `Package` は `dpkg-deb -f` で確認（現行成果物は `prelis-desktop`） |
| Linux の実行ファイル名 | `apps/desktop/src-tauri/tauri.linux.conf.json` の `mainBinaryName`（`PrelisDesktop`） |
| 依存パッケージ | Tauri が生成する deb の `Depends` で確認（既存の 0.1.1 は `libwebkit2gtk-4.1-0`、`libgtk-3-0`） |
| アプリアイコン | `packages/icons/assets/brand.png` から生成する `apps/desktop/src-tauri/icons/` の画像 |

## 2. 成果物と署名を確認する

```sh
version="$(node -p 'require("./apps/desktop/package.json").version')"
deb="dist/linux/v${version}/PrelisDesktop_${version}_amd64.deb"
appimage="dist/linux/v${version}/PrelisDesktop_${version}_amd64.AppImage"
dpkg-deb -f "$deb" Package Version Architecture Maintainer Section Depends
dpkg-deb -I "$deb"
dpkg-deb -c "$deb"
gpg --verify "${deb}.asc" "$deb"
gpg --verify "${appimage}.asc" "$appimage"
sha256sum "$deb" "${deb}.asc" "$appimage" "${appimage}.asc"
```

`Package: prelis-desktop`、意図した `Version`、`Architecture: amd64` と、対象 Ubuntu で解決可能な `Depends` を確認します。
署名は検証成功に加えて、署名鍵のフィンガープリントが意図した値と一致することを確認します。

## 3. Ubuntu でインストール・起動を確認する

可能ならクリーンな Ubuntu amd64 環境に成果物を渡して確認します。
以下はビルド環境で実行する場合の例です。別の環境では `deb`・`appimage` に作業ディレクトリからのコピー先の相対パスを設定してください。

```sh
# deb（前節の変数を使用）
sudo apt install "./${deb}"
PrelisDesktop

# AppImage
chmod +x "$appimage"
"./${appimage}"
```

- サイドバーのバージョン表示が、パッケージの `Version` と一致すること。
- アプリが起動し、Diary・Timer・Password の主要操作ができること。保存した内容の再読込とタイマー完了時の音声も確認します。
- アプリランチャーから起動でき、ランチャーと起動中のウィンドウに共通アイコンが表示されること。Linux の実行ファイル名、アイコン名、`StartupWMClass` は `PrelisDesktop` に揃えています。
- deb は `sudo apt remove prelis-desktop` で削除できること。
- 更新版では旧版からの更新後も起動・保存データの利用ができること。

ファイルマネージャー上の deb ファイルは通常、パッケージ形式の汎用アイコンになります。
AppImage ファイルのアイコン表示とランチャーへの登録には、ファイルマネージャーの対応や AppImage のデスクトップ統合が必要です。

AppImage が FUSE 不足で起動できない場合、Ubuntu 22.04 では `sudo apt install libfuse2`、Ubuntu 24.04 では `sudo apt install libfuse2t64` を使用します。
FUSE を使えない環境では `"./${appimage}" --appimage-extract-and-run` で展開して起動できます。

## 4. 直接頒布する

ビルドと動作確認が完了した成果物を公開します。

1. 変更をコミットし、`v<version>` のタグを付けて push します。
2. GitHub Releases などに deb、対応する `.deb.asc`、AppImage、対応する `.AppImage.asc`、`sha256sum` の結果を添付します。
3. リリースノートに確認した Ubuntu のバージョン・amd64、インストール手順、既知の問題を記載します。

公開するファイルは、動作確認したファイルと同じものを使います。同じバージョン番号で内容だけ変えて再頒布せず、修正時はバージョンを上げて作り直します。

## トラブルシュート

| 症状 | 確認・対処 |
| --- | --- |
| GPG 秘密鍵が見つからない | [署名鍵の情報](../../../environment/signing-key.md)に従い、GnuPG ホーム、秘密鍵の登録、フィンガープリントを確認します |
| 署名の入力待ちでビルドが止まる | パスフレーズ入力画面を確認します。端末で署名する場合は `export GPG_TTY="$(tty)"` を設定して再実行します |
| ビルド後に成果物が見つからない | `CARGO_TARGET_DIR`・Cargo の `build.target-dir`、[設定・ロックファイル・画面表示のバージョン](../../desktop.md#バージョンを揃える)、amd64 環境であることを確認します |
| AppImage が FUSE エラーで起動しない | Ubuntu 22.04 は `libfuse2`、24.04 は `libfuse2t64` を導入するか、`--appimage-extract-and-run` を付けて起動します |
| AppImage で音声が鳴らない・WebView が停止する | `tauri.conf.json` の `bundle.linux.appimage.bundleMediaFramework` が `true` であることと、ビルド環境に必要な GStreamer プラグインがあることを確認し、作り直します |

## 注意

- AppImage は `tauri.conf.json` の `bundle.linux.appimage.bundleMediaFramework: true` で GStreamer を同梱します。無効にすると `GStreamer element appsink not found` などの不具合が発生する場合があります。この同梱機能は Ubuntu のビルド環境を前提とし、実行時に必要なプラグインをビルド環境へ用意します。
- `.deb.asc` は deb ファイルを検証するための分離署名です。`apt install ./...deb` はこの署名を自動検証しません。APT リポジトリでは別の鍵で `InRelease` または `Release.gpg` に署名します。Snap Store の署名も直接頒布用の GPG 署名とは別です。
- ビルド時の成果物は `target/`、最終成果物は `dist/linux/` 配下に置き、どちらも Git の管理対象外です。コミットしないでください。
