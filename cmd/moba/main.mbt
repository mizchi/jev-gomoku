///|
/// A headless 3v3 MOBA where Jev plays a whole team, under fog of war.
///
/// The shape of the problem is what makes it interesting here. Team vision is
/// shared, so at any tick there is exactly ONE observation per team — and
/// three champions who each need a decision from it. That is the fan-out
/// pattern with nothing contrived about it: one request carries the state once
/// and asks three independent `choice` questions, one per champion, plus a
/// couple of team-level reads. Three champions therefore cost one round trip,
/// which is what keeps the whole team inside a ~2 decisions/second budget.
///
///   moon run --target native cmd/moba -- --a jev --b scripted --games 3
struct Opts {
  api_key : String
  base_url : String
  model : String
  team_a : String
  team_b : String
  games : Int
  max_ticks : Int
  verbose : Bool
}

///|
/// Per-run counters, so the report can say what a game cost.
struct Stats {
  mut requests : Int
  mut input_tokens : Int
  mut decisions : Int
  mut api_ms : Int
  /// Picks that named something outside the legal list. Should stay 0: the
  /// choices ARE the legal moves, so an illegal action is unrepresentable.
  mut illegal : Int
  /// Ticks where the API failed and the scripted fallback was used.
  mut fallback_ticks : Int
}

///|
fn Stats::new() -> Stats {
  {
    requests: 0,
    input_tokens: 0,
    decisions: 0,
    api_ms: 0,
    illegal: 0,
    fallback_ticks: 0,
  }
}

// ------------------------------------------------------------ action naming

///|
/// A short tactical note per action, in the spirit of the gomoku hints: the
/// model should not have to re-derive from the map what the code already
/// knows.
fn describe(g : @game.Game, c : @game.Champ, a : @game.Action) -> String {
  match a {
    @game.Action::Move(n) => {
      let enemy_team = if c.team == @game.TEAM_A {
        @game.TEAM_B
      } else {
        @game.TEAM_A
      }
      let there = g.champs_at(n, enemy_team)
      let seen = g.vision(c.team)
      let tower = match g.structure_at(n) {
        Some(s) => {
          let side = if s.team == c.team { "our" } else { "their" }
          let kind = if s.is_base { "base" } else { "tower" }
          "; \{side} \{kind} here (hp \{s.hp})"
        }
        None => ""
      }
      let danger = if !seen[n] {
        "; NOT VISIBLE - could be walking into anything"
      } else if there.length() > 0 {
        "; \{there.length()} enemy champion(s) standing there"
      } else {
        ""
      }
      let enemy_base = @game.base_of(enemy_team)
      "move to \{@game.node_name(n)} (\{@game.node_lane[n]} lane, \{@game.hops(n, enemy_base)} hops from the enemy base)\{tower}\{danger}"
    }
    @game.Action::AttackChamp(id) => {
      let e = g.champs[id]
      "attack \{e.name} (hp \{e.hp}) here"
    }
    @game.Action::AttackStructure =>
      match g.structure_at(c.node) {
        Some(s) => {
          let kind = if s.is_base { "BASE" } else { "tower" }
          "attack the enemy \{kind} here (hp \{s.hp})"
        }
        None => "attack the structure here"
      }
    @game.Action::Farm =>
      "farm here for +\{@game.camp_gold(c.node)} gold (safe, no progress on objectives)"
    @game.Action::Recall => "teleport home and heal (gives up this position)"
    @game.Action::Hold => "stay put"
  }
}

// -------------------------------------------------------------- jev a team

