---
name: vela-app-verification
description: Verify Vela changes with unit tests, release builds, bundle signing, isolated CLI checks, and a launched-app smoke test. Use after changing Vela code, configuration, CLI, app behavior, or build scripts and before committing.
---

# Vela App Verification

Vela の変更を、ビルド成功だけでなく実際の署名済み App と CLI/App 間通信まで確認する。

## 1. 変更範囲を確認する

`git status --short` と `git diff --check` を実行する。ユーザーの既存差分を上書きせず、検証対象の機能と必要な smoke test を決める。

## 2. 自動検証を通す

リポジトリルートで次を実行する。

```sh
swift test
swift build --configuration release
./Scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 Vela.app
test -x Vela.app/Contents/MacOS/Vela
test -x Vela.app/Contents/Helpers/vela
Vela.app/Contents/Helpers/vela
```

最後のコマンドは usage を表示して正常終了することを確認する。既存警告と新規警告を区別し、新しい警告は修正する。

CLI の設定読み書きに触れた場合は、ユーザーの `~/.config/vela` を使わず隔離して確認する。

```sh
vela_test_dir=$(mktemp -d /tmp/vela-verification.XXXXXX)
VELA_CONFIG_HOME="$vela_test_dir" Vela.app/Contents/Helpers/vela init
VELA_CONFIG_HOME="$vela_test_dir" Vela.app/Contents/Helpers/vela check
```

終了時は `vela_test_dir` が `/tmp/vela-verification.` で始まることを確認してから、`trash "$vela_test_dir"` でそのディレクトリだけを退避する。

## 3. 署名済み App を実際に確認する

起動中の Vela とその実行パスを先に記録する。`open Vela.app` で今回ビルドした App を起動し、プロセスが生存していることと実行パスがこのリポジトリの `Vela.app/Contents/MacOS/Vela` であることを確認する。

App/Overlay/IPC を変更した場合は、組み込み CLI で変更対象を表示する。

```sh
Vela.app/Contents/Helpers/vela show search
Vela.app/Contents/Helpers/vela show clipboard
Vela.app/Contents/Helpers/vela show windows
```

該当する画面だけを実行し、次を目視または UI 操作で確認する。

- パレットが表示され、検索欄が入力可能
- Escape で閉じる
- Clipboard は履歴または空状態を表示し、クラッシュしない
- Windows は権限不足の案内またはウィンドウ一覧を表示し、クラッシュしない
- CLI/権限変更では `vela doctor` と `vela permissions status` が App と通信して完了する

権限要求そのものを変更した場合だけ、対象権限の setup/request を対話端末で確認する。既存の許可をリセットしない。

## 4. 環境を戻して結果を報告する

検証用 App を終了する。検証前に別の Vela が動いていた場合は、最初に記録した実行パス（Homebrew 配下を含む）から元の App bundle を再度開き、同じ実行元へ戻ったことを確認する。

最後に `git diff --check` と `git status --short` を再実行し、次を報告する。

- unit test と release build の結果
- bundle/signing と CLI isolation test の結果
- 実際に起動して確認した画面・操作
- 環境依存で未確認の項目
