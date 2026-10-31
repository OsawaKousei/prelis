# GitHub Releases の公開資料

リリースごとの資料を `v<version>/` に保存します。各版のリリースノートと、その版の署名検証に使う公開鍵をまとめます。

| 版 | リリースノート | 案内する配布物 |
| --- | --- | --- |
| v0.1.2 | [release-notes.md](v0.1.2/release-notes.md) | Ubuntu amd64 向け deb・AppImage |
| v0.1.1 | [release-notes.md](v0.1.1/release-notes.md) | 既存の各プラットフォーム向け案内 |

## 保存する資料

| ファイル | 用途 |
| --- | --- |
| `v<version>/release-notes.md` | GitHub Release の本文に使用する原稿 |
| `v<version>/prelis-release-signing-key.asc` | その版の deb・AppImage の検証用公開鍵。GitHub Release の Assets に添付する |
| `v<version>/sha256sums.txt` | 公開対象ファイルの SHA-256。作成した版では Assets に添付する |

過去版の資料と公開鍵は保存し、新しい版では新しいディレクトリを作成します。署名鍵を変更した場合も、過去版の公開鍵は置き換えません。秘密鍵はこのディレクトリに保存しません。

ビルド成果物本体と分離署名は、Git 管理対象外の `dist/linux/v<version>/` に保持します。公開資料のディレクトリには重複配置しません。
macOS の公証済み ZIP・DMG・`SHA256SUMS` は `dist/macos/v<version>/` に保持します。生成と検証は [macOS 配布物の手順](../../docs/development/dist/macos/sign.md)を参照してください。
Android の署名付き AAB・APK・`SHA256SUMS` は、`apps/mobile/package.json` の版を使った `dist/android/v<version>/`（今回は `v0.1.3`）に保持します。作成と検証は [Android 配布物の手順](../../docs/development/dist/android/sign.md)を参照してください。直接頒布するのは `PrelisMobile_<version>_github.apk` です。

## v0.1.2 の公開対象

| Assets に添付するファイル | ローカルの保存先 |
| --- | --- |
| `PrelisDesktop_0.1.2_amd64.deb` | `dist/linux/v0.1.2/PrelisDesktop_0.1.2_amd64.deb` |
| `PrelisDesktop_0.1.2_amd64.deb.asc` | `dist/linux/v0.1.2/PrelisDesktop_0.1.2_amd64.deb.asc` |
| `PrelisDesktop_0.1.2_amd64.AppImage` | `dist/linux/v0.1.2/PrelisDesktop_0.1.2_amd64.AppImage` |
| `PrelisDesktop_0.1.2_amd64.AppImage.asc` | `dist/linux/v0.1.2/PrelisDesktop_0.1.2_amd64.AppImage.asc` |
| `prelis-release-signing-key.asc` | [v0.1.2/prelis-release-signing-key.asc](v0.1.2/prelis-release-signing-key.asc) |
| `sha256sums.txt` | [v0.1.2/sha256sums.txt](v0.1.2/sha256sums.txt) |

`release-notes.md` は本文として使用します。この一覧は公開準備用であり、GitHub 上へのアップロード完了を示すものではありません。

公開前に署名・ハッシュと対象 Ubuntu でのインストール・起動・更新を確認します。成果物や署名が変わった場合はチェックサムを再計算し、公開済みの同じ版を内容だけ変えて再頒布しません。ビルドと検証は [Linux 配布物の手順](../../docs/development/dist/linux/sign.md)を参照してください。
