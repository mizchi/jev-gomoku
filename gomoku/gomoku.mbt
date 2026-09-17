///|
/// Pure Gomoku (five-in-a-row) game logic: board, moves, win detection,
/// candidate generation, coordinates, and rendering. No IO, no API.
pub(all) struct Board {
  size : Int
  grid : Array[Array[Int]]
}

///|
pub const EMPTY : Int = 0

///|
pub const STONE_X : Int = 1

///|
pub const STONE_O : Int = 2

///|
pub fn Board::new(size : Int) -> Board {
  let rows : Array[Array[Int]] = Array::make(size, [])
  for i in 0..<size {
    rows[i] = Array::make(size, 0)
  }
  { size, grid: rows, }
}

///|
pub fn Board::in_bounds(self : Board, r : Int, c : Int) -> Bool {
  r >= 0 && r < self.size && c >= 0 && c < self.size
}

///|
pub fn Board::stone_at(self : Board, r : Int, c : Int) -> Int {
  if self.in_bounds(r, c) {
    self.grid[r][c]
  } else {
    0
  }
}

///|
pub fn Board::place(self : Board, r : Int, c : Int, stone : Int) -> Unit {
  self.grid[r][c] = stone
}

///|
pub fn Board::count_stones(self : Board) -> Int {
  let mut n = 0
  for r in 0..<self.size {
    for c in 0..<self.size {
      if self.grid[r][c] != 0 {
        n += 1
      }
    }
  }
  n
}

///|
pub fn Board::is_full(self : Board) -> Bool {
  self.count_stones() == self.size * self.size
}

///|
/// Longest run of `stone` through the cell (row, col), counting the cell
/// itself as if it held `stone`. Used to decide where playing wins/blocks.
pub fn Board::line_of_stone(
  self : Board,
  row : Int,
  col : Int,
  stone : Int,
) -> Int {
  let (run, _) = self.line_info(row, col, stone)
  run
}

///|
/// `(run, open)` for the longest line of `stone` through (row, col): `run`
/// counts the cell itself, `open` is true when both ends of that line are
/// empty on the board.
pub fn Board::line_info(
  self : Board,
  row : Int,
  col : Int,
  stone : Int,
) -> (Int, Bool) {
  let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
  let mut best_run = 1
  let mut best_open = false
  for (dr, dc) in dirs {
    let mut run = 1
    let mut lr = row + dr
    let mut lc = col + dc
    while self.in_bounds(lr, lc) && self.grid[lr][lc] == stone {
      run += 1
      lr += dr
      lc += dc
    }
    let mut rr = row - dr
    let mut rc = col - dc
    while self.in_bounds(rr, rc) && self.grid[rr][rc] == stone {
      run += 1
      rr -= dr
      rc -= dc
    }
    let open = self.in_bounds(lr, lc) &&
      self.in_bounds(rr, rc) &&
      self.grid[lr][lc] == 0 &&
      self.grid[rr][rc] == 0
    if run > best_run || (run == best_run && open && !best_open) {
      best_run = run
      best_open = open
    }
  }
  (best_run, best_open)
}

///|
/// True when placing `stone` at (row, col) completes five in a row.
pub fn Board::has_won(self : Board, row : Int, col : Int, stone : Int) -> Bool {
  self.line_of_stone(row, col, stone) >= 5
}

///|
/// Candidate moves, row-major: empty cells within Chebyshev distance 2 of any
/// stone (immediate win/block cells are always within distance 1). An empty
/// board yields the center cell.
pub fn Board::candidates(self : Board) -> Array[(Int, Int)] {
  if self.count_stones() == 0 {
    let mid = self.size / 2
    return [(mid, mid)]
  }
  let near : Array[Array[Bool]] = Array::make(self.size, [])
  for i in 0..<self.size {
    near[i] = Array::make(self.size, false)
  }
  for r in 0..<self.size {
    for c in 0..<self.size {
      if self.grid[r][c] != 0 {
        for dr in -2..<=2 {
          for dc in -2..<=2 {
            let nr = r + dr
            let nc = c + dc
            if self.in_bounds(nr, nc) && self.grid[nr][nc] == 0 {
              near[nr][nc] = true
            }
          }
        }
      }
    }
  }
  let out : Array[(Int, Int)] = []
  for r in 0..<self.size {
    for c in 0..<self.size {
      if near[r][c] {
        out.push((r, c))
      }
    }
  }
  out
}

///|
/// Cell name "c8": column letter (a..) then row number (1..).
pub fn cell_name(r : Int, c : Int) -> String {
  "\{col_label(c)}\{r + 1}"
}

///|
pub fn parse_cell(name : String) -> (Int, Int)? {
  guard name.length() >= 2 else { return None }
  let letter = name[0]
  if letter < 'a' || letter > 'z' {
    return None
  }
  let col = (letter - 'a').to_int()
  let row_text = name[1:]
  let n : Int = @string.from_str(row_text) catch { _ => return None }
  if n < 1 {
    return None
  }
  Some((n - 1, col))
}

///|
fn col_label(c : Int) -> String {
  "\{Int::unsafe_to_char(97 + c)}"
}

///|
/// ASCII rendering of the board with coordinate headers.
pub fn Board::render(self : Board) -> String {
  let sb = StringBuilder()
  sb.write_string("    ")
  for c in 0..<self.size {
    sb.write_string(" \{col_label(c)}")
  }
  for r in 0..<self.size {
    sb.write_string("\n")
    if r + 1 < 10 {
      sb.write_string(" \{r + 1} ")
    } else {
      sb.write_string("\{r + 1} ")
    }
    for c in 0..<self.size {
      match self.grid[r][c] {
        1 => sb.write_string(" X")
        2 => sb.write_string(" O")
        _ => sb.write_string(" .")
      }
    }
  }
  sb.to_string()
}
