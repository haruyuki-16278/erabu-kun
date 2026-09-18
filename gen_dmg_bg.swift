import Cocoa
import Foundation

let width: CGFloat = 480
let height: CGFloat = 260

let img = NSImage(size: NSSize(width: width, height: height))
img.lockFocus()

// 背景を白に近い明るいグレーに塗る
let bgColor = NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
bgColor.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

// 枠線をうっすらと
NSColor.lightGray.setStroke()
let border = NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height))
border.lineWidth = 2
border.stroke()

// 上から110px が アイコンのY座標。
// Bottom-Left基準なので Y = 260 - 110 = 150付近がアイコンの中心
let iconYCenter: CGFloat = 150

// 矢印を描画
let arrowPath = NSBezierPath()
let arrowStartX: CGFloat = 190
let arrowEndX: CGFloat = 290
let arrowY: CGFloat = iconYCenter

arrowPath.move(to: NSPoint(x: arrowStartX, y: arrowY))
arrowPath.line(to: NSPoint(x: arrowEndX, y: arrowY))
arrowPath.lineWidth = 4

// 矢印の先端
arrowPath.move(to: NSPoint(x: arrowEndX - 15, y: arrowY + 10))
arrowPath.line(to: NSPoint(x: arrowEndX, y: arrowY))
arrowPath.line(to: NSPoint(x: arrowEndX - 15, y: arrowY - 10))

NSColor.systemBlue.setStroke()
arrowPath.stroke()

// テキストを描画
// "Erabu-kun をドラッグ＆ドロップしてインストール"
let text = "Erabu-kun をドラッグ＆ドロップしてインストール"
let font = NSFont.systemFont(ofSize: 16, weight: .bold)
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center

let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.darkGray,
    .paragraphStyle: paragraphStyle
]

let textStr = NSAttributedString(string: text, attributes: attributes)
// テキストのサイズを計算
let textSize = textStr.size()
let textRect = NSRect(
    x: (width - textSize.width) / 2,
    y: iconYCenter - 70, // アイコンの下に配置
    width: textSize.width,
    height: textSize.height
)
textStr.draw(in: textRect)

img.unlockFocus()

// NSImageをPNGデータに変換して保存
guard let tiffData = img.tiffRepresentation,
      let bitmapImage = NSBitmapImageRep(data: tiffData),
      let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
    print("PNG変換エラー")
    exit(1)
}

let fileURL = URL(fileURLWithPath: "dmg-background.png")
do {
    try pngData.write(to: fileURL)
    print("生成成功: dmg-background.png")
} catch {
    print("保存エラー: \(error)")
    exit(1)
}
