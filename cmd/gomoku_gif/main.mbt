///|
/// Turn a cmd/gomoku JSONL move log into a real-time animated GIF: each frame
/// shows the board after a move and stays on screen for the wall-clock time
/// that move's Jev decision actually took (GIF delay units are 10 ms).
struct Options {
  log : String
  out : String
  scale : Int
  padding : Int
  hold_cs : Int
  max_cs : Int
}

///|
struct MoveRecord {
  cell : String
  elapsed_ms : Int
}

///|
async fn main {
  let matches = @argparse.parse(
    @argparse.Command(
      "gomoku-gif",
      about="Render a Gomoku move log as a real-time animated GIF.",
      options=[
        @argparse.OptionArg(
          "log",
          long="log",
          required=true,
          about="Path to the JSONL move log.",
        ),
        @argparse.OptionArg(
          "out",
          long="out",
          default_values=["gomoku.gif"],
          about="Output GIF path.",
        ),
        @argparse.OptionArg(
          "scale",
          long="scale",
          default_values=["20"],
          about="Pixels per board cell.",
        ),
        @argparse.OptionArg(
          "padding",
          long="padding",
          default_values=["16"],
          about="Border padding in pixels.",
        ),
        @argparse.OptionArg(
          "hold-cs",
          long="hold-cs",
          default_values=["80"],
          about="Final frame hold, in centiseconds.",
        ),
        @argparse.OptionArg(
          "max-cs",
          long="max-cs",
          default_values=["500"],
          about="Cap per-frame delay, in centiseconds.",
        ),
      ],
    ),
  )
  let opts : Options = {
    log: opt_value(matches, "log").unwrap_or(""),
    out: opt_value(matches, "out").unwrap_or("gomoku.gif"),
    scale: int_option(matches, "scale", 20).max(4),
    padding: int_option(matches, "padding", 16).max(0),
    hold_cs: int_option(matches, "hold-cs", 80).max(1),
    max_cs: int_option(matches, "max-cs", 500).max(1),
  }
  if opts.log.is_empty() {
    @stdio.stderr.write("gomoku-gif: --log is required\n")
    @sys.exit(2)
    return
  }
  build_gif(opts) catch {
    e => {
      @stdio.stderr.write("gomoku-gif: error: \{e}\n")
      @sys.exit(1)
    }
  }
}

///|
async fn build_gif(opts : Options) -> Unit {
  let text = @fs.read_file(opts.log).text()
  let (board_size, moves, total_ms, winner) = parse_log(text)
  if board_size <= 0 {
    raise @gif.GifError::InvalidDimensions
  }
  let frame_w = opts.padding * 2 + board_size * opts.scale
  let anim = @gif.Animation::new(width=frame_w, height=frame_w)
  let board = @gomoku.Board::new(board_size)
  let mut stone = @gomoku.STONE_X
  // Frame 0: the empty board, held for the first move's decision time.
  let first_delay = if moves.length() > 0 {
    ms_to_cs(moves[0].elapsed_ms).min(opts.max_cs)
  } else {
    opts.hold_cs
  }
  anim.add_frame(make_frame(board, opts, None, first_delay)) |> ignore
  for i in 0..<moves.length() {
    let mv = moves[i]
    let (r, c) = match @gomoku.parse_cell(mv.cell) {
      Some(x) => x
      None => raise @gif.GifError::InvalidBlock(context="bad cell \{mv.cell}")
    }
    if stone == @gomoku.STONE_X {
      board.place(r, c, @gomoku.STONE_X)
    } else {
      board.place(r, c, @gomoku.STONE_O)
    }
    // The frame showing the position AFTER move i stays for move i+1's
    // decision time; the last displayed frame holds for --hold-cs.
    let delay_cs = if i + 1 < moves.length() {
      ms_to_cs(moves[i + 1].elapsed_ms).min(opts.max_cs)
    } else {
      opts.hold_cs
    }
    anim.add_frame(make_frame(board, opts, Some((r, c)), delay_cs)) |> ignore
    stone = if stone == @gomoku.STONE_X {
      @gomoku.STONE_O
    } else {
      @gomoku.STONE_X
    }
  }
  let bytes = @gif.encode(anim)
  @fs.write_file(opts.out, bytes)
  let secs = total_ms / 1000
  println(
    "wrote \{opts.out}: \{board_size}x\{board_size}, \{moves.length()} moves, \{anim.frame_count()} frames, \{bytes.length()} bytes; game took \{secs / 60}m\{secs % 60}s (\{total_ms} ms), winner \{winner}",
  )
  match @gif.explain_gif_error(bytes) {
    "valid GIF stream" => {
      println("validator: valid GIF stream")
      match @gif.decode_checked(bytes) {
        None =>
          println(
            "note: this engine's decoder can't re-open its own output (engine quirk); standard GIF viewers should play it",
          )
        Some(a) => println("decoder round-trip: \{a.frame_count()} frames")
      }
    }
    msg => println("warning: validation failed: \{msg}")
  }
}

