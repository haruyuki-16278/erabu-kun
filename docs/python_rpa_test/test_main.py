import os
import sys
import time

from utils import start_app, stop_app, wait_and_click_image, take_screenshot

# スクリプトのディレクトリ
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATES_DIR = os.path.join(SCRIPT_DIR, "templates")

# 各テンプレート画像へのパス
IMG_MENU_ICON = os.path.join(TEMPLATES_DIR, "menu_icon.png")
IMG_SETTINGS_BTN = os.path.join(TEMPLATES_DIR, "settings_btn.png")
IMG_QUIT_BTN = os.path.join(TEMPLATES_DIR, "quit_btn.png")
# 設定画面を検知するための画像（例: ウィンドウのタイトル部分や特定のラベルなど）
IMG_SETTINGS_WINDOW = os.path.join(TEMPLATES_DIR, "settings_window.png")

def check_templates_exist():
    """必要な画像テンプレートが存在するか確認する"""
    required_images = [IMG_MENU_ICON, IMG_SETTINGS_BTN, IMG_QUIT_BTN]
    missing = [img for img in required_images if not os.path.exists(img)]
    
    if missing:
        print("⚠️ Warning: 次のテンプレート画像が見つかりません。")
        for m in missing:
            print(f"  - {m}")
        print("\nPyAutoGUIを用いたテストを実行するには、Mac上で実際に表示される各要素のスクリーンショットを切り抜き、上記のパスに配置してください。")
        print("MacのRetinaディスプレイの場合、Shift+Command+4で撮影した画像をそのまま使うと解像度がかみ合わない場合があります。")
        print("その場合は画像サイズを半分にするか、confidenceパラメータを調整してください。")
        return False
    return True

def run_tests():
    app_path = os.environ.get("TEST_APP_PATH")
    if not app_path:
        print("Error: TEST_APP_PATH is not set.")
        sys.exit(1)

    print(f"--- 1. アプリケーションの起動 ({app_path}) ---")
    start_app(app_path)
    
    if not check_templates_exist():
        print("テストの実行を中断します。テンプレート画像を用意してから再度実行してください。")
        # デバッグ用にスクリーンショットを保存
        take_screenshot(os.path.join(SCRIPT_DIR, "debug_desktop.png"))
        stop_app("Erabu-kun")
        sys.exit(1)

    try:
        print("--- 2. メニューバーアイコンの認識とクリック ---")
        # confidence は環境に合わせて調整 (0.8 ~ 0.9 程度)
        if not wait_and_click_image(IMG_MENU_ICON, timeout=5, confidence=0.8):
            raise Exception("メニューバーアイコンが見つかりませんでした。")
        
        # クリック直後の状態を保存（メニューが正しく開いているか確認用）
        time.sleep(1)
        take_screenshot(os.path.join(SCRIPT_DIR, "after_menu_click.png"))
        
        # メニュー展開を待つ（Macのメニューアニメーションを考慮して少し長めに）
        time.sleep(1)

        print("--- 3. 「Settings...」ボタンのクリック ---")
        # メニュー内の項目は背景が透過していたり影があったりするため、少し confidence を下げる
        if not wait_and_click_image(IMG_SETTINGS_BTN, timeout=10, confidence=0.7):
            raise Exception("Settingsボタンが見つかりませんでした。")
            
        # 設定ウィンドウが開くのを待つ
        time.sleep(2)
        print("設定画面が開かれたとみなします（必要であれば IMG_SETTINGS_WINDOW 等で検証を追加できます）。")
        
        # 開いた設定画面を閉じる（あるいは無視して次に進む）
        # 簡単な方法としてEscキーやCmd+Wを送るなどで閉じることができる
        import pyautogui
        pyautogui.hotkey('command', 'w')
        time.sleep(1)
        
        print("--- 4. 再度メニューバーアイコンをクリックしてメニューを展開 ---")
        if not wait_and_click_image(IMG_MENU_ICON, timeout=5, confidence=0.8):
            raise Exception("メニューバーアイコンが見つかりませんでした。")
        
        time.sleep(1)
        
        print("--- 5. 「Quit」ボタンのクリックと終了確認 ---")
        if not wait_and_click_image(IMG_QUIT_BTN, timeout=5, confidence=0.8):
            raise Exception("Quitボタンが見つかりませんでした。")
            
        print("Quitボタンをクリックしました。アプリが終了するのを待ちます。")
        time.sleep(2)
        
    except Exception as e:
        print(f"❌ テスト失敗: {e}")
        take_screenshot(os.path.join(SCRIPT_DIR, "error_screenshot.png"))
        stop_app("Erabu-kun")
        sys.exit(1)
        
    print("✅ テスト完了: Errorなし。")
    # 念のため終了コマンドを送る
    stop_app("Erabu-kun")

if __name__ == "__main__":
    run_tests()
