# Linux 向け deb・AppImage のビルド

Ubuntu（amd64）向けに AppImage と deb パッケージを作成する手順です。
コマンドはリポジトリのルートで実行します。全体像は[Linux 版デスクトップ](README.md)、環境条件は[デスクトップ開発](../desktop.md)を参照してください。

## 事前準備

- [共通セットアップ](../workflow.md)を完了し、`npm run check` が成功すること。
- Tauri の Linux 前提パッケージ（WebKitGTK 4.1・GTK 3 の開発ライブラリなど）が入っていること。
- AppImage の作成時に linuxdeploy が GitHub から自動ダウンロードされるため、ネットワーク接続が必要です。
- deb と AppImage の署名に使う GPG 秘密鍵（フィンガープリント `5985489712B7621E3FD07DEC77B8FD8948B3E363`）をビルド環境で利用できること。
- ビルドは配布先と同じ CPU アーキテクチャ（amd64）の Linux で行います。

## 1. バージョンを更新する

次の 3 か所を同じ値に揃えます。

| ファイル | 項目 |
| --- | --- |
| [tauri.conf.json](../../../apps/desktop/src-tauri/tauri.conf.json) | `version` |
| [Cargo.toml](../../../apps/desktop/src-tauri/Cargo.toml) | `version` |
| [apps/desktop/package.json](../../../apps/desktop/package.json) | `version` |

`Cargo.toml` を更新したら `Cargo.lock` の更新も差分に含めます。

## 2. 検証する

```sh
npm run check
npm run build -w apps/desktop
```

## 3. パッケージを作成する

```sh
./scripts/linux/build-ubuntu.sh
```

スクリプトは deb と AppImage を作成し、AppImage に GPG 埋め込み署名を付けてその存在を確認します。両ファイルに分離署名（`.asc`）も付け、`gpg --verify` で検証します。別の鍵を使う場合は `RELEASE_KEY_FPR=<フィンガープリント> ./scripts/linux/build-ubuntu.sh` と指定できます。
初回は Rust の依存コンパイルに数分かかります。

| 成果物 | 出力先 |
| --- | --- |
| deb | `apps/desktop/src-tauri/target/release/bundle/deb/PrelisDesktop_<version>_amd64.deb` |
| deb の署名 | `apps/desktop/src-tauri/target/release/bundle/deb/PrelisDesktop_<version>_amd64.deb.asc` |
| AppImage | `apps/desktop/src-tauri/target/release/bundle/appimage/PrelisDesktop_<version>_amd64.AppImage` |
| AppImage の分離署名 | `apps/desktop/src-tauri/target/release/bundle/appimage/PrelisDesktop_<version>_amd64.AppImage.asc` |

パッケージのメタデータは次の設定から生成されます。

| 内容 | 設定元 |
| --- | --- |
| 発行元・カテゴリ・説明・deb セクション | `tauri.conf.json` の `bundle` |
| Maintainer・パッケージ名 | `Cargo.toml` の `authors`、`productName` |
| 依存パッケージ | Tauri が自動設定（`libwebkit2gtk-4.1-0`、`libgtk-3-0`） |

## 4. 成果物を確認する

```sh
version="$(node -p 'require("./apps/desktop/package.json").version')"
deb="apps/desktop/src-tauri/target/release/bundle/deb/PrelisDesktop_${version}_amd64.deb"
appimage="apps/desktop/src-tauri/target/release/bundle/appimage/PrelisDesktop_${version}_amd64.AppImage"
dpkg-deb -I "$deb"
dpkg-deb -c "$deb"
gpg --verify "${deb}.asc" "$deb"
gpg --verify "${appimage}.asc" "$appimage"
sha256sum "$deb" "${deb}.asc" "$appimage" "${appimage}.asc"
```

Ubuntu 実機（可能ならクリーンな環境）で次を確認します。

```sh
# deb
sudo apt install ./PrelisDesktop_<version>_amd64.deb
PrelisDesktop   # またはアプリランチャーの「PrelisDesktop」から起動

# AppImage
chmod +x PrelisDesktop_<version>_amd64.AppImage
./PrelisDesktop_<version>_amd64.AppImage
```

- アプリが起動し、Diary・Timer・Password の主要操作ができること。
- アプリランチャーと起動中のウィンドウに Android 版と共通のアイコンが表示されること。Linux の実行ファイル名、アイコン名、`StartupWMClass` は `PrelisDesktop` に揃えています。ファイルマネージャー上の deb ファイルは通常、パッケージ形式の汎用アイコンになります。AppImage ファイルのアイコン表示とランチャーへの登録には、ファイルマネージャーの対応や AppImage のデスクトップ統合が必要です。
- deb は `sudo apt remove prelis-desktop` で削除できること。
- Ubuntu 22.04 以降では AppImage の実行に FUSE 2（`libfuse2`）が必要な場合があります。
  無い環境では `sudo apt install libfuse2`、または `--appimage-extract-and-run` を付けて実行します。

## 5. 直接頒布する

1. 変更をコミットし、`v<version>` のタグを付けて push します。
2. GitHub Releases などに deb、対応する `.deb.asc`、AppImage、対応する `.AppImage.asc`、`sha256sum` の結果を添付します。
3. リリースノートに対応 OS（Ubuntu amd64）、インストール手順、既知の問題を記載します。

APT リポジトリでも deb を頒布する場合は、[APT での頒布](apt.md)に従って同じ `.deb` を `reprepro` に登録・署名し、公開前後の検証を行います。`.deb.asc` は APT リポジトリの署名には使いません。

## 注意

- AppImage には `bundleMediaFramework: true`（[tauri.conf.json](../../../apps/desktop/src-tauri/tauri.conf.json)）で GStreamer を同梱しています。
  無効だと `GStreamer element appsink not found` が出て、WebView がフリーズします。
  同梱にはビルド機に GStreamer（`libgstreamer1.0-dev`、`gstreamer1.0-plugins-base/good/bad` など）が必要です。

- AppImage 署名には `LDAI_SIGN` と `LDAI_SIGN_KEY` を使います。`APPIMAGETOOL_FORCE_SIGN` は現行の appimagetool では削除されているため、スクリプトは生成後に署名の有無を確認します。
- `.deb.asc` は deb ファイルを検証するための分離署名です。`apt install ./...deb` はこの署名を自動検証しません。APT リポジトリで配布する場合は、リポジトリの `InRelease` または `Release.gpg` の署名が別途必要です。
- arm64 向けは別途 arm64 環境（または対応するクロスビルド環境）でのビルド・検証が必要で、未検証です。
- 成果物は `target/` 配下で Git の管理対象外です。コミットしないでください。
- Windows 11 向けのパッケージ作成手順は [Windows ビルド手順](../windows.md) を参照してください。macOS 向けは未整備です。
