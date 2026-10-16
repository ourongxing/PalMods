# 範囲スキルを至近距離で使用

1.1.0 · ourongxing

パルが敵に近づいてから、ボルカニックレイン、ロックバースト、ポイズンシャワーを使うようになります。

## 機能と使い方

この 3 つのスキルをパルが自動で使う際、対象から約 0.5 m 以内まで近づく必要があります。威力、クールタイム、攻撃範囲、ダメージ判定は標準のままです。

## 導入方法

1. 必要な Mod（UE4SSExperimentalPW, PalSchema）をサブスクライブして有効にします。
2. ゲーム内の Mod 管理で本 Mod を有効にします。
3. ゲームを完全に終了してから、再起動してください。

## 設定

Palworld のインストール先にある `Mods/NativeMods/UE4SS/Mods/PalSchema/mods/PointBlankBurstSkills/raw/point_blank_burst_skills.json` を編集し、保存後にゲームを完全に終了して再起動してください。

`MaxRange` で自動使用時の最大発動距離を指定します。初期値はゲーム内の 50 単位で、約 0.5 m です。

## 利用上の注意

同じ 3 つのスキルの発動距離を変更する Mod と併用した場合、読み込み順によって結果が変わります。

## 不具合の報告

不具合は GitHub Issues で報告してください：https://github.com/ourongxing/PalMods/issues

UE4SS ログがない場合、不具合の原因を特定して修正することができません。

調査のため、次の情報を添えてください。

- Mod 名、ゲームと Mod のバージョン、ゲームの言語。
- シングルプレイ、協力プレイのホスト、参加プレイヤー、専用サーバーのいずれか。
- 再現手順、期待した動作と実際の動作、関連するスクリーンショット、ほかに有効にしている Mod。
- 問題が起きた後の `UE4SS.log` 全体を添付してください。

Steam で Palworld を右クリック → 管理 → ローカルファイルを閲覧し、`Mods\NativeMods\UE4SS\UE4SS.log` を開いてください。
G ドライブにインストールしている場合の例：
`G:\SteamLibrary\steamapps\common\Palworld\Mods\NativeMods\UE4SS\UE4SS.log`

ドライブ名と Steam ライブラリの場所は、ご自身の環境に合わせて読み替えてください。ログが上書きされないよう、ゲームを再起動する前にコピーしてください。

## ソースコード

GPL-3.0 ライセンスで公開しています。
https://github.com/ourongxing/PalMods
