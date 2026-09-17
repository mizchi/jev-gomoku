///|
/// Errors surfaced by the TypeSafe AI client.
pub(all) suberror ApiError {
  /// Non-2xx HTTP response: (status code, reason phrase, response body).
  Http(Int, String, String)
  /// The server answered 2xx but the body was not the expected shape.
  InvalidResponse(String)
} derive(Debug)

///|
/// A typed question to ask about the `state`. Mirrors the three TypeSafe
/// primitives: `Noul` (yes/no), `Choice` (pick one), `Score` (ordered
/// rubric). Constructor fields are positional:
///
/// - `Noul(instructions, true_desc, false_desc)`
/// - `Choice(instructions, choice-name -> description Map)`
/// - `Score(instructions, ordered score levels)`
pub(all) enum Question {
  Noul(String?, String?, String?)
  Choice(String?, Map[String, String])
  Score(String?, Array[String])
}

///|
/// A typed answer, keyed by question name in `SystemOneResponse.answers`.
pub(all) enum Answer {
  NoulAnswer(Double)
  ChoiceAnswer(String, Double, Map[String, Double])
  ScoreAnswer(Double, Double, Map[String, String], Map[String, Double])
}

///|
pub(all) struct SystemOneRequest {
  /// Content all questions refer to: any JSON value (string, object, array).
  state : Json
  /// Model name or alias, e.g. "jev-latest".
  model : String
  /// Named questions; each answer in the response uses the same name.
  questions : Map[String, Question]
}

///|
pub(all) struct SystemOneResponse {
  model : String
  answers : Map[String, Answer]
  input_tokens : Int
  output_tokens : Int
}

///|
pub(all) struct Model {
  name : String
  description : String
  release_date : String
}

///|
fn json_object(json : Json, what : String) -> Map[String, Json] raise {
  guard json is Json::Object(fields) else {
    raise ApiError::InvalidResponse(
      "\{what}: expected JSON object, got \{json.stringify()}",
    )
  }
  let m : Map[String, Json] = Map([])
  for (k, v) in fields {
    m[k] = v
  }
  m
}

///|
fn get_string(
  m : Map[String, Json],
  key : String,
  what : String,
) -> String raise {
  match m.get(key) {
    Some(Json::String(s)) => s
    Some(other) =>
      raise ApiError::InvalidResponse(
        "\{what}.\{key}: expected string, got \{other.stringify()}",
      )
    None => raise ApiError::InvalidResponse("\{what}.\{key}: missing")
  }
}

///|
fn get_string_opt(
  m : Map[String, Json],
  key : String,
  what : String,
) -> String? raise {
  match m.get(key) {
    None | Some(Json::Null) => None
    Some(Json::String(s)) => Some(s)
    Some(other) =>
      raise ApiError::InvalidResponse(
        "\{what}.\{key}: expected string, got \{other.stringify()}",
      )
  }
}

///|
fn get_double(
  m : Map[String, Json],
  key : String,
  what : String,
) -> Double raise {
  match m.get(key) {
    Some(Json::Number(v, ..)) => v
    Some(other) =>
      raise ApiError::InvalidResponse(
        "\{what}.\{key}: expected number, got \{other.stringify()}",
      )
    None => raise ApiError::InvalidResponse("\{what}.\{key}: missing")
  }
}

///|
fn get_string_map(
  m : Map[String, Json],
  key : String,
  what : String,
) -> Map[String, String] raise {
  let inner = match m.get(key) {
    Some(Json::Object(fields)) => fields
    Some(other) =>
      raise ApiError::InvalidResponse(
        "\{what}.\{key}: expected object, got \{other.stringify()}",
      )
    None => raise ApiError::InvalidResponse("\{what}.\{key}: missing")
  }
  let out : Map[String, String] = Map([])
  for (k, v) in inner {
    match v {
      Json::String(s) => out[k] = s
      _ =>
        raise ApiError::InvalidResponse(
          "\{what}.\{key}.\{k}: expected string, got \{v.stringify()}",
        )
    }
  }
  out
}

///|
fn get_double_map(
  m : Map[String, Json],
  key : String,
  what : String,
) -> Map[String, Double] raise {
  let inner = match m.get(key) {
    Some(Json::Object(fields)) => fields
    Some(other) =>
      raise ApiError::InvalidResponse(
        "\{what}.\{key}: expected object, got \{other.stringify()}",
      )
    None => raise ApiError::InvalidResponse("\{what}.\{key}: missing")
  }
  let out : Map[String, Double] = Map([])
  for (k, v) in inner {
    match v {
      Json::Number(n, ..) => out[k] = n
      _ =>
        raise ApiError::InvalidResponse(
          "\{what}.\{key}.\{k}: expected number, got \{v.stringify()}",
        )
    }
  }
  out
}

///|
fn opt_str(v : String?) -> Json {
  match v {
    Some(s) => Json::string(s)
    None => Json::null()
  }
}

///|
pub fn Question::to_json(self : Question) -> Json {
  match self {
    Noul(instructions, true_desc, false_desc) =>
      Json({
        "type": Json("noul"),
        "instructions": opt_str(instructions),
        "true": opt_str(true_desc),
        "false": opt_str(false_desc),
      })
    Choice(instructions, criteria) =>
      Json({
        "type": Json("choice"),
        "instructions": opt_str(instructions),
        "criteria": Json(criteria),
      })
    Score(instructions, criteria) =>
      Json({
        "type": Json("score"),
        "instructions": opt_str(instructions),
        "criteria": Json(criteria.map(s => Json::string(s))),
      })
  }
}

