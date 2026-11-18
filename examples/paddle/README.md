# Paddle: a bat-and-ball game served by M9

A game against the computer in a browser: you move the left paddle with
the mouse, the program moves the right one.

**Qwen produced this program on a prompt by the author** (2026-11-18),
in its first session with M9, using `m9c` 0.28.0. The agent was
instructed with the [Modula-9 report](../../docs/M9-report.md) and the
M9 skills in [`skills/`](../../skills), and the game, `Paddle.m9` with
its test, compiled and ran without error in its first version. The
server needed one change, kept as a comment in `PaddleServer.m9`: the
file route was added before `/tick` and answered it with 404.

It is here as it was written, with these changes: the name, the port and
the page's folder as arguments, the comments, and the banner on the
page.

It is three small files, and shows several things in one screen:

- **`Paddle.m9`** is a library: a `DEFINITION` with the court's constants,
  the `State` record and two procedures, and the `IMPLEMENTATION` with the
  rules. It imports nothing.
- **`PaddleTest.m9`** holds the rules with `Check`: the serve, a bounce off
  a wall, a hit, a miss and its score, the computer's speed limit.
- **`PaddleServer.m9`** is the program. The state is one `MONITOR` record,
  and `Tick`, bound to it, is the only procedure that touches it, because
  `HttpServer` answers on several workers. `GET /tick?y=N` advances the
  game and answers the state as JSON; every other path is a file of
  `web/`.

The rules run in the server and the page only draws. So the test covers
the whole game without a browser.

## Run it

    m9c --make -o paddletest PaddleTest.m9 && ./paddletest
    m9c --make -o paddleserver PaddleServer.m9
    ./paddleserver                # http://127.0.0.1:8000, pages from web/
    ./paddleserver 8123 web       # another port, the page's folder named

Open the address, click or press space to serve, and move the mouse.
The server listens on 127.0.0.1 only. Stop it with Ctrl-C.

`runtime/test/paddle.sh` is the gate: the test, then the server asked for
`/tick` and the page.