///|
/// One request decides the whole team's tick.
///
/// `questions` carries one `choice` per living champion over exactly that
/// champion's legal actions, so whatever comes back is a legal move. Two
/// team-level questions ride along for free (the state is already paid for):
/// a `score` for how much danger the team is in — ordered, so it is a score
/// and not a choice, per docs/01 — and a `choice` guessing where the enemies
/// that are NOT visible have gone, which is the fog-of-war read a human
/// makes constantly.
async fn jev_team_actions(
  client : @lib.Client,
  model : String,
  g : @game.Game,
  team : Int,
  mem : @game.Memory,
  stats : Stats,
  verbose : Bool,
) -> Map[Int, @game.Action] {
  let out : Map[Int, @game.Action] = Map([])
  let legal_by_champ : Map[Int, Array[@game.Action]] = Map([])
  let qs : Map[String, @lib.Question] = Map([])
  for c in g.champs {
    if c.team != team || !c.alive() {
      continue
    }
    let legal = g.legal_actions(c)
    if legal.is_empty() {
      continue
    }
    legal_by_champ[c.id] = legal
    let criteria : Map[String, String] = Map([])
    for a in legal {
      criteria[a.to_string()] = describe(g, c, a)
    }
    qs["champ_\{c.id}"] = @lib.Question::choice(
      criteria,
      instructions="What should \{c.name} (the \{c.role} laner, hp \{c.hp}) do this tick? Win the game: take towers and then the base. Do not feed kills, and do not walk alone into places you cannot see.",
    )
  }
  if qs.is_empty() {
    return out
  }
  // Team-level reads, riding along on a state that is already being sent.
  qs["danger"] = @lib.Question::score(
    [
      "Safe, keep pushing", "Trade carefully", "Back off and regroup",
      "Our base is about to fall",
    ],
    instructions="How much danger is our team in right now?",
  )
  let unseen = []
  for i in 0..<@game.N_NODES {
    unseen.push(@game.node_names[i])
  }
  qs["enemy_probably_at"] = @lib.Question::choice_of(
    unseen,
    instructions="The enemies you cannot see right now — which node are they most likely grouped at?",
  )

  let state = g.observation(team, mem)
  let t0 = @env.now()
  let resp = client.system_one({ state, model, questions: qs }) catch {
    _ => {
      // The game must keep moving; fall back to the scripted policy and say so.
      stats.fallback_ticks += 1
      for c in g.champs {
        if c.team == team && c.alive() {
          out[c.id] = @game.scripted_action(g, c)
        }
      }
      return out
    }
  }
  stats.api_ms += (@env.now() - t0).to_int()
  stats.requests += 1
  stats.input_tokens += resp.input_tokens

  for entry in legal_by_champ {
    let (id, legal) = entry
    let (choice, conf) = @report.choice_at(resp, "champ_\{id}")
    let mut picked : @game.Action? = None
    for a in legal {
      if a.to_string() == choice {
        picked = Some(a)
      }
    }
    match picked {
      Some(a) => {
        out[id] = a
        stats.decisions += 1
        if verbose {
          println(
            "    \{g.champs[id].name}: \{a.to_string()} (conf \{@report.d2(conf)})",
          )
        }
      }
      None => {
        // Cannot happen while the criteria are the legal moves; counted so
        // the claim is measured rather than asserted.
        stats.illegal += 1
        out[id] = @game.scripted_action(g, g.champs[id])
      }
    }
  }
  if verbose {
    let (danger, dconf) = @report.score_at(resp, "danger")
    let (guess, gconf) = @report.choice_at(resp, "enemy_probably_at")
    println(
      "    [team read] danger=\{@report.d2(danger)}/3@\{@report.d2(dconf)}  unseen enemies probably at \{guess}@\{@report.d2(gconf)}  (\{resp.input_tokens} tok)",
    )
  }
  out
}

// ------------------------------------------------------------------ one game

///|
struct GameResult {
  winner : Int
  ticks : Int
  a_structure_hp : Int
  b_structure_hp : Int
}

