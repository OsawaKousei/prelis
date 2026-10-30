# Linux 向け Snap での頒布

Ubuntu amd64 向けのビルド済み `.deb` から `prelis` Snap を作成し、Snap Store へ公開します。
コマンドはリポジトリのルートで実行します。`.deb` の作成と動作確認は [ビルド・署名手順](sign.md)、バージョン更新は [デスクトップ開発](../../desktop.md#バージョンを揃える)を参照してください。
APT 管理者への成果物提出・公開依頼は [APT での頒布](apt.md)を参照してください。
Snap Store の正式フォームに沿った掲載情報は [掲載情報](../../../../dist/snap-work/assets/text.md)を参照してください。

## 必要な環境と設定

- Snapcraft・LXD・`dpkg-deb`・Python 3 と、Snap 内部情報の確認用の PyYAML・`unsquashfs` を用意します。
- Snapcraft に KUPAC LLC のアカウントでログインし、`prelis` の公開権限があることを確認します。
- ビルド環境では `lxc info local:` が成功する必要があります。
- [snapcraft.yaml](../../../../dist/snap-work/snap/snapcraft.yaml)、[アイコン](../../../../dist/snap-work/snap/gui/prelis.png)、[デスクトップエントリ](../../../../dist/snap-work/snap/gui/prelis.desktop)を `dist/snap-work/snap/` に揃えます。

Ubuntu では、内部情報の確認用ツールを次のコマンドで導入できます。

```sh
sudo apt install python3-yaml squashfs-tools
```

Snap は strict confinement、`core24`、GNOME extension を使います。
`home`・`network`・`audio-playback`、GStreamer の stage packages、ファイル選択用の `GTK_USE_PORTAL=0` は `snapcraft.yaml` で設定します。
ホーム外や隠しファイルへのアクセスは Snap の制限を受けます。Snap Store の署名は APT・直接頒布用の GPG 署名とは別です。

## 1. ビルド済み deb を確認する

[ビルド・署名手順](sign.md)に従い、対象 Ubuntu での動作確認が完了した `.deb` を用意します。

```sh
version="$(node -p 'require("./apps/desktop/package.json").version')"
deb="dist/linux/v${version}/PrelisDesktop_${version}_amd64.deb"
test -f "$deb"
dpkg-deb -f "$deb" Package Version Architecture
snap_version="$(dpkg-deb -f "$deb" Version)"
snapcraft whoami
lxc info local:
```

`Package: prelis-desktop`、意図した `Version`、`Architecture: amd64` を確認します。
Snap のバージョンは `.deb` の `Version` から設定します。設定ファイル原本の `version` はビルドの入力値には使いません。

## 2. Snap を作成する

```sh
./scripts/linux/publish-snap.sh --deb "$deb" --build-only
```

[公開スクリプト](../../../../scripts/linux/publish-snap.sh)は `.deb` のパッケージ名・アーキテクチャ・バージョンを検証し、`snapcraft.yaml` のコピーにそのバージョンを設定します。
展開した `payload/` と既存の設定・アイコンを使って `snapcraft pack --use-lxd` を実行します。
生成物は `dist/snap-work/prelis_<version>_amd64.snap` です。同じ名前の生成物が既にある場合は上書きせず停止します。
最終配置時にも上書きを拒否するため、同じバージョンを並行してビルドした場合も既存の成果物を保持します。
ビルド時に使用する一時ディレクトリは終了時に削除します。`--build-only` では Store へのアップロードは行いません。

## 3. ローカルで動作を確認する

`prelis` が未インストールの Ubuntu amd64 テスト環境で、生成物をインストールします。

```sh
snap_file="dist/snap-work/prelis_${snap_version}_amd64.snap"
sudo snap install --dangerous "$snap_file"
snap run prelis
snap connections prelis
```

起動、ファイルの読み書き、音声再生、ネットワーク通信、アプリメニューからの起動を確認します。
サイドバーのバージョン表示が、入力した `.deb` の `Version` と一致することも確認します。

## 4. edge へ公開する

確認した同じ Snap ファイルをアップロードします。
スクリプトは生成時と `--upload-edge` の実行時に `meta/snap.yaml` を読み、アプリ名が `prelis`、バージョンがファイル名と一致し、アーキテクチャが `amd64` であることを確認します。不一致や読み取り失敗の場合はアップロードしません。

```sh
./scripts/linux/publish-snap.sh --upload-edge "$snap_file"
snapcraft status prelis
snapcraft revisions prelis
```

新しい版をまとめてビルドして edge へアップロードする場合は、`./scripts/linux/publish-snap.sh --deb "$deb"` を使用できます。
この場合は `--build-only` を付けたときと異なり、ビルド後にアップロードまで進みます。

## 5. Store 版を確認する

Store のレビューを通過したら、ローカル版をインストールしたテスト環境で Store の edge 版へ切り替えます。

```sh
sudo snap refresh --amend --channel=edge prelis
snap run prelis
snap info prelis
```

ローカル版をインストールしていないテスト環境では `sudo snap install --channel=edge prelis` を使います。
主要機能、バージョン表示、既存データを引き継いだ起動を確認します。

## 6. stable に昇格する

動作確認した edge の revision 番号を `snapcraft revisions prelis` で調べます。
`REVISION` は実際の番号に置き換えてください。同じ Snap を再アップロードせずに昇格します。

```sh
./scripts/linux/publish-snap.sh --promote REVISION
snapcraft status prelis
snap info prelis
```

未インストールのテスト環境では `sudo snap install prelis` で stable 版を確認します。
既に Store 版を使用している場合は `sudo snap refresh --channel=stable prelis` で切り替えます。

## LXD に接続できない場合

`ClientConnectionFailed` と `PermissionError(13, 'Permission denied')` が出た場合は、Snapcraft が LXD の Unix ソケットへ接続できていません。
現在のシェルで次を確認します。

```sh
id -nG
getent group lxd
lxc info local:
```

`getent group lxd` にユーザー名があり、`id -nG` に `lxd` が無い場合は、ログアウトして再ログインするか `newgrp lxd` で新しいシェルを開きます。
`getent group lxd` にユーザー名が無い場合は `sudo usermod -aG lxd "$USER"` で追加し、再ログインします。
新しいシェルでは `deb`・`snap_version`・`snap_file` などのシェル変数を設定し直してください。
`lxc info local:` が成功してからビルドを再実行します。
