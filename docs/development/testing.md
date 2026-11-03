# テスト運用

## macOS ネイティブ E2E

日記を UI から保存し、アプリの終了・再起動を経ても内容が保持されることを XCTest / XCUIAutomation で確認します。テストの配置と責務は [E2E の README](../../tests/e2e/README.md)、検証内容は [日記の期待結果](../../tests/e2e/domains/diary/README.md)を参照してください。

### Mac の初回準備

- Xcode 本体を導入し、初回起動のセットアップを完了する。Python 3 も必要。XCTest・Swift は Xcode に含まれる。独立した Xcode プロジェクトを使うため、テストランナーの生成に Ruby・CocoaPods・追加 npm パッケージは不要。
- GUI にログインしているユーザーで実行する。SSH から実行する場合も同じユーザーを使い、画面のロック・スリープを避ける。
- 初回に XCTest の `Enable UI Automation` の認証が出たら、Mac の画面で Touch ID またはパスワードにより承認する。Xcode Helper の操作権限の確認が出た場合も承認する。
- テスト対象アプリを閉じる。起動済みなら、テストは終了させずに失敗とする。
- 既存の個人データとの干渉を避けるため、専用の macOS ユーザーを推奨する。既存ユーザーで実行する場合は、翌日から14日以内の空の日付を1つ使用し、テスト後に入力だけを消す。

`DEVELOPER_DIR` が未指定で標準位置に Xcode がある場合、ランナーが `/Applications/Xcode.app/Contents/Developer` を指定します。別の Xcode を使う場合は実行環境で指定します。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

### Mac 上で実行する

リポジトリのルートで実行します。アプリ本体のビルド・署名・インストールは行いません。テストランナーだけを ad-hoc 署名でビルドします。

以下は、公証済みの GitHub 配布向けアプリを使う例です。App Store 提出用とは Bundle ID・署名・Sandbox 条件が異なるため、このテストの成功を提出用ビルドの検証結果には流用しません。

```sh
bash scripts/macos/test-e2e.sh \
  --app /Users/kousei/prelis-remote/apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/macos/PrelisDesktop.app
```

任意の新しい出力先を使う場合は `--output /absolute/path/to/new-directory` を付けます。既存ディレクトリは再利用しません。

成功時の動画も保存する場合は、同じコマンドに `--record` を付けます。Xcode 標準の UI テスト画面記録を使用し、成功時にも自動添付物を保持して `recording.mp4` などへ取り出します。独自の撮影アプリは不要です。

Mac の記録はデスクトップ全体を含み、アプリ起動前・再起動中には他のウィンドウも映ります。今回の確認でも起動前に別アプリが映ったため、外部共有や審査用の撮影は専用ユーザーの整理したデスクトップで実施してください。

```sh
npm run test:e2e:macos -- \
  --app /Users/kousei/prelis-remote/apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/macos/PrelisDesktop.app \
  --record
```

### Ubuntu から実行する

`scripts/macos/.env` の既存の接続設定と SSH 鍵認証を使用します。`--app` は **Mac 上の絶対パス**です。

```sh
bash scripts/macos/test-e2e.sh \
  --app /Users/kousei/prelis-remote/apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/macos/PrelisDesktop.app
```

新しい `artifacts/e2e/<run-id>/source/` にテストコードのみを転送します。既存ソースの同期や上書き、アプリの再ビルドは行いません。終了後、ログと `.xcresult`・添付物を Ubuntu に回収します。大きな `derived-data/` は Mac に残します。Ubuntu 経由では出力先を自動採番し、`--output` は指定しません。

Ubuntu 経由でも `--record` を指定できます。動画も同じ実行 ID のフォルダへ回収します。

