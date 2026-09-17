///|
test "question json round trip" {
  let qs = [
    Question::Noul(
      Some("Is this message spam?"),
      Some("Unsolicited advertising"),
      Some("A legitimate conversation"),
    ),
    Question::Choice(Some("What is the tone?"), {
      "angry": "An upset or hostile message",
      "calm": "A neutral or polite message",
    }),
    Question::Score(Some("How urgent is this?"), [
      "Can wait", "This week", "Today",
    ]),
  ]
  for q in qs {
    let back = Question::from_json(q.to_json())
    assert_eq(back.to_json().stringify(), q.to_json().stringify())
  }
}

///|
test "answer json round trip" {
  let ans = [
    Answer::NoulAnswer(0.98),
    Answer::ChoiceAnswer("angry", 0.92, {
      "angry": 0.8,
      "calm": 0.1,
      "excited": 0.1,
    }),
    Answer::ScoreAnswer(
      1.7,
      0.68,
      { "0": "Can wait", "1": "This week", "2": "Today" },
      { "0": 0.1, "1": 0.1, "2": 0.8 },
    ),
  ]
  for a in ans {
    let back = Answer::from_json(a.to_json())
    assert_eq(back.to_json().stringify(), a.to_json().stringify())
  }
}

///|
test "parse full response" {
  let sample =
    #|{
    #|  "model": "jev-latest",
    #|  "answers": {
    #|    "tone": {
    #|      "type": "choice",
    #|      "choice": "frustrated",
    #|      "confidence": 0.82,
    #|      "probabilities": {"frustrated": 0.8, "neutral": 0.15, "polite": 0.05}
    #|    },
    #|    "needs_refund": {"type": "noul", "noul": 0.95},
    #|    "urgency": {
    #|      "type": "score",
    #|      "score": 1.7,
    #|      "confidence": 0.7,
    #|      "legend": {"0": "Can wait", "1": "This week", "2": "Today"},
    #|      "probabilities": {"0": 0.1, "1": 0.1, "2": 0.8}
    #|    }
    #|  },
    #|  "usage": {"input_tokens": 412, "output_tokens": 9}
    #|}
  let resp = SystemOneResponse::from_json(@json.parse(sample))
  assert_eq(resp.model, "jev-latest")
  assert_eq(resp.input_tokens, 412)
  assert_eq(resp.output_tokens, 9)
  assert_eq(resp.answers.length(), 3)
  match resp.answers.get("needs_refund") {
    Some(Answer::NoulAnswer(prob)) => assert_true(prob > 0.9)
    _ => fail("needs_refund should be a noul answer")
  }
  match resp.answers.get("tone") {
    Some(Answer::ChoiceAnswer(choice, _, _)) => assert_eq(choice, "frustrated")
    _ => fail("tone should be a choice answer")
  }
}

///|
test "request json shape" {
  let req : SystemOneRequest = {
    state: Json("I was charged twice. Please help."),
    model: "jev-latest",
    questions: { "billing": Question::Noul(None, None, None) },
  }
  let j = req.to_json().stringify()
  assert_true(j.contains("\"model\":\"jev-latest\""))
  assert_true(j.contains("\"type\":\"noul\""))
}