///|
pub fn Question::from_json(json : Json) -> Question raise {
  let m = json_object(json, "question")
  let why = "question"
  match m.get("type") {
    Some(Json::String("noul")) =>
      Noul(
        get_string_opt(m, "instructions", why),
        get_string_opt(m, "true", why),
        get_string_opt(m, "false", why),
      )
    Some(Json::String("choice")) =>
      Choice(
        get_string_opt(m, "instructions", why),
        get_string_map(m, "criteria", why),
      )
    Some(Json::String("score")) =>
      Score(
        get_string_opt(m, "instructions", why),
        match m.get("criteria") {
          Some(Json::Array(items)) =>
            items.map(v => {
              match v {
                Json::String(s) => s
                other =>
                  raise ApiError::InvalidResponse(
                    "question.criteria: expected strings, got \{other.stringify()}",
                  )
              }
            })
          Some(other) =>
            raise ApiError::InvalidResponse(
              "question.criteria: expected array, got \{other.stringify()}",
            )
          None => raise ApiError::InvalidResponse("question.criteria: missing")
        },
      )
    Some(other) =>
      raise ApiError::InvalidResponse(
        "question.type: unknown \{other.stringify()}",
      )
    None => raise ApiError::InvalidResponse("question.type: missing")
  }
}

///|
pub fn Answer::to_json(self : Answer) -> Json {
  match self {
    NoulAnswer(prob) =>
      Json({ "type": Json("noul"), "noul": Json::number(prob) })
    ChoiceAnswer(choice, confidence, probabilities) =>
      Json({
        "type": Json("choice"),
        "choice": Json(choice),
        "confidence": Json::number(confidence),
        "probabilities": Json(probabilities),
      })
    ScoreAnswer(score, confidence, legend, probabilities) =>
      Json({
        "type": Json("score"),
        "score": Json::number(score),
        "confidence": Json::number(confidence),
        "legend": Json(legend),
        "probabilities": Json(probabilities),
      })
  }
}

///|
pub fn Answer::from_json(json : Json) -> Answer raise {
  let m = json_object(json, "answer")
  let why = "answer"
  match m.get("type") {
    Some(Json::String("noul")) => NoulAnswer(get_double(m, "noul", why))
    Some(Json::String("choice")) =>
      ChoiceAnswer(
        get_string(m, "choice", why),
        get_double(m, "confidence", why),
        get_double_map(m, "probabilities", why),
      )
    Some(Json::String("score")) =>
      ScoreAnswer(
        get_double(m, "score", why),
        get_double(m, "confidence", why),
        get_string_map(m, "legend", why),
        get_double_map(m, "probabilities", why),
      )
    Some(other) =>
      raise ApiError::InvalidResponse(
        "answer.type: unknown \{other.stringify()}",
      )
    None => raise ApiError::InvalidResponse("answer.type: missing")
  }
}

///|
pub fn SystemOneRequest::to_json(self : SystemOneRequest) -> Json {
  let qs : Map[String, Json] = Map([])
  for (name, q) in self.questions.to_array() {
    qs[name] = q.to_json()
  }
  Json({ "model": Json(self.model), "state": self.state, "questions": Json(qs) })
}

///|
pub fn SystemOneResponse::from_json(json : Json) -> SystemOneResponse raise {
  let m = json_object(json, "response")
  let usage = match m.get("usage") {
    Some(obj) => json_object(obj, "response.usage")
    None => raise ApiError::InvalidResponse("response.usage: missing")
  }
  let answers = match m.get("answers") {
    Some(Json::Object(fields)) => fields
    Some(other) =>
      raise ApiError::InvalidResponse(
        "response.answers: expected object, got \{other.stringify()}",
      )
    None => raise ApiError::InvalidResponse("response.answers: missing")
  }
  let parsed : Map[String, Answer] = Map([])
  for (name, a) in answers {
    parsed[name] = Answer::from_json(a)
  }
  {
    model: get_string(m, "model", "response"),
    answers: parsed,
    input_tokens: match usage.get("input_tokens") {
      Some(Json::Number(n, ..)) => n.to_int()
      _ =>
        raise ApiError::InvalidResponse(
          "response.usage.input_tokens: expected integer",
        )
    },
    output_tokens: match usage.get("output_tokens") {
      Some(Json::Number(n, ..)) => n.to_int()
      _ =>
        raise ApiError::InvalidResponse(
          "response.usage.output_tokens: expected integer",
        )
    },
  }
}

///|
pub fn SystemOneResponse::to_json(self : SystemOneResponse) -> Json {
  let ans : Map[String, Json] = Map([])
  for (name, a) in self.answers.to_array() {
    ans[name] = a.to_json()
  }
  Json({
    "model": Json(self.model),
    "answers": Json(ans),
    "usage": Json({
      "input_tokens": Json::number(
        self.input_tokens.to_double(),
        repr="\{self.input_tokens}",
      ),
      "output_tokens": Json::number(
        self.output_tokens.to_double(),
        repr="\{self.output_tokens}",
      ),
    }),
  })
}

///|
pub fn Model::from_json(json : Json) -> Model raise {
  let m = json_object(json, "model")
  {
    name: get_string(m, "name", "model"),
    description: get_string(m, "description", "model"),
    release_date: get_string(m, "release_date", "model"),
  }
}

///|
pub fn Model::to_json(self : Model) -> Json {
  Json({
    "name": Json(self.name),
    "description": Json(self.description),
    "release_date": Json(self.release_date),
  })
}
