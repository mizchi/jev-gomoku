# 12. 間違ったドラフトを正しいアクションで取り返す

[11](11-synergy.md) は「**正しいシナジーを選ぶと勝つ**」を測った。その裏返しを測る:
**グランド戦略(ドラフト)を間違えても、正しいアクションが取れれば取り返せるか。**

切り分けは 1 つ:**正しいアクション = Jev、拙いアクション = scripted bot**。同じ 2 編成のまま、
「どちらが上手く操作するか」だけを入れ替えた 3 セルで測る。

再現:

```bash
# BAD=classic を Jev が、GOOD=bruiser_mix を scripted が持つ、など 3 セルを自動で回す
moon run --target native cmd/moba -- --comeback --bad classic --good bruiser_mix --games 3
moon run --target native cmd/moba -- --comeback --bad glass_ad --good bruiser_mix --games 3 --replay out/cb.jsonl
moon run --target native cmd/moba_replay -- --file out/cb.jsonl   # 取り返した試合を再生
```

---

## 1. セットアップ

- **グランド戦略 = ドラフト**。間違い = 弱い編成。
- BAD 編成を**両サイドで**走らせてサイド有利を相殺し、BAD 視点の勝敗を数える。
- 3 セル、編成は固定で操作の質だけ変える:

| セル | BAD 側 | GOOD 側 | 問い |
| --- | --- | --- | --- |
| 1. equal play | scripted | scripted | ドラフト差は本物か |
| 2. scenario | **Jev** | scripted | 正しいアクションで取り返せるか |
| 3. ceiling | **Jev** | **Jev** | 両者が上手いとき差は戻るか |

[11 §4](11-synergy.md#4-フルゲームだと薄まる--総当たり) のとおり、フルゲームのドラフト差はマクロで薄まって僅差
(scripted 同士で構造体マージン ~24–30/350)。**だからこそ**大きい行動差で買い戻す余地がある。

## 2. 結果 — `classic`(素の均一編成)を間違ったドラフトに

```
cell                                  BAD(classic) W-L-D   →
 1. equal play    scripted vs scripted     0-2-0     GOOD wins
 2. scenario      classic+Jev vs bruiser_mix+scripted  5-1  BAD recovers
 3. ceiling       classic+Jev vs bruiser_mix+Jev        2-4  GOOD wins
```

きれいな 3 段:

- **ドラフト差は本物**(セル 1、0–2)。同条件なら bruiser_mix(前衛+AD+AP)が classic に勝つ。
- **正しいアクションで取り返せる**(セル 2、5–1)。classic を Jev が持つと、bruiser_mix を持つ scripted に勝ち越す。
- **ただし天井がある**(セル 3、2–4)。相手も Jev だと、ドラフト差が戻って GOOD が勝つ。

**取り返しには限界がある。** 弱いドラフトは「相手が下手なら」正しいアクションで買い戻せるが、
**相手も同じく上手いと編成差は戻る**。アクションはドラフト赤字を**買い戻す**が、ドラフトを**良くはしない**。

取り返した試合(classic+Jev、リプレイ)を見ると、行動差の中身が分かる。Jev の A は**タワーに繰り返しダイブして構造体を割り続け**(`A_top was killed by the tower at b_top` が何度も出る)、
死を対価に objective を押す。一方 scripted の bruiser_mix は**リコールを繰り返して受け身**(`B_top recalled; B_bot recalled` の連発)。
「正しいアクション」の正体は、この局面では**objective への圧の掛け方**だった。

## 3. ひねり — `glass_ad`(3 キャリー・前衛なし)を間違ったドラフトに

同じ 3 セルを、より「いかにも悪いドラフト」(前衛なし・全 AD・全キャリー)で:

```
cell                                  BAD(glass_ad) W-L-D   →
 1. equal play    scripted vs scripted     0-2-0     GOOD wins
 2. scenario      glass_ad+Jev vs bruiser_mix+scripted  5-1  BAD recovers
 3. ceiling       glass_ad+Jev vs bruiser_mix+Jev        5-1  BAD recovers (!)
```

セル 3 が返らない。glass_ad は Jev が持つと、**相手も Jev でも勝つ**。

つまり glass_ad は **scripted には弱いが Jev には強い**。「弱いドラフト」という判定(セル 1)は、
編成そのものではなく **scripted という操作者への判定**だった。ある種の「間違ったグランド戦略」は、
**下手な操作者にとってだけ間違い**で、正しく操作すれば最初から不利ですらない。
これは [11 §3–4](11-synergy.md#3-正しいシナジーは勝つか--チーム戦アリーナ) の「アリーナと
フルゲームで編成順位がねじれる(順位は policy 依存)」と同じ構図だ。

## 4. なぜ取り返せるのか

- **ドラフト赤字は小さい。** マクロ希釈でフルゲームの編成差は僅差(§1)。
- **行動黒字は大きい。** [02](02-moba.md#2-結果) で Jev は同じ scripted bot に 6–0。行動の質の差は編成差より大きい。
- 小さい赤字を大きい黒字が上回るので、**弱いドラフト + Jev > 強いドラフト + scripted**。
  ただし黒字が両サイドに乗る(セル 3、両 Jev)と赤字だけが残り、classic では GOOD に戻る。

## 5. この scenario で言えること

1. **間違ったグランド戦略は正しいアクションで取り返せる** —— ただし相手が同等に上手いと戻る
   (classic: 5–1 → 2–4)。**取り返しには天井がある。** アクションは戦略の赤字を買い戻すが、戦略を良くはしない。
2. **「間違い」は編成ではなく操作者への判定のことがある。** glass_ad は scripted に弱く Jev に強く、
   セル 3 でも取り返した。ドラフトの良し悪しは **policy 依存**。
3. 実務的な含意: **上流(戦略・プロンプト設計)の小さなミスは、下流(tick ごとの正しい判断)の
   積み重ねで吸収できることがある。** ただし相手/基準も強いなら、上流を直すほうが確実。

## 6. 正直な限界

- **scripted bot が弱い**ので行動差が大きく出る([02](02-moba.md#4-正直な限界) のまま)。もっと強い
  基準相手なら取り返し幅は縮むはず。「Jev が特別強い」というより「scripted が弱い」が正確。
- フルゲームのドラフト差が僅差(macro 希釈)なのが前提。差が支配的な題材だと取り返せないだろう。
- n=3/side(6 ゲーム/セル)。5–1 や 2–4 は**方向は明確だが小標本**。決定論ではなく Jev の分散が乗る。
- BAD/GOOD は `--bad/--good`(編成名)で差し替え可能。ここでは 2 例だけ。

## 7. 次に試すこと

- 強い scripted bot(集団プッシュ + 引き)を基準にして、取り返し幅がどこまで縮むか。
- 「取り返せない」編成差の探索: どのドラフト赤字までなら Jev の行動で買い戻せるかの境界。
- [11 §5](11-synergy.md#5-jev-は編成を選べるか--ドラフト) の draft と接続: Jev に**わざと**弱い編成を持たせ、
  それでも Jev の行動で勝てるかを一気通貫で。
