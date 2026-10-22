import CoreGraphics
import Foundation

/// 閾値・係数はすべてここに集める（実機で調整しやすくするため）
enum Constants {
    // MARK: 入力

    /// 受け付ける動画の最大長（秒）
    static let maxVideoDuration: Double = 60
    /// 「1:00」表示の動画が 60.03 秒などになるのを許容する誤差（秒）
    static let durationTolerance: Double = 0.1

    // MARK: 追跡

    /// 追跡結果の confidence がこれ未満なら「見失い」
    static let trackingConfidenceThreshold: Float = 0.5
    /// 何フレームごとに顔検出をやり直して追跡を補正するか
    static let redetectInterval = 10
    /// 補正に使う顔として採用する最小IoU
    static let redetectMinIoU: CGFloat = 0.3

    // MARK: 再認識（VNGenerateImageFeaturePrintRequest Revision2 の距離）

    /// 見失い中に検出した顔がこの距離以下なら同じ人として追跡を再開する
    static let reidentifyDistanceThreshold: Float = 0.6
    /// 定期補正のとき、IoU最大の顔でもこの距離を超えていたら別人とみなして補正しない（乗り移り防止）
    static let identitySwitchDistance: Float = 0.9
    /// 再認識で特徴量を計算する顔の最大数（大きい順）
    static let reidentifyMaxCandidates = 4
    /// 特徴量を取るとき顔矩形を広げる割合（各辺）
    static let faceCropPadding: CGFloat = 0.2

    // MARK: 見失い時の挙動

    /// 見失ってからこの秒数までは直前のマスクを使い続ける
    static let lostGraceDuration: Double = 0.5
    /// 復帰時にマスクをフェードインさせる秒数
    static let reacquireFadeDuration: Double = 0.3

    // MARK: マスク

    /// Vision 解析用フレームの長辺（px）
    static let analysisLongSide: CGFloat = 1080
    /// フェザー（CIGaussianBlur）の半径 = 長辺 × この値
    static let maskFeatherRatio: CGFloat = 0.003
    /// 時間方向の平滑化：今回のマスクの重み（前回の重みは 1 − この値）
    static let maskCurrentWeight: CGFloat = 0.7

    // MARK: 玉ボケ

    /// ボケ半径 = 強さ × 長辺 × この値
    static let bokehRadiusRatio: CGFloat = 0.02
    static let bokehRingAmount: CGFloat = 0.05
    static let bokehRingSize: CGFloat = 0.1
    static let bokehSoftness: CGFloat = 1.0
    /// ボケはこの長辺まで縮小してから計算し、元の解像度に戻す（4Kでの速度対策。ぼけた画像なので劣化は目立たない）
    static let bokehWorkingLongSide: CGFloat = 1920

    // MARK: 書き出し

    /// 元動画のビットレートが取れないときの目安（1画素・1フレームあたりのビット数）
    static let fallbackBitsPerPixel: Double = 0.1
    /// 進捗をメインスレッドに通知する間隔（フレーム数）
    static let progressReportInterval = 5

    // MARK: UI

    static let defaultStrength: Double = 0.6
    /// 調整画面プレビューの長辺（px）
    static let previewLongSide: CGFloat = 1280
    /// スライダー操作からプレビュー更新までの待ち時間
    static let previewDebounce: Duration = .milliseconds(150)
}
