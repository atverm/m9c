# Snake: the grid game served by M9

A game in a browser: you steer the snake with the arrow keys or WASD,
it eats and grows, and the walls and its own body end the game. A full
board wins.

**Qwen produced this program on a prompt by the author** (2026-11-18),
its second M9 game after [paddle](../paddle), using `m9c` 0.28.1. The
agent was instructed with the [Modula-9 report](../../docs/M9-report.md)
and the M9 skills in [`skills/`](../../skills). The game module took two
checker refusals, each fixed from the refusal: a computed CONST
(`Cols * Rows` was not a constant then; since 2026-11-19 a CONST names
the CONSTs before it, and the line reads as the agent first wrote it), and bare enumeration
members in expressions (`Dir.Down`; bare only in CASE arms). The test
and the server compiled first try. The server took one deliberate change
after its first build: the game waits for `start=1` instead of starting
on the first poll, so the snake does not move before the player is
ready.

It is here as it was written, with these changes: the banner on the
page and the links of this README.

It is three small modules and a page, and shows several things in one
screen:

- **`Snake.m9`** is a library: a `DEFINITION` with the grid's constants,
  the `Dir` enumeration, the `State` record and three procedures, and
  the `IMPLEMENTATION` with the rules. It imports `Stats` for the
  seeded random stream, and `Faults` to name the exception that stream
  can raise. The body lies in two fixed arrays, head at index 0; the
  food is the k-th empty cell of one `Stats.UniformI` draw — uniform
  over the empty cells, with no retry loop. Equal seeds play equal
  games. There is not a float in the module.
- **`SnakeTest.m9`** holds the rules with `Check`: 43 exact checks.
  `Check.EqI64s` compares the body against golden arrays; the rest
  assert the reset, a step, a turn and its rejected reversal, an eat,
  a wall death, a self death, the legal tail-follow, and the win. Two
  games from one seed stay identical through turns and steps, so the
  random stream is tested without reimplementing it. Paddle's test
  needs tolerances; this one asserts equality.
- **`SnakeServer.m9`** is the program. The state is one `MONITOR`
  record, and `Tick`, bound to it, is the only procedure that touches
  it, because `HttpServer` answers on several workers. The pace
  quickens with the score, from one cell every 0.16 s to one every
  0.07 s; a browser tab that slept advances at most three cells.
  `GET /tick?dir=N[&start=1]` advances the game and answers the state
  as JSON, the body as arrays (0 up, 1 down, 2 left, 3 right); every
  other path is a file of `web/`. The port and the page's folder are
  arguments: default 8001 and web.

The rules run in the server and the page only draws. So the test covers
the whole game without a browser.

## Run it

    m9c --make -o snaketest SnakeTest.m9 && ./snaketest
    m9c --make -o snakeserver SnakeServer.m9
    ./snakeserver                # http://127.0.0.1:8001, pages from web/
    ./snakeserver 8123 web       # another port, the page's folder named

Open the address and press space to start; steer with the arrow keys or
WASD, and press space to restart. The server listens on 127.0.0.1 only.
Stop it with Ctrl-C.

`runtime/test/snake.sh` is the gate: the test, then the server asked for
`/tick` before and after `start=1`, with a bad direction, and for the
page.
