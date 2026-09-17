///|
/// Game state, vision, and one tick of resolution.
///
/// Everything is deterministic given the action list: the point of the
/// experiment is to compare policies, and a stochastic sim would need far more
/// games to say anything. Damage is flat, so a 2-on-1 always wins.

///|
pub const TEAM_A = 1

///|
pub const TEAM_B = 2

///|
/// What a champion can be told to do in a tick. `Move` is to an adjacent node
/// only; the rest act on whatever is in the champion's current node.
pub(all) enum Action {
  /// Walk to an adjacent node.
  Move(Int)
  /// Hit an enemy champion standing here, by champion id.
  AttackChamp(Int)
  /// Hit the enemy tower or base standing here.
  AttackStructure
  /// Take gold from the minions or camp here.
  Farm
  /// Teleport home and start healing. Costs the tick.
  Recall
  /// Do nothing.
  Hold
} derive(Eq)

///|
pub fn Action::to_string(self : Action) -> String {
  match self {
    Move(n) => "move_\{node_name(n)}"
    AttackChamp(id) => "attack_champ_\{id}"
    AttackStructure => "attack_structure"
    Farm => "farm"
    Recall => "recall"
    Hold => "hold"
  }
}

///|
pub struct Champ {
  id : Int
  name : String
  team : Int
  /// Lane this champion starts in; the scripted bot stays loyal to it.
  role : String
  mut hp : Int
  max_hp : Int
  mut node : Int
  mut gold : Int
  /// Ticks until respawn. 0 when alive.
  mut respawn : Int
  mut kills : Int
  mut deaths : Int
}

///|
pub fn Champ::alive(self : Champ) -> Bool {
  self.respawn == 0
}

///|
/// A tower, or a base when `is_base`. Towers must fall before the base behind
/// them can be attacked.
pub struct Structure {
  node : Int
  team : Int
  mut hp : Int
  max_hp : Int
  is_base : Bool
}

///|
pub fn Structure::alive(self : Structure) -> Bool {
  self.hp > 0
}

///|
pub struct Game {
  champs : Array[Champ]
  structures : Array[Structure]
  mut tick : Int
  /// 0 while the game is running, otherwise the winning team.
  mut winner : Int
  /// One line per tick, for the report.
  log : Array[String]
}

///|
/// Damage a champion deals to a champion or structure in one tick, before the
/// gold bonus.
const CHAMP_DAMAGE = 10

///|
/// Damage a tower deals to each enemy champion standing on it. Deliberately
/// below a champion's output but high enough that soloing a tower costs most
/// of a health bar: two champions take it comfortably, one barely, which is
/// what makes grouping a real decision rather than a flavour note.
const TOWER_DAMAGE = 8

///|
const HEAL_AT_BASE = 25

///|
const RESPAWN_TICKS = 6

///|
/// Gold buys damage: every 100 gold is one more damage per hit. It gives
/// farming a reason to exist without needing items.
fn champ_damage(c : Champ) -> Int {
  CHAMP_DAMAGE + c.gold / 100
}

///|
pub fn Game::new() -> Game {
  let champs = []
  let roles = ["top", "jungle", "bot"]
  let a_start = [1, 8, 5]
  let b_start = [3, 10, 7]
  for i in 0..<3 {
    champs.push({
      id: i,
      name: "A_\{roles[i]}",
      team: TEAM_A,
      role: roles[i],
      hp: 100,
      max_hp: 100,
      node: a_start[i],
      gold: 0,
      respawn: 0,
      kills: 0,
      deaths: 0,
    })
  }
  for i in 0..<3 {
    champs.push({
      id: 3 + i,
      name: "B_\{roles[i]}",
      team: TEAM_B,
      role: roles[i],
      hp: 100,
      max_hp: 100,
      node: b_start[i],
      gold: 0,
      respawn: 0,
      kills: 0,
      deaths: 0,
    })
  }
  let structures = [
    { node: 1, team: TEAM_A, hp: 100, max_hp: 100, is_base: false },
    { node: 5, team: TEAM_A, hp: 100, max_hp: 100, is_base: false },
    { node: A_BASE, team: TEAM_A, hp: 150, max_hp: 150, is_base: true },
    { node: 3, team: TEAM_B, hp: 100, max_hp: 100, is_base: false },
    { node: 7, team: TEAM_B, hp: 100, max_hp: 100, is_base: false },
    { node: B_BASE, team: TEAM_B, hp: 150, max_hp: 150, is_base: true },
  ]
  { champs, structures, tick: 0, winner: 0, log: [] }
}