///|
fn ms_to_cs(ms : Int) -> Int {
  if ms / 10 < 1 {
    1
  } else {
    ms / 10
  }
}

///|
fn make_frame(
  board : @gomoku.Board,
  opts : Options,
  last : (Int, Int)?,
  delay_cs : Int,
) -> @gif.Frame {
  let size = board.size
  let fw = opts.padding * 2 + size * opts.scale
  let canvas = @gif.Canvas::new(
    width=fw,
    height=fw,
    fill=@gif.rgb(0x15, 0x15, 0x1c),
  )
  for r in 0..<size {
    for c in 0..<size {
      let x0 = opts.padding + c * opts.scale
      let y0 = opts.padding + r * opts.scale
      let fill = match board.stone_at(r, c) {
        1 => @gif.rgb(0xe8, 0x4a, 0x3d)
        2 => @gif.rgb(0x4d, 0x9b, 0xff)
        _ => @gif.rgb(0x28, 0x28, 0x33)
      }
      fill_rect(canvas, x0, y0, opts.scale, fill)
    }
  }
  if last is Some((lr, lc)) {
    let x0 = opts.padding + lc * opts.scale
    let y0 = opts.padding + lr * opts.scale
    let ring = @gif.rgb(0xf4, 0xee, 0xca)
    for i in 0..<opts.scale {
      canvas.set(x=x0 + i, y=y0, color=ring) |> ignore
      canvas.set(x=x0 + i, y=y0 + opts.scale - 1, color=ring) |> ignore
      canvas.set(x=x0, y=y0 + i, color=ring) |> ignore
      canvas.set(x=x0 + opts.scale - 1, y=y0 + i, color=ring) |> ignore
    }
  }
  @gif.Frame::new(canvas~, delay_cs~)
}

///|
fn fill_rect(
  canvas : @gif.Canvas,
  x0 : Int,
  y0 : Int,
  size : Int,
  color : @gif.Rgba,
) -> Unit {
  for dy in 0..<size {
    for dx in 0..<size {
      canvas.set(x=x0 + dx, y=y0 + dy, color~) |> ignore
    }
  }
}

///|
fn parse_log(text : String) -> (Int, Array[MoveRecord], Int, String) {
  let mut board_size = 0
  let moves : Array[MoveRecord] = []
  let mut total_ms = 0
  let mut winner = "?"
  for line in text.split("\n") {
    if line.is_blank() {
      continue
    }
    let json = @json.parse(line) catch { _ => continue }
    let m = object_fields(json)
    match m.get("type") {
      Some(Json::String("game")) =>
        match m.get("board_size") {
          Some(Json::Number(n, ..)) => board_size = n.to_int()
          _ => ()
        }
      Some(Json::String("move")) => {
        let cell = match m.get("cell") {
          Some(Json::String(s)) => s
          _ => ""
        }
        let elapsed = match m.get("elapsed_ms") {
          Some(Json::Number(n, ..)) => n.to_int()
          _ => 100
        }
        moves.push({ cell, elapsed_ms: elapsed, })
      }
      Some(Json::String("result")) => {
        match m.get("total_ms") {
          Some(Json::Number(n, ..)) => total_ms = n.to_int()
          _ => ()
        }
        match m.get("winner") {
          Some(Json::String(s)) => winner = s
          _ => ()
        }
      }
      _ => ()
    }
  }
  (board_size, moves, total_ms, winner)
}

///|
fn object_fields(json : Json) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([])
  match json {
    Json::Object(entries) =>
      for (k, v) in entries {
        fields[k] = v
      }
    _ => ()
  }
  fields
}

///|
fn opt_value(matches : @argparse.Matches, key : String) -> String? {
  match matches.values.get(key) {
    Some(arr) if arr.length() > 0 => Some(arr[0])
    _ => None
  }
}

///|
fn int_option(matches : @argparse.Matches, key : String, dflt : Int) -> Int {
  match opt_value(matches, key) {
    Some(t) => @string.from_str(t) catch { _ => dflt }
    None => dflt
  }
}
