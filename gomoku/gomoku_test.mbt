///|
test "cell name round trip" {
  let cells = [(0, 0), (0, 14), (7, 7), (10, 0), (14, 14)]
  for (r, c) in cells {
    match parse_cell(cell_name(r, c)) {
      Some((pr, pc)) => {
        assert_eq(pr, r)
        assert_eq(pc, c)
      }
      None => fail("parse failed for \{cell_name(r, c)}")
    }
  }
  assert_true(parse_cell("a0") is None)
  assert_true(parse_cell("1a") is None)
  assert_true(parse_cell("") is None)
}

///|
test "win detection" {
  let b = Board::new(15)
  // horizontal five for X
  for c in 3..<8 {
    b.place(7, c, STONE_X)
  }
  assert_true(b.has_won(7, 7, STONE_X))
  assert_false(b.has_won(7, 6, STONE_O))
  assert_true(b.line_of_stone(7, 4, STONE_X) >= 5)

  // vertical five for O (place elsewhere so X's line stays)
  let c = Board::new(15)
  for r in 4..<9 {
    c.place(r, 10, STONE_O)
  }
  assert_true(c.has_won(6, 10, STONE_O))

  // diagonal five
  let d = Board::new(15)
  for i in 0..<5 {
    d.place(3 + i, 6 + i, STONE_X)
  }
  assert_true(d.has_won(5, 8, STONE_X))

  // four is not a win
  let e = Board::new(15)
  for i in 0..<4 {
    e.place(0, 2 + i, STONE_X)
  }
  assert_false(e.has_won(0, 3, STONE_X))
}

///|
test "line info open vs closed" {
  let b = Board::new(15)
  b.place(7, 5, STONE_X)
  b.place(7, 6, STONE_X)
  b.place(7, 7, STONE_X)
  let (run, open) = b.line_info(7, 6, STONE_X)
  assert_eq(run, 3)
  assert_true(open)
  b.place(7, 4, STONE_O)
  let (run2, open2) = b.line_info(7, 6, STONE_X)
  assert_eq(run2, 3)
  assert_false(open2)
}

///|
test "candidates" {
  let b = Board::new(15)
  // empty board -> center on a 15x15 board
  let center = b.candidates()
  assert_eq(center.length(), 1)
  assert_eq(center[0], (7, 7))

  // after a stone: within distance 2, excludes occupied cells
  b.place(7, 7, STONE_X)
  let cands = b.candidates()
  assert_false(cands.contains((7, 7)))
  assert_true(cands.contains((7, 8)))
  assert_false(cands.contains((2, 2)))
  assert_true(cands.contains((9, 9)))

  // a win cell four away horizontally is a candidate (distance 1 from stone)
  let w = Board::new(15)
  for c in 3..<7 {
    w.place(5, c, STONE_X)
  }
  let wc = w.candidates()
  assert_true(wc.contains((5, 7)))
}

///|
test "board basics" {
  let b = Board::new(9)
  assert_eq(b.count_stones(), 0)
  assert_false(b.is_full())
  b.place(4, 4, STONE_O)
  assert_eq(b.stone_at(4, 4), STONE_O)
  assert_eq(b.stone_at(0, 0), EMPTY)
  assert_eq(b.stone_at(-1, 5), EMPTY)
  let r = b.render()
  assert_false(r.contains("X"))
  assert_true(r.contains("O"))
  assert_true(r.contains("a"))
  assert_true(r.contains("9"))
}