///|
pub fn base_of(team : Int) -> Int {
  if team == TEAM_A {
    A_BASE
  } else {
    B_BASE
  }
}

///|
pub fn Game::structure_at(self : Game, node : Int) -> Structure? {
  for s in self.structures {
    if s.node == node && s.alive() {
      return Some(s)
    }
  }
  None
}

///|
/// A team's base can only be attacked once both its towers are down. Without
/// this the jungle route would win every game on turn four.
pub fn Game::base_exposed(self : Game, team : Int) -> Bool {
  for s in self.structures {
    if s.team == team && !s.is_base && s.alive() {
      return false
    }
  }
  true
}

///|
pub fn Game::champs_at(self : Game, node : Int, team : Int) -> Array[Champ] {
  let out = []
  for c in self.champs {
    if c.team == team && c.alive() && c.node == node {
      out.push(c)
    }
  }
  out
}

// --------------------------------------------------------------- fog of war

///|
/// Which nodes a team can see: where its living champions stand, everything
/// adjacent to them, and the nodes its surviving structures sit on. This is
/// the only channel through which a policy learns about the enemy.
pub fn Game::vision(self : Game, team : Int) -> Array[Bool] {
  let seen = Array::make(N_NODES, false)
  for c in self.champs {
    if c.team == team && c.alive() {
      seen[c.node] = true
      for n in adjacency[c.node] {
        seen[n] = true
      }
    }
  }
  for s in self.structures {
    if s.team == team && s.alive() {
      seen[s.node] = true
    }
  }
  seen
}

///|
/// The enemy champions a team can currently see.
pub fn Game::visible_enemies(self : Game, team : Int) -> Array[Champ] {
  let seen = self.vision(team)
  let out = []
  for c in self.champs {
    if c.team != team && c.alive() && seen[c.node] {
      out.push(c)
    }
  }
  out
}

// ------------------------------------------------------------- legal actions

///|
/// Everything a champion may do this tick. A policy picks from exactly this
/// list, so an illegal move is impossible by construction — the model cannot
/// hallucinate a move the way it could with free-form text.
pub fn Game::legal_actions(self : Game, c : Champ) -> Array[Action] {
  if !c.alive() {
    return []
  }
  let out : Array[Action] = []
  for n in adjacency[c.node] {
    out.push(Move(n))
  }
  for e in self.visible_enemies(c.team) {
    if e.node == c.node {
      out.push(AttackChamp(e.id))
    }
  }
  match self.structure_at(c.node) {
    Some(s) =>
      if s.team != c.team && (!s.is_base || self.base_exposed(s.team)) {
        out.push(AttackStructure)
      }
    None => ()
  }
  if camp_gold(c.node) > 0 {
    out.push(Farm)
  }
  if c.node != base_of(c.team) {
    out.push(Recall)
  }
  out.push(Hold)
  out
}

// ------------------------------------------------------------------ one tick

