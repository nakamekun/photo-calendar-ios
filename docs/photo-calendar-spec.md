# Photo Calendar 現仕様

## コンセプト

- Photo Calendar は写真管理アプリではなく、1日を1枚で残す写真カレンダーである。
- カレンダーや widget に表示されるのは picked 済み写真のみである。
- 純正写真アプリと競うのではなく、日付と1枚の関係を気持ちよく残す体験を重視する。

## Pick の基本ルール

- 各日には代表写真を1枚 picked できる。
- picked は manual pick と auto pick の2種類で管理する。
- picked されていない日は no photo selected 扱いにする。
- 1日に保持する picked 写真は1枚のみで、Random Pick や manual pick は既存 picked を置き換える。

## 表示ルール

- カレンダーに表示するのは picked 済み写真のみである。
- picked がない日は、写真が存在していてもカレンダーに写真を表示しない。
- 「写真があるから表示する」フォールバックはしない。
- 日別画面は、その日の picked がある場合に代表写真として表示する。
- 日別画面で picked がない場合は空状態を表示し、下部の写真一覧から manual pick できる。

## Auto Pick

- auto-pick は初回のみ実行する。
- auto-pick は picked がなく、auto-pick resolved でもない日だけを対象にする。
- 一度 auto-picked された日は、次回起動後も同じ picked 写真を維持する。
- manual pick がある日は auto-pick しない。
- unpick 後は auto-pick を再実行しない。
- auto-pick は screenshot を除外した候補から1枚選ぶ。
- screenshot しかない日は auto-pick せず、auto-pick resolved として記録する。
- 月表示時は、表示対象月の未確定日だけを軽量に auto-pick 対象として処理する。

## Manual Pick / Unpick

- manual pick はユーザーが明示的に選んだ写真である。
- auto pick / manual pick のどちらも unpick できる。
- unpick した日は no photo selected になる。
- unpick 後は auto-pick resolved として扱い、auto-pick が復活しない。
- unpick 後の日別画面では、picked がなく auto-pick resolved の場合に `Auto-pick disabled for this day` を小さく表示する。

## Random Pick

- Random Pick は、その日の screenshot 除外後の候補から1枚を選ぶ。
- Random Pick で選んだ写真は manual pick 扱いで保存する。
- Random Pick は現在開いている日の picked 写真だけを差し替える。
- widget から開いた日で Random Pick しても、widget の対象日が still picked である限り日付は維持し、asset identifier だけ追従する。

## Screenshot 除外

- auto-pick と Random Pick は `PHAssetMediaSubtype.photoScreenshot` を持つ asset を候補から除外する。
- manual pick の UI 上の通常タップ選択は、現状実装では写真一覧に表示される asset を選べるため、screenshot 自体の選択を完全にはブロックしていない。
- auto-pick 用候補は、日別に除外された asset identifier も除外する。

## Widget

- widget に表示する候補は picked 済みの日のみである。
- 未picked 日、unpick 済み日、no photo selected の日は widget 候補に含めない。
- 候補がない場合、または有効な picked 画像を解決できない場合は `No memories yet` の空状態を表示する。
- widget は small / medium / large を提供する。
- small / medium / large はそれぞれ独立した選定状態を持つ。
- widget は3時間ごとに表示写真を切り替える。
- 同じ3時間 bucket 内では、各サイズの選定状態を保存して再利用する。
- widget の View body 再評価では random 選定しない。
- widget の写真は全面表示し、`scaledToFill` 相当で widget bounds を埋める。
- widget タップで、その表示中の日付の詳細画面を開く。

## Widget 選定状態

- widget は App Group の UserDefaults にサイズ別の選定状態を保存する。
- 保存する主な値は day key、asset identifier、3時間 bucket の開始時刻である。
- 既存のサイズ別選定が同じ bucket で、day と asset が still picked なら再利用する。
- 同じ day が still picked で asset だけ変わった場合は、day を維持して asset identifier だけ更新する。
- その day が unpick されて候補から消えた場合のみ、別の picked 日へ再選定する。

## Deep Link

- widget の deep link は `photocalendar://day?date=yyyy-MM-dd` を使う。
- 互換用に `photocalendar://day/yyyy-MM-dd` も受け取れる。
- deep link で該当日の `DayPhotosView` を開く。
- cold start でも background 復帰でも遷移できるよう、受信した日付を pending state に保持する。
- scene が active になった時点で pending deep link を適用する。
- deep link 適用時は NavigationStack を明示的にリセットし、前回開いていた画面より widget の日付を優先する。

## 状態管理

- picked selection は `SelectedPhotoStore` に保存する。
- picked selection には代表 asset identifier、latest asset identifier、source、updatedAt を保持する。
- auto-pick を一度試行済み、または再試行しない日は auto-pick resolved day key として保存する。
- widget のサイズ別選択状態は App Group の UserDefaults に保存する。
- app 本体と widget は同じ App Group を通じて picked 情報を共有する。

## UX 方針

- 設定を増やさず、操作結果そのものを状態として扱う。
- `Disable Auto Pick` のような設定 UI は置かない。
- 余計な説明やラベルはできるだけ減らす。
- 機能追加よりも、1日1枚の体験の気持ちよさを優先する。
