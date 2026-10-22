# FocusBlur（人物フォーカスぼかし MVP）

選んだ1人だけをくっきり残し、背景と他の人物を玉ボケでぼかした動画を書き出す iOS 17+ アプリ。

## ビルド（Mac）

```sh
brew install xcodegen
xcodegen generate          # project.yml から FocusBlur.xcodeproj と Info.plist を生成
open FocusBlur.xcodeproj   # Signing の Team を設定して実機で実行
xcodebuild test -scheme FocusBlur -destination 'platform=iOS Simulator,name=iPhone 15'
```

Vision の人物インスタンスマスクは実機での確認を推奨。

## 構成

| ファイル | 役割 |
|---|---|
| `Processing/SubjectTracker.swift` | 顔追跡・10フレームごとの補正・見失い判定・特徴量による再認識 |
| `Processing/PersonMaskProvider.swift` | 対象インスタンスの選択・時間方向の平滑化・フェザー |
| `Processing/BokehRenderer.swift` | 玉ボケと合成 |
| `Processing/FocusPipeline.swift` | 1フレームの処理の流れ、見失い猶予・全体ぼかし・フェードイン |
| `Processing/VideoExporter.swift` | 読み出し・書き出し・音声パススルー・進捗・キャンセル |
| `Processing/PreviewRenderer.swift` | 調整画面のプレビュー |
| `Utilities/CoordinateConverter.swift` | 表示座標 ⇔ Vision 正規化座標、向きの変換 |
| `Utilities/Constants.swift` | 閾値・係数 |

### 向きの扱い

Vision の解析は表示の向きに回転・縮小したフレーム（長辺1080px）で行い、得られたマスクだけを
バッファの向きに戻して合成する。書き出しのピクセルは回転前のまま、`preferredTransform` を
writer の `transform` に設定する。

## 実機で調整したい定数

- `reidentifyDistanceThreshold` / `identitySwitchDistance`：再認識と乗り移り防止の距離（Revision2 の特徴量の距離）
- `bokehRingAmount` / `bokehSoftness`：玉ボケの見た目
- `bokehWorkingLongSide`：4K での速度と画質のバランス