///|
/// Apply one action per living champion, then resolve. `actions` is indexed by
/// champion id; an id with no entry holds.
pub fn Game::step(self : Game, actions : Map[Int, Action]) -> Unit {
  if self.winner != 0 {
    return
  }
  self.tick += 1
  let events = []

  // Movement and recalls first, so combat happens where champions end up.
  for c in self.champs {
    if !c.alive() {
      continue
    }
    match actions.get(c.id) {
      Some(Move(n)) =>
        if adjacency[c.node].contains(n) {
          c.node = n
        }
      Some(Recall) => {
        c.node = base_of(c.team)
        events.push("\{c.name} recalled")
      }
      _ => ()
    }
  }

  // Then the actions that need a target in the resolved position.
  for c in self.champs {
    if !c.alive() {
      continue
    }
    match actions.get(c.id) {
      Some(AttackChamp(target_id)) => {
        let target = self.champs[target_id]
        if target.team != c.team && target.alive() && target.node == c.node {
          target.hp -= champ_damage(c)
          if target.hp <= 0 {
            c.kills += 1
            c.gold += 150
            target.deaths += 1
            target.respawn = RESPAWN_TICKS
            target.hp = 0
            events.push("\{c.name} killed \{target.name} at \{node_name(c.node)}")
          }
        }
      }
      Some(AttackStructure) =>
        match self.structure_at(c.node) {
          Some(s) =>
            if s.team != c.team && (!s.is_base || self.base_exposed(s.team)) {
              s.hp -= champ_damage(c)
              if s.hp <= 0 {
                s.hp = 0
                c.gold += 100
                let what = if s.is_base { "BASE" } else { "tower" }
                events.push("\{c.name} destroyed the \{what} at \{node_name(s.node)}")
              }
            }
          None => ()
        }
      Some(Farm) => c.gold += camp_gold(c.node)
      _ => ()
    }
  }

  // Towers punish anyone standing on them.
  for s in self.structures {
    if !s.alive() {
      continue
    }
    let enemy = if s.team == TEAM_A { TEAM_B } else { TEAM_A }
    for c in self.champs_at(s.node, enemy) {
      c.hp -= TOWER_DAMAGE
      if c.hp <= 0 {
        c.hp = 0
        c.deaths += 1
        c.respawn = RESPAWN_TICKS
        events.push("\{c.name} was killed by the tower at \{node_name(s.node)}")
      }
    }
  }

  // Healing at home, and respawns.
  for c in self.champs {
    if c.alive() {
      if c.node == base_of(c.team) && c.hp < c.max_hp {
        c.hp = @cmp.minimum(c.max_hp, c.hp + HEAL_AT_BASE)
      }
    } else {
      c.respawn -= 1
      if c.respawn == 0 {
        c.hp = c.max_hp
        c.node = base_of(c.team)
      }
    }
  }

  for s in self.structures {
    if s.is_base && !s.alive() {
      self.winner = if s.team == TEAM_A { TEAM_B } else { TEAM_A }
    }
  }
  if events.length() > 0 {
    self.log.push("t\{self.tick}: " + events.join("; "))
  }
}

///|
/// Total structure health left, used to decide a game that hits the tick cap.
pub fn Game::structure_hp(self : Game, team : Int) -> Int {
  let mut total = 0
  for s in self.structures {
    if s.team == team {
      total += s.hp
    }
  }
  total
}

///|
/// A one-screen view of the game, for `--verbose`.
pub fn Game::render(self : Game) -> String {
  let lines = []
  lines.push("tick \{self.tick}")
  for c in self.champs {
    let where_ = if c.alive() {
      node_name(c.node)
    } else {
      "dead(\{c.respawn})"
    }
    lines.push(
      "  \{c.name} hp=\{c.hp}/\{c.max_hp} at \{where_} gold=\{c.gold} k/d=\{c.kills}/\{c.deaths}",
    )
  }
  let structs = []
  for s in self.structures {
    let tag = if s.is_base { "base" } else { "tower" }
    structs.push("\{node_name(s.node)}:\{tag}=\{s.hp}")
  }
  lines.push("  " + structs.join(" "))
  lines.join("\n")
}