///|
async fn play_game(
  opts : Opts,
  client : @lib.Client,
  stats : Stats,
  index : Int,
) -> GameResult {
  let g = @game.Game::new()
  let mem_a = @game.Memory::new()
  let mem_b = @game.Memory::new()
  if opts.verbose {
    println("")
    println("--- game \{index + 1}: A=\{opts.team_a} vs B=\{opts.team_b} ---")
  }
  while g.winner == 0 && g.tick < opts.max_ticks {
    mem_a.observe(g, @game.TEAM_A)
    mem_b.observe(g, @game.TEAM_B)
    let actions : Map[Int, @game.Action] = Map([])
    for pair in [(@game.TEAM_A, opts.team_a), (@game.TEAM_B, opts.team_b)] {
      let (team, kind) = pair
      let mem = if team == @game.TEAM_A { mem_a } else { mem_b }
      if kind == "jev" {
        if opts.verbose {
          println(
            "  tick \{g.tick + 1} team \{if team == @game.TEAM_A { "A" } else { "B" }}:",
          )
        }
        let chosen = jev_team_actions(
          client, opts.model, g, team, mem, stats, opts.verbose,
        )
        for e in chosen {
          actions[e.0] = e.1
        }
      } else {
        for c in g.champs {
          if c.team == team && c.alive() {
            actions[c.id] = @game.scripted_action(g, c)
          }
        }
      }
    }
    g.step(actions)
    if opts.verbose && g.log.length() > 0 {
      let last = g.log[g.log.length() - 1]
      if last.has_prefix("t\{g.tick}:") {
        println("  \{last}")
      }
    }
  }
  if opts.verbose {
    println(g.render())
  }
  // A game that runs out of ticks goes to whoever did more structural damage.
  let a_hp = g.structure_hp(@game.TEAM_A)
  let b_hp = g.structure_hp(@game.TEAM_B)
  let winner = if g.winner != 0 {
    g.winner
  } else if b_hp < a_hp {
    @game.TEAM_A
  } else if a_hp < b_hp {
    @game.TEAM_B
  } else {
    0
  }
  { winner, ticks: g.tick, a_structure_hp: a_hp, b_structure_hp: b_hp }
}

// ----------------------------------------------------------------- plumbing

///|
async fn main {
  let cmd = @argparse.Command(
    "moba",
    about="A headless 3v3 MOBA with fog of war, played by Jev or a scripted bot.",
    flags=[
      @argparse.FlagArg(
        "verbose",
        long="verbose",
        about="Print every decision and the team-level reads.",
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
        "a",
        long="a",
        default_values=["jev"],
        about="Team A policy: jev or scripted.",
      ),
      @argparse.OptionArg(
        "b",
        long="b",
        default_values=["scripted"],
        about="Team B policy: jev or scripted.",
      ),
      @argparse.OptionArg(
        "games",
        long="games",
        default_values=["1"],
        about="How many games to play.",
      ),
      @argparse.OptionArg(
        "max-ticks",
        long="max-ticks",
        default_values=["60"],
        about="Tick cap; the tie breaks on structure damage.",
      ),
    ],
  )
  let matches = @argparse.parse(cmd) catch {
    msg => raise @lib.ApiError::InvalidResponse("usage: \{msg}")
  }
  let api_key = match opt_value(matches, "api-key") {
    Some(k) if !k.is_empty() => k
    _ =>
      match @env.get_env_var("TYPESAFEAI_API_KEY") {
        Some(k) if !k.is_empty() => k
        _ => ""
      }
  }
  let opts : Opts = {
    api_key,
    base_url: opt_value(matches, "base-url").unwrap_or(
      "https://api.typesafe.ai",
    ),
    model: opt_value(matches, "model").unwrap_or("jev-latest"),
    team_a: opt_value(matches, "a").unwrap_or("jev"),
    team_b: opt_value(matches, "b").unwrap_or("scripted"),
    games: parse_int(opt_value(matches, "games"), 1),
    max_ticks: parse_int(opt_value(matches, "max-ticks"), 60),
    verbose: matches.flags.get("verbose").unwrap_or(false),
  }
  for kind in [opts.team_a, opts.team_b] {
    if kind != "jev" && kind != "scripted" {
      @stdio.stderr.write("moba: team policy must be jev or scripted\n")
      @sys.exit(1)
      return
    }
  }
  let needs_api = opts.team_a == "jev" || opts.team_b == "jev"
  if needs_api && api_key.is_empty() {
    @stdio.stderr.write(
      "moba: no API key; set TYPESAFEAI_API_KEY or pass --api-key\n",
    )
    @sys.exit(1)
    return
  }
  run(opts) catch {
    @lib.ApiError::Http(code, reason, body) => {
      @stdio.stderr.write(
        "moba: HTTP \{code} \{reason}: \{@report.clip(body, 300)}\n",
      )
      @sys.exit(1)
    }
    @lib.ApiError::InvalidResponse(msg) | @lib.ApiError::InvalidRequest(msg) => {
      @stdio.stderr.write("moba: \{msg}\n")
      @sys.exit(1)
    }
    _ => {
      @stdio.stderr.write("moba: unexpected error\n")
      @sys.exit(1)
    }
  }
}