Mac の通常の Mutagen 同期では `artifacts` を除外します。この除外を追加した初回は既存の同期スクリプトの仕様によりセッションを再作成します。同期先のファイルは保持されるため、競合時は [Mac の同期手順](desktop.md#macos-で開発起動する)に従います。E2E の実行自体は Mutagen を使用しません。

### 生成物と判定

```text
artifacts/e2e/<run-id>/
├── remote.json                 # Ubuntu からの実行時のみ
└── macos/
    ├── manifest.json           # 対象アプリ、入力、テストソースの SHA-256
    ├── build.log
    ├── run.log
    ├── result.xcresult
    ├── summary.json
    ├── export.log
    ├── attachments/            # 保存後・再起動後の画面、失敗時の UI 階層
    ├── recording.mp4           # --record 指定時。形式や画面数により名前は異なる
    └── derived-data/           # Mac にのみ保持するビルド中間物
```

準備・ビルド・テストの失敗箇所により、後続の生成物は存在しない場合があります。結果は終了コードと `manifest.json` の `status` で確認します。

- `passed`: 指定した1件のテストが成功し、失敗・スキップがなく、対象の `.app` のハッシュも実行前後で一致。
- `failed`: テストの期待結果を満たさない、または対象テストが実行されていない。
- `environment-failed`: UI 自動操作の初期化・認証に失敗。アプリ機能の失敗とは区別する。
- `build-failed`: UI テストランナーのビルドに失敗。
- `execution-failed`: タイムアウト・結果収集・対象アプリの変更など、実行基盤で失敗。

GUI テストはユーザーごとのロックで直列実行します。自動リトライによって失敗を隠さず、再実行は別の実行 ID で保存します。タイムアウト後は対象アプリとテストランナーの状態、日記の後片付けを確認してください。

`test_status` と `recording.status` は独立して記録します。`--record` 指定時に動画を取得できなければ実行全体は失敗とし、UI テスト自体の結果は `test_status` に保持します。動画ができたことだけでテスト成功とは判定しません。

`.xcresult` は Xcode で開けます。画面・UI 階層には表示中の日記が含まれる可能性があるため、成果物は Git 管理対象外とし、外部共有時は内容を確認します。

### 実行基盤の回帰テスト

Mac へ接続せず、アプリの識別・実行設定の形式・結果判定を検証します。

```sh
python3 scripts/e2e/runner.test.py
```

### 現時点の範囲

macOS の日記保存・再起動テストと、任意の動画保存から導入します。審査に必要な他の機能の操作、iOS 実機のテストターゲットは今後追加します。今回の動画は日記のテスト記録です。審査提出用には、実際の提出対象・必要な全機能・映像と音声の内容を確認する必要があります。

提出物の検証では、`--app` が実際の提出対象と一致することを別途確認してください。バージョン番号とハッシュの記録だけで App Store Connect のビルドとの一致は保証しません。

### 初回の確認記録（2026-11-03）

- MacBook Air / macOS 27.2 / Xcode 27.1 で、日記の保存・アプリ終了・再起動後の完全一致・テスト入力の消去・アプリ終了まで成功。テスト1件、失敗0件、スキップ0件。
- 成功した対象は、公証済みの GitHub 配布向け v0.1.4（Bundle ID `jp.co.kupacllc.prelis`）。アプリ本体の追加ビルド・署名変更・インストールは実施していない。
- 既存の App Store 提出用 `.app`（Bundle ID `jp.co.kupac.prelis`）は、署名の整合性検証は通るが、ローカル起動時に OS が `No matching profile found` / `no eligible provisioning profiles found` で拒否。提出用ファイルは変更していない。実行可能な配布経路で導入した提出対象のビルドに対し、別途検証する必要がある。
- 初回の `Enable UI Automation` の認証待ちは、Mac 画面での本人認証後に解消。
- WebKit のカレンダーは `CheckBox` として取得。本文欄は名前と実際の枠を確認し、枠の中心をクリックする。入力済みの本文欄では XCTest の既定のヒット位置が取得できない事象があるため、絶対座標を固定しない。
- 実行基盤の回帰テスト9件は成功。iOS のビルド・実機テストは未実施。

通常実行の成功結果は、Mac と Ubuntu の `artifacts/e2e/20261103T113503Z-5902b8e1/macos/` に保存する。認証・起動・UI 操作の初期失敗も別の実行 ID で保持し、成功結果で上書きしない。

録画付きの成功結果は `artifacts/e2e/20261103T113655Z-d9b7bf82/macos/` に保存する。`recording.mp4` は約75.47秒・2940×1912・映像1トラック・音声0トラック。AVFoundation で読み取りとフレーム抽出を確認した。今回は日記の検証であり、タイマーの音声を含む検証には別途音声の収録・確認が必要。

録画付き実行後に、使用した `2026-11-04` の日記が0バイトに戻り、対象アプリのプロセスが終了していることを確認した。
