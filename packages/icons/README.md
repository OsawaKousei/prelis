# 共有アイコン

`assets/*.png` がデスクトップとモバイルで使うアイコンの正本です。機能アイコンは 128×128 px の透過 PNG で、黒い線の透明度を使って描画時に各アプリのテーマ色を付けます。`brand.png` は 512×512 px のカラー画像です。SVG のパス定義はアプリ内に持ちません。

新しいアイコンを SVG から作る場合は、一時ディレクトリに SVG ファイルを置いて変換します。変換後は PNG を確認し、`src/index.ts` の名前と両アプリの画像参照を追加します。既存の PNG を置き換える場合だけ `--force` を指定します。

```sh
npm run convert -w packages/icons -- /path/to/svg-directory
npm run convert -w packages/icons -- /path/to/brand-svg-directory --size 512
npm run convert -w packages/icons -- /path/to/svg-directory --force
```

変換には `@resvg/resvg-js` を使います。機能アイコンの SVG は 24×24 の `viewBox`、透過背景、黒い線で作成します。変換元の SVG は一時的な入力で、Git には追加しません。

Android のホーム画面用アイコンは `brand.png` から生成します。ブランド画像を変更したら次のコマンドでサイズ別画像と適応型アイコンの前景画像を更新します。

```sh
npm run launcher:android -w packages/icons
```

Windows・Ubuntu・macOS のデスクトップアプリアイコンも同じ `brand.png` から生成します。背景色・角丸・ロゴの配置は Android の通常アイコンと同じです。ブランド画像を変更したら、両方の生成コマンドを実行します。

```sh
npm run launcher:desktop -w packages/icons
```
