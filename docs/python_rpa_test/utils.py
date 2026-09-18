import os
import subprocess
import time
import pyautogui

def start_app(app_path):
    """アプリを open コマンドで起動する"""
    print(f"Starting app: {app_path}")
    if not os.path.exists(app_path):
        raise FileNotFoundError(f"App not found at {app_path}")
    
    subprocess.run(["open", app_path], check=True)
    # アプリが起動してメニューバーアイコンが表示されるまで少し待機
    time.sleep(3)

def stop_app(app_name="Erabu-kun"):
    """killall コマンドでアプリを終了させる"""
    print(f"Stopping app: {app_name}")
    try:
        subprocess.run(["killall", app_name], check=True, stderr=subprocess.DEVNULL)
        time.sleep(1)
        print("App stopped successfully.")
    except subprocess.CalledProcessError:
        print("App was not running or could not be stopped.")

def wait_and_click_image(image_path, timeout=10, confidence=0.8):
    """
    指定した画像が画面上に出現するまで待機し、見つかったら中心をクリックする
    
    :param image_path: テンプレート画像のパス
    :param timeout: タイムアウト（秒）
    :param confidence: 画像マッチングの精度（0〜1）
    :return: True (成功), False (失敗)
    """
    print(f"Waiting for image: {image_path} (timeout={timeout}s)")
    if not os.path.exists(image_path):
        print(f"Error: Template image not found - {image_path}")
        return False

    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            # grayscale=True にすると少し高速化＆安定化する場合がある
            location = pyautogui.locateCenterOnScreen(image_path, confidence=confidence, grayscale=True)
            if location:
                print(f"Image found at: {location}. Clicking via AppleScript...")
                
                # マウス移動
                pyautogui.moveTo(location.x, location.y, duration=0.2)
                
                # pyautogui.click() がメニュー展開に失敗する場合があるため、
                # AppleScript でクリックイベントをシミュレートする
                script = f'''
                tell application "System Events"
                    click at {{{location.x}, {location.y}}}
                end tell
                '''
                try:
                    subprocess.run(["osascript", "-e", script], check=True)
                except:
                    # フォールバック
                    pyautogui.click()
                
                time.sleep(0.5)
                return True
        except pyautogui.ImageNotFoundException:
            pass
        except Exception as e:
            print(f"Unexpected error during image search: {e}")
            pass
            
        time.sleep(0.5)
        
    print(f"Timeout: Image not found within {timeout} seconds.")
    return False

def take_screenshot(save_path):
    """画面全体のスクリーンショットを保存する（Mac標準コマンドを使用）"""
    print(f"Taking debug screenshot via screencapture: {save_path}")
    try:
        # Macの標準コマンドを使用。-x はシャッター音なし。
        subprocess.run(["screencapture", "-x", save_path], check=True)
    except Exception as e:
        print(f"Failed to take screenshot with screencapture: {e}")
        # フォールバック
        try:
            pyautogui.screenshot(save_path)
        except:
            pass
