#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${SCRIPT_DIR}/../../build/Erabu-kun.app"
VENV_DIR="${SCRIPT_DIR}/.venv"

echo "=== Erabu-kun RPA Test ==="

# 1. アプリケーションのビルド確認
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Application not found at $APP_PATH"
    echo "Please build the application first (e.g. run ../../build_release.sh)."
    exit 1
fi

# 2. Python 仮想環境のセットアップと依存パッケージのインストール
if [ ! -d "$VENV_DIR" ]; then
    echo "Setting up Python virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

echo "Installing/checking dependencies..."
pip install -q --upgrade pip
pip install -q -r "${SCRIPT_DIR}/requirements.txt"

# 3. テストの実行
echo "=== Running Tests ==="
# APP_PATH を環境変数経由でスクリプトに渡す
export TEST_APP_PATH="${APP_PATH}"

python "${SCRIPT_DIR}/test_main.py"
TEST_EXIT_CODE=$?

# 4. 仮想環境の無効化と結果の表示
deactivate

if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "✅ Tests passed successfully!"
else
    echo "❌ Tests failed with exit code: $TEST_EXIT_CODE"
    exit $TEST_EXIT_CODE
fi
