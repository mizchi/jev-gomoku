///|
/// A small CLI for the TypeSafe AI Jev API: send state plus typed questions
/// and get typed probabilistic answers back. Reads the API key from
/// `TYPESAFEAI_API_KEY` (or `--api-key`).
struct Config {
  api_key : String
  base_url : String
  model : String
  list_models : Bool
  pretty : Bool
  state : String?
  state_file : String?
  questions_file : String?
}

///|
async fn main {
  let cmd = @argparse.Command(
    "jev",
    about="TypeSafe AI Jev client: typed probabilistic decisions for software.",
    flags=[
      @argparse.FlagArg(
        "models",
        long="models",
        about="List available models, then exit.",
      ),
      @argparse.FlagArg(
        "pretty",
        long="pretty",
        about="Pretty-print JSON output.",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "api-key",
        long="api-key",
        about="API key (defaults to TYPESAFEAI_API_KEY).",
      ),
      @argparse.OptionArg(
        "model",
        long="model",
        default_values=["jev-latest"],
        about="Model name or alias.",
      ),
      @argparse.OptionArg(
        "base-url",
        long="base-url",
        about="API base URL (default https://api.typesafe.ai).",
      ),
      @argparse.OptionArg(
        "state",
        long="state",
        about="State text or JSON to evaluate.",
      ),
      @argparse.OptionArg(
        "state-file",
        long="state-file",
        about="Read the state from a file.",
      ),
      @argparse.OptionArg(
        "questions-file",
        long="questions-file",
        about="JSON file containing a {name: question} map.",
      ),
    ],
  )
  let matches = @argparse.parse(cmd) catch {
    msg => raise @lib.ApiError::InvalidResponse("usage: \{msg}")
  }
  let api_key = resolve_api_key(matches)
  if api_key.is_empty() {
    @stdio.stderr.write(
      "jev: no API key; set TYPESAFEAI_API_KEY or pass --api-key\n",
    )
    @sys.exit(1)
    return
  }
  let config : Config = {
    api_key,
    base_url: opt_value(matches, "base-url").unwrap_or(
      "https://api.typesafe.ai",
    ),
    model: opt_value(matches, "model").unwrap_or("jev-latest"),
    list_models: matches.flags.get("models").unwrap_or(false),
    pretty: matches.flags.get("pretty").unwrap_or(false),
    state: opt_value(matches, "state"),
    state_file: opt_value(matches, "state-file"),
    questions_file: opt_value(matches, "questions-file"),
  }
  if config.state is Some(_) && config.state_file is Some(_) {
    @stdio.stderr.write(
      "jev: --state and --state-file are mutually exclusive\n",
    )
    @sys.exit(1)
    return
  }
  run(config) catch {
    @lib.ApiError::Http(code, reason, body) => {
      @stdio.stderr.write("jev: HTTP \{code} \{reason}: \{clamp(body)}\n")
      @sys.exit(1)
    }
    @lib.ApiError::InvalidResponse(msg) => {
      @stdio.stderr.write("jev: \{msg}\n")
      @sys.exit(1)
    }
    _ => {
      @stdio.stderr.write("jev: unexpected error\n")
      @sys.exit(1)
    }
  }
}

///|
fn resolve_api_key(matches : @argparse.Matches) -> String {
  match opt_value(matches, "api-key") {
    Some(k) if !k.is_empty() => k
    _ =>
      match @env.get_env_var("TYPESAFEAI_API_KEY") {
        Some(k) if !k.is_empty() => k
        _ => ""
      }
  }
}

///|
fn opt_value(matches : @argparse.Matches, key : String) -> String? {
  match matches.values.get(key) {
    Some(arr) if arr.length() > 0 => Some(arr[0])
    _ => None
  }
}

///|
async fn run(config : Config) -> Unit {
  let client = if config.base_url == "https://api.typesafe.ai" {
    @lib.Client::new(config.api_key)
  } else {
    @lib.Client::with_base_url(config.api_key, config.base_url)
  }
  if config.list_models {
    let models = client.list_models()
    print_json(Json(models.map(m => m.to_json())), config.pretty)
  } else {
    let state = match config.state {
      Some(text) => parse_state(text)
      None =>
        match config.state_file {
          Some(path) => read_state(path)
          None => demo_state()
        }
    }
    let questions = match config.questions_file {
      Some(path) => read_questions(path)
      None => demo_questions()
    }
    let req : @lib.SystemOneRequest = { state, model: config.model, questions, }
    let resp = client.system_one(req)
    print_json(resp.to_json(), config.pretty)
  }
}

///|
fn parse_state(text : String) -> Json {
  @json.parse(text) catch {
    _ => Json::string(text)
  }
}

///|
async fn read_state(path : String) -> Json {
  let text = @fs.read_file(path).text() catch {
    _ => raise @lib.ApiError::InvalidResponse("cannot read state file: \{path}")
  }
  parse_state(text)
}

///|
async fn read_questions(path : String) -> Map[String, @lib.Question] {
  let text = @fs.read_file(path).text() catch {
    _ =>
      raise @lib.ApiError::InvalidResponse(
        "cannot read questions file: \{path}",
      )
  }
  let json = @json.parse(text) catch {
    _ =>
      raise @lib.ApiError::InvalidResponse(
        "questions file is not valid JSON: \{path}",
      )
  }
  guard json is Json::Object(fields) else {
    raise @lib.ApiError::InvalidResponse(
      "questions file must be a JSON object: \{path}",
    )
  }
  let qs : Map[String, @lib.Question] = Map([])
  for (name, qj) in fields {
    qs[name] = @lib.Question::from_json(qj)
  }
  qs
}

///|
fn demo_state() -> Json {
  Json({
    "message": Json(
      "I was charged twice for my subscription. Please cancel the duplicate charge and refund me.",
    ),
    "subject": Json("Duplicate charge on my account"),
    "customer": Json("Premium subscriber for 3 years"),
  })
}

///|
fn demo_questions() -> Map[String, @lib.Question] {
  let qs : Map[String, @lib.Question] = Map([])
  qs["urgency"] = @lib.Question::Score(Some("How urgent is this request?"), [
    "Can wait a week", "Needs attention this week", "Needs attention today",
  ])
  qs["tone"] = @lib.Question::Choice(Some("What is the customer's tone?"), {
    "frustrated": "Angry or upset",
    "neutral": "Calm and factual",
    "polite": "Friendly and courteous",
  })
  qs["needs_refund"] = @lib.Question::Noul(
    Some("This customer should receive a refund."),
    Some("A billing error harmed the customer"),
    Some("The request does not warrant a refund"),
  )
  qs
}

///|
fn print_json(j : Json, pretty : Bool) -> Unit {
  if pretty {
    println(j.stringify(indent=2))
  } else {
    println(j.stringify())
  }
}

///|
fn clamp(s : String) -> String {
  let limit = 300
  if s.length() <= limit {
    s
  } else {
    s[:limit].to_owned() + "…"
  }
}
