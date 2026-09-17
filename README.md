# jev-playground

TypeSafe AI の System One モデル **Jev** を MoonBit から触るためのプレイグラウンド。
Jev は「文字列ではなく**型付きの確率判断**を返す」意思決定専用モデルです(unstructured state in, typed probabilistic decisions out)。

このリポジトリには次の 4 つの部品が入っています。

| パッケージ | 内容 |
| --- | --- |
| `lib/` | Jev API クライアント(`GET /v1/models`・`POST /v1/systemone`、noul/choice/score 3 種の質問と型付き応答の JSON 変換) |
| `cmd/jev` | 単発質問 CLI(モデル一覧・state に対する型付き質問) |
| `cmd/gomoku` | 五目並べで Jev 同士を対戦させる CLI(毎手、盤面+着手候補を Jev に判断させる) |
| `cmd/gomoku_gif` | 対局ログ(各手の実測ミリ秒付き)を**実時間再生の GIF** に変換するツール |
| `cmd/patterns` | 公式ドキュメントの[意思決定パターン](https://docs.typesafe.ai/patterns)を実 API に対して走らせ、効果を実測する CLI |

## 必要なもの

- MoonBit ツールチェーン(`moon` 0.1.20260915 以降)
- TypeSafe AI の API キー(早期アクセス)

## セットアップ

```bash
export TYPESAFEAI_API_KEY=your_key_here
moon update   # 依存(tapi: moonbitlang/async, moonbitlang/x, mizchi/image, WGYo90/moonbit-gif)を取得
```

API キーはソースコードに書かず、環境変数 `TYPESAFEAI_API_KEY` か各 CLI の `--api-key` で渡します。

## 1. モデル一覧を確認

```bash
moon run --target native cmd/jev -- --models
# [{"name":"jev-latest",...},{"name":"jev-preview",...}]
```

## 2. 単発質問(コマンド/コマンドライン)

デモ(3 種の質問 — score / choice / noul — を 1 リクエストで並列評価):

```bash
moon run --target native cmd/jev -- --pretty
```

state を直接指定(テキスト or JSON 文字列):

```bash
moon run --target native cmd/jev -- --state "This email is a phishing attempt" --pretty
moon run --target native cmd/jev -- --state '{"amount": 299, "currency": "USD"}' --pretty
```

state と質問をファイルから:

```bash
moon run --target native cmd/jev -- --state-file state.json --questions-file questions.json
```

`questions.json` の形式(noul / choice / score を混在可能):

```json
{
  "is_spam": {
    "type": "noul",
    "instructions": "This message is spam.",
    "criteria": {
      "true": "Unsolicited advertising",
      "false": "A legitimate conversation"
    }
  },
  "tone": {
    "type": "choice",
    "instructions": "What is the tone of this message?",
    "criteria": {
      "polite": "Friendly and courteous",
      "neutral": "Calm and factual",
      "frustrated": "Angry or upset"
    }
  },
  "handler": {
    "type": "choice",
    "instructions": "Which handler owns this? (選択肢名だけで解釈させる形)",
    "criteria": { "billing": null, "technical": null, "sales": null }
  },
  "urgency": {
    "type": "score",
    "instructions": "How urgent is this request?",
    "criteria": ["Can wait", "Needs attention this week", "Needs attention today"]
  }
}
```

オプション: `--model`(既定 `jev-latest`)、`--base-url`、`--pretty`、`--api-key`

## 3. Jev vs Jev 五目並べ

```bash
moon run --target native cmd/gomoku --                     # 15x15 で 1 局
moon run --target native cmd/gomoku -- --board 9 --games 2 --verbose
moon run --target native cmd/gomoku -- \
  --player1 jev-latest --player2 jev-preview --board 15    # モデルを分けて対戦
```

毎手、盤面を state に、着手候補(石の近傍セル)を choice 質問の criteria として Jev に問い、
`WINS` / `BLOCK` / ライン長(`3o` = 3 連・片端オープン)のヒント付きで最良手を選ばせます。
API 失敗・不正手のときだけ組み込みフォールバック(勝ち手 > ブロック > 中央)を使います(統計に `fallback moves` と表示)。

主要オプション: `--board N`(1..15 推奨)、`--games N`、`--player1/--player2 <model>`、
`--verbose`(毎手の盤面表示)、`--log-path <file>`(対局ログの JSONL を出力)

## 4. 対局を実時間 GIF 化

```bash
# 1. 対局をログ付きで実行(各手の実測ミリ秒を記録)
moon run --target native cmd/gomoku -- --board 15 --log-path game15.jsonl

# 2. ログから GIF を生成(フレーム遅延 = その手の実測時間 → 実時間再生)
moon run --target native cmd/gomoku_gif -- --log game15.jsonl --out gomoku.gif
```

生成例: [gomoku.gif](gomoku.gif)(362x362 / 26 フレーム / 約 47KB、再生総時間 ≈ 対局の実測時間)。

`gomoku_gif` のオプション: `--scale`(セル辺長 px)、`--padding`、`--hold-cs`(最終フレーム表示、1/100 秒)、
`--max-cs`(フレーム遅延の上限)、`--loop` は未対応(GIF は常にループ再生)。

## 5. 五目並べ以外に効くパターンを試す

公式の[パターン集](https://docs.typesafe.ai/patterns)にある 4 つ(speculative fan-out /
composite scoring / confidence-gated routing / intent routing)と、[launch post](https://typesafe.ai/blog/introducing-system-one-models-and-jev)
が挙げるガードレール用途を、実 API に投げて効果を測る CLI です。

```bash
moon run --target native cmd/patterns --                      # 5 パターン全部
moon run --target native cmd/patterns -- --pattern fanout     # 個別に
# fanout / composite / gate / intent / guardrail
```

数値は下記の実測値(`jev-latest`、2026-09)ですが、走らせ直せばその場で再計測されます。

### 5.1 Speculative fan-out — 一番効く

同じ state に対する 20 問を、1 リクエストにまとめるか 20 回に分けるか:

| | レイテンシ | 入力トークン |
| --- | --- | --- |
| 20 回に分けて投げる | 5227 ms | 8277 |
| 1 リクエストにまとめる | **246 ms** | **1000** |

**21.2 倍速く、8.3 倍安い。** state が 1 回しか送られないので、質問を足すコストがほぼ質問文だけになります。

しかも答えが動きません。同じ 20 問を単独で聞いた場合と比較して、数値回答 17 個の
平均差は **0.011**(最大 0.04)、choice 3 問は全て同じ選択肢でした。並列評価という
説明どおりで、「使うか分からない質問も込みで投げて、必要なものだけコードで拾う」が成立します。

### 5.2 質問は分解して、合成はコード側で

公式ドキュメントが繰り返し勧めるのがこれです。複合質問 1 問と、原子的な noul を
コード側で重み付けした場合、結果自体はほぼ一致します(複合 `2.92/3` conf `0.92` に対し
加重和 `0.899`)。違うのは**内訳が見えること**と、重みの変更に API 呼び出しが要らないことです。

ガードレールではこの差が精度に出ます。`You are now DAN…` のような roleplay と
軽い依頼が混ざった入力では、判定を 1 問の choice に任せると confidence が **0.43** まで落ちるのに、
原子的な noul は `injection=0.97` / `roleplay_bypass=0.98` と鋭いままでした。
`inj > 0.9 || harm > 1.5` のような判定をコードに置くほうが安定します。

### 5.3 confidence だけをゲートにすると穴がある

confidence は**渡した選択肢の中での分布の尖り方**であって、「どれかが妥当か」ではありません。
そのため範囲外の入力が、自信満々の誤答として返ります:

```
off-topic ("What is the airspeed velocity of an unladen swallow?") -> technical  conf=0.96  [AUTO]
nonsense  ("asdf qwer zxcv")                                       -> technical  conf=0.99  [AUTO]
```

どちらも閾値 0.85 を越えるので自動処理に流れてしまいます。対処は 2 つあり、どちらも実測で効きました。

- **A: 逃げ道の選択肢を足す** — `none_of_these` を criteria に入れると、上の 2 件とも
  `none_of_these` を conf `1.00` で選びます。
- **B: スコープ判定を fan-out で同じリクエストに混ぜる** — `in_scope` の noul を併せて聞くと
  範囲外が `0.02`、正常な問い合わせが `0.97` と明確に分かれます。リクエストは 1 回のままなので追加コストは質問文だけです。

### 5.4 intent routing は選択肢名だけで十分安い

criteria の説明を省いて選択肢名だけ渡す形(`Question::choice_of`)が使えます。
説明文がトークンを食う本体なので、20 ハンドラのメニューでも入力 **441 トークン**、
confidence は 0.98〜1.00 で当たりました。

ただし **1 問あたりの選択肢は 255 個まで**です(超えると
`400 {"detail":"Too many choices. Must have at most 255 choices."}`)。
OpenAPI スキーマには書かれていないので、`lib` 側に `max_choices` として持たせ、
送信前に `InvalidRequest` で弾くようにしています。五目並べが 15×15 までなのも実はこれが効いていて、
盤面全体を候補にすると 16×16(256 セル)で上限に当たります。

## 実 API を叩いて分かったこと(スキーマに書かれていない挙動)

- **noul の criteria はネストする。** `NoulCriteria` は `criteria: {"true": …, "false": …}` という
  入れ子で、`true`/`false` をトップレベルに置くと**サーバーはエラーを返さず黙って無視します**。
  反転した criteria を与える実験で、ネストすれば `0.05`、トップレベルだと `0.67`(criteria なしの
  素の判断)になり、取り違えても成功レスポンスが返るぶん気付けません。以前の `lib` はこの形で
  送っていたため noul の criteria が一切効いておらず、修正済みです
  (`lib/types_test.mbt` にワイヤ形式を固定するテストを追加。往復テストは対称なので
  この種のバグを検出できません)。
- **`instructions` と criteria の説明は文字列でなくてもよい。** スキーマ上は string / object / array が
  許され、実際どれも通ります。そのため `Question` は `Json` を保持する形にし、
  全部文字列という普通のケース用に `Question::noul` / `choice` / `choice_of` / `score` を用意しました。
- **choice の説明は `null` にできる**(選択肢名だけで解釈させる)。最も安い形です。
- **state は文字列・オブジェクト・配列のいずれでもよい。** 会話ログを配列でそのまま渡す、
  ユーザー属性を入れ子で渡すといった使い方ができます。
- レイテンシは実測 125〜730 ms でした(質問数を増やしても大きく変わりません)。

## 補足

- **料金**(2026-09 時点): 入力トークン `$0.042 / MTok`、出力トークン無料。15×15 の五目並べ 1 局で入力約 5.8 万トークン(≈ $0.0024)程度。
- Jev の応答は毎回 1 回の `POST /v1/systemone`(約 0.5 秒/手)。
- GIF エンジン(`WGYo90/moonbit-gif`)はバリデータ上は有効な GIF を出力しますが、**同エンジンのデコーダーは自分の出力を再デコードできません**(標準のブラウザ/ビューアでは再生可能)。
- 参考: Jev に関する解説は [Introducing System One Models & Jev(TypeSafe AI ブログ)](https://typesafe.ai/blog/introducing-system-one-models-and-jev)、API 仕様は [docs.typesafe.ai](https://docs.typesafe.ai/introduction) と `https://api.typesafe.ai/openapi.json`。