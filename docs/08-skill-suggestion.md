# 08. skill suggestion cookbook の追試(mizchi/skills で)

[docs.typesafe.ai/cookbooks/skill_suggestion](https://docs.typesafe.ai/cookbooks/skill_suggestion) の再現。
cookbook は Nous Research の Hermes(182 スキル)で「そのターンにどのスキルを 1 つ読み込むか」を
Jev に決めさせるが、ここでは [mizchi/skills](https://github.com/mizchi/skills)(68 スキル)で同じことをする。

再現:

```bash
cd experiments/skill-suggestion && npm install
npx tsx src/roster.ts --skills-dir /home/user/mizchi/skills   # roster を作る
npx tsx src/dataset.ts --resume                                # 評価用リクエストを生成
TYPESAFEAI_API_KEY=... npx tsx src/run.ts --limit 90 --concurrency 5
```

---

## 1. 何をするものか

エージェントのスキル一覧は**説明が 60 文字に切り詰めて**渡される。cookbook が測った Hermes では
その結果、関連するリクエストで **16.8%** 誤ったスキルを読み込み、どれも要らないリクエストで
**9.8%** 無駄に読み込んでいた。

対策は、エージェントが決める**前に** Jev を 2 段通す:

| 段 | リクエスト | 内容 |
| --- | --- | --- |
| 1 | 1 回 | 全スキルの `choice`(エージェントと**同じ切り詰め説明**)+ noul 3 問のゲート |
| 2 | 1 回 | 上位 3 件だけ、**full description + `SKILL.md` 先頭 700 文字**で `choice` + 候補ごとの fit noul |

ゲートの 3 問(cookbook の文言そのまま):

1. 「ユーザーのファイル・アカウント・端末・オンラインサービスに**作用する**ことを求められているか(説明や助言だけではなく)」
2. 「慎重な専門家なら、一般的な理解ではなく**特定の手順書やコマンド列**を参照するか」
3. 「知識のあるジェネラリストが、ツールもアクセスも無しに**文章だけで**満たせるか」

3 問目はスキルが**不要**な方向の証拠なので、反転して平均する。平均 < 0.30 なら何も提案しない。
段 2 では候補ごとの fit noul の最大値が < 0.30 なら何も提案しない。

提案はシステムプロンプトの roster 直後に 1 行入る:

```
<skill_relevance>
Relevant to the current request: <name>. Ignore this if it does not fit what the user actually asked for.
</skill_relevance>
```

## 2. 設計で目を引いた点

**段 1 の `choice` に「どれでもない」選択肢が無い。** 必ず 1 つを名指しする。
それを止めているのが**別立ての noul ゲート**で、これは
[00 の closed-world 問題](00-api-notes.md#closed-world)に対して私が
「Fix B: スコープ判定を fan-out で同じリクエストに混ぜる」と書いたものと同じ形。
独立に同じ設計に着いている。

**roster 全体が 1 問に収まる。** 182 も 68 も
[255 選択肢の上限](00-api-notes.md#name-only)の内側。
上限を超える roster では事前フィルタが必要になる。

**段 1 の criteria はエージェントと同じ切り詰め説明を使う。** ここが設計として綺麗なところで、
「Jev には情報を余分に渡しているから当たる」のではない。段 1 は**同じ情報で順位付けだけ**して、
情報を足すのは上位 3 件に絞った段 2 だけ。

## 3. cookbook との条件差

| | cookbook | この追試 |
| --- | --- | --- |
| roster | Hermes 182 | mizchi/skills **68** |
| 評価件数 | 488(315 covered / 173 none) | **90**(68 / 22) |
| 評価セット | 既存 | **生成**(リークの risk) |
| Jev | `jev-1.12` | `jev-latest`(応答 `jev-1.13.0`) |
| エージェント | `claude-haiku-4-5-20251001` | 同じ |
| 切り詰めによる衝突 | 密集(問題の核) | **先頭 30 文字の衝突は 0** |

最後の行が結果の読み方に効く。cookbook の前提は「182 個を 60 文字に切ると似たものが
区別できなくなる」だが、`mizchi/skills` は 68 個で説明の頭が被っていない
(`roster.ts` が数える衝突グループは 0)。つまり**課題としては cookbook より易しい**。
エージェント単独の誤読み込み率が 16.8% より低く出たら、それは Jev の性能ではなく roster の性質。

## 4. 結果

<!-- src/run.ts の出力から -->

## 5. 正直な限界

- **評価セットがスキル説明から生成されている。** 「説明の言い回しを写さない・スキル名を出さない・
  状況だけ書く」と指示してはいるが(`src/dataset.ts`)、リークは減らせても消せない。
  **絶対値は楽観的**で、意味があるのはアーム間の比較。両アームは同じリクエストを見ている。
- 90 件(cookbook は 488 件)。1 件の増減が 1 ポイント以上動く。
- `none` 側 22 件は「どのスキルも要らないリクエスト」を生成させたもので、
  実際のユーザー分布ではない。
- スキルを「読み込んだ後に成績が上がるか」は測っていない。cookbook と同じく、
  **読み込み判断の正しさ**だけを測っている。
