# FocusBlur（人物フォーカスぼかし MVP）

選んだ1人だけをくっきり残し、背景と他の人物を玉ボケでぼかした動画を書き出す iOS 17+ アプリ。

## ビルドと配布（GitHub Actions）

Mac は不要。`.github/workflows/ios.yml` がクラウドの Mac で XcodeGen → ユニットテストを実行する（main への push ごと）。

TestFlight へ配布するときは、GitHub の Actions タブ →「iOS」→「Run workflow」で **upload** をオンにして実行する。
必要な Secrets：`APPLE_TEAM_ID` / `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8`（.p8 の中身）。
App Store Connect に Bundle ID `com.sammy.focusblur` のアプリを作っておくこと。

アイコンは `python scripts/make-icon.py` で作り直せる。

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
