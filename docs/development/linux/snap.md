# Linux 向け Snap での頒布

Ubuntu amd64 向けのビルド済み `.deb` から `prelis` Snap を作成し、Snap Store へ公開します。コマンドはリポジトリのルートで実行します。`.deb` の作成と確認は[ビルド手順](build.md)を参照してください。

Snapcraft、LXD、`dpkg-deb`、Python 3 を使用します。Snapcraft に KUPAC LLC のアカウントでログインし、`prelis` の公開権限があることを確認してください。LXD を使うビルド環境では `lxc info` が成功する必要があります。Snapcraft の設定とデスクトップ素材は [`dist/snap-work/snap/`](../../../dist/snap-work/snap/snapcraft.yaml) に置きます。

```sh
version="$(node -p 'require("./apps/desktop/package.json").version')"
deb="apps/desktop/src-tauri/target/release/bundle/deb/PrelisDesktop_${version}_amd64.deb"
dpkg-deb -f "$deb" Package Version Architecture
snapcraft whoami
lxc info local:
./scripts/linux/publish-snap.sh --deb "$deb" --build-only
```

スクリプトは `.deb` の `Package: prelis-desktop`、`Architecture: amd64` とバージョンを検証し、`dist/snap-work/snap/snapcraft.yaml` のコピーにそのバージョンを設定します。展開した `payload/` と既存の設定・アイコンを使って `snapcraft pack --use-lxd` を実行します。生成物は `dist/snap-work/prelis_<version>_amd64.snap` です。同じ名前の生成物が既にある場合は上書きせず停止します。ビルド時に使用する一時ディレクトリは終了時に削除します。

ローカルで生成物をインストールし、起動、ファイルの読み書き、音声再生、ネットワーク通信、アプリメニューからの起動を確認します。

```sh
snap_file="dist/snap-work/prelis_${version}_amd64.snap"
sudo snap install --dangerous "$snap_file"
snap run prelis
snap connections prelis
```

確認した同じ Snap ファイルを edge へアップロードします。新しい版をまとめてビルドして edge へアップロードする場合は `./scripts/linux/publish-snap.sh --deb "$deb"` を実行できます。

```sh
./scripts/linux/publish-snap.sh --upload-edge "$snap_file"
snapcraft status prelis
snapcraft revisions prelis
```

Store のレビューを通過したら、Store 版へ切り替えて主要機能を再確認します。ローカル版をインストールしていないテスト環境では `sudo snap install --channel=edge prelis` を使用します。

```sh
sudo snap refresh --amend --channel=edge prelis
snap run prelis
snap info prelis
```

動作確認した edge の revision 番号を `snapcraft revisions prelis` で調べ、stable に昇格します。`REVISION` は実際の番号に置き換えます。同じ Snap を再アップロードせずに昇格します。

```sh
./scripts/linux/publish-snap.sh --promote REVISION
snapcraft status prelis
snap info prelis
sudo snap install prelis
```

Snap は strict confinement、`core24`、GNOME extension を使います。`home`、`network`、`audio-playback` と GStreamer の stage packages、ファイル選択用の `GTK_USE_PORTAL=0` は[設定ファイル](../../../dist/snap-work/snap/snapcraft.yaml)を参照してください。ホーム外や隠しファイルへのアクセスは Snap の制限を受けます。Snap Store の署名は APT・直接頒布用の GPG 署名とは別です。

## LXD に接続できない場合

`ClientConnectionFailed` と `PermissionError(13, 'Permission denied')` が出た場合は、Snapcraft が LXD の Unix ソケットへ接続できていません。現在のシェルで次を確認します。

```sh
id -nG
getent group lxd
lxc info local:
```

`getent group lxd` にユーザー名があり、`id -nG` に `lxd` が無い場合は、ログアウトして再ログインするか `newgrp lxd` で新しいシェルを開きます。`getent group lxd` にユーザー名が無い場合は `sudo usermod -aG lxd "$USER"` で追加し、再ログインします。新しいシェルでは `deb` などのシェル変数を設定し直してください。`lxc info local:` が成功してからビルドを再実行します。