///|
async fn run(opts : Opts) -> Unit {
  let client = if opts.base_url == "https://api.typesafe.ai" {
    @lib.Client::new(opts.api_key)
  } else {
    @lib.Client::with_base_url(opts.api_key, opts.base_url)
  }
  let stats = Stats::new()
  @report.header(
    "3v3 MOBA",
    "A=\{opts.team_a} vs B=\{opts.team_b}, \{opts.games} game(s), fog of war",
  )
  let mut a_wins = 0
  let mut b_wins = 0
  let mut draws = 0
  let mut total_ticks = 0
  let wall0 = @env.now()
  for i in 0..<opts.games {
    let r = play_game(opts, client, stats, i)
    total_ticks += r.ticks
    if r.winner == @game.TEAM_A {
      a_wins += 1
    } else if r.winner == @game.TEAM_B {
      b_wins += 1
    } else {
      draws += 1
    }
    let who = if r.winner == @game.TEAM_A {
      "A (\{opts.team_a})"
    } else if r.winner == @game.TEAM_B {
      "B (\{opts.team_b})"
    } else {
      "draw"
    }
    println(
      "  game \{i + 1}: \{who} after \{r.ticks} ticks   structures left A=\{r.a_structure_hp} B=\{r.b_structure_hp}",
    )
  }
  let wall = (@env.now() - wall0).to_int()
  println("")
  println(
    "  A (\{opts.team_a}) \{a_wins} — \{b_wins} B (\{opts.team_b})\{if draws > 0 { "  (\{draws} draw)" } else { "" }}, \{total_ticks} ticks total",
  )
  if stats.requests > 0 {
    let per_req = stats.api_ms.to_double() / stats.requests.to_double()
    let per_dec = stats.api_ms.to_double() / stats.decisions.to_double()
    println("")
    println(
      "  \{stats.requests} requests decided \{stats.decisions} champion actions",
    )
    println(
      "  \{@report.d0(per_req)} ms/request, \{@report.d0(per_dec)} ms per champion decision",
    )
    println(
      "  \{stats.input_tokens} input tokens (~$\{@report.fixed(stats.input_tokens.to_double() / 1000000.0 * 0.042, 4)}), wall clock \{@report.d1(wall.to_double() / 1000.0)}s",
    )
    println(
      "  illegal picks: \{stats.illegal} (the choices ARE the legal moves)",
    )
    if stats.fallback_ticks > 0 {
      println("  scripted fallback ticks after API failures: \{stats.fallback_ticks}")
    }
  }
  println("")
}

///|
fn opt_value(matches : @argparse.Matches, key : String) -> String? {
  match matches.values.get(key) {
    Some(arr) if arr.length() > 0 => Some(arr[0])
    _ => None
  }
}

///|
fn parse_int(v : String?, fallback : Int) -> Int {
  match v {
    Some(s) => @string.from_str(s) catch { _ => fallback }
    None => fallback
  }
}
