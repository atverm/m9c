#!/usr/bin/env python3
"""llmfix.py plays a chat server for runtime/test/llm.sh, and judges what
Llm sent it.  It needs only Python's standard library.

  llmfix.py serve PORT OUT   serve on 127.0.0.1:PORT, save each request
  llmfix.py judge OUT PNG    hold the saved requests to what LlmTest sent

The model name picks the reply.  fixture-NAME answers NAME.json from this
folder with the status in NAME.status: replies recorded from sglang
serving Qwen3.8-27B on 2026-11-21.  Three names have no file:
fixture-500 answers an OpenAI-style error, fixture-notjson a body that is
not JSON, and fixture-nochoices a completion without choices.  A body
that is not JSON gets sglang's own 400, as the real server answers it.
A request with "stream": true gets NAME.sse instead, one event per chunk
as uvicorn sends them: streams recorded from the same server (stage A4).
fixture-streamcut answers stream.sse without its [DONE], and
fixture-streamerror its first three pieces and then an error object.
That one is made up, not recorded: no server was seen sending it.
fixture-echo is made up too: it answers "echo: " and the last user
message after half a second, or a 500 when that message is "fail".  It
counts the echo requests it holds at once, and the most it held goes to
OUT/echo.max: the judge holds Llm.Batch's inFlight to it.
badmodel.json is a record, not a reply the test asks for: sglang
answered a request for model no-such-model as if it named its own
(docs/ml-plan.md, A1).

The judge is the oracle for the requests: Python's json decodes each one,
and each is compared with the conversation LlmTest holds (corpus/LlmTest.m9,
procedure Live).
"""
import base64
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))

HARD = 'What is 17*23? Use the tool. "Quoted", C:\\data and CO\u2082'
MUL = {"type": "object",
       "properties": {"a": {"type": "integer"}, "b": {"type": "integer"}},
       "required": ["a", "b"]}
TOOLS = [{"type": "function",
          "function": {"name": "mul", "description": "multiply two integers",
                       "parameters": MUL}}]


def recorded(name):
    with open(os.path.join(HERE, name + ".json"), "rb") as f:
        body = f.read()
    with open(os.path.join(HERE, name + ".status")) as f:
        status = int(f.read().strip())
    return status, body


def reply(model):
    if model == "fixture-500":
        return 500, json.dumps({"error": {"message": 'boom "quoted"'}}).encode()
    if model == "fixture-notjson":
        return 200, b"this is not json"
    if model == "fixture-nochoices":
        return 200, b'{"object":"chat.completion","id":"x"}'
    if model.startswith("fixture-") and os.path.exists(os.path.join(HERE, model[8:] + ".json")):
        return recorded(model[8:])
    return 404, json.dumps({"error": {"message": "no fixture for model " + model}}).encode()


def events(name):
    with open(os.path.join(HERE, name + ".sse"), "rb") as f:
        raw = f.read()
    return [e + b"\n\n" for e in raw.split(b"\n\n") if e]


def assemble(name):
    """The reply a stream carries, as Python's json reads it: the oracle
    for Llm.Collect."""
    r = {"content": "", "reasoning": "", "finish": "", "usage": None}
    for e in events(name):
        data = e.decode().strip()[len("data: "):]
        if data == "[DONE]":
            break
        d = json.loads(data)
        for ch in d["choices"][:1]:
            r["content"] += ch["delta"].get("content") or ""
            r["reasoning"] += ch["delta"].get("reasoning_content") or ""
            r["finish"] = ch.get("finish_reason") or r["finish"]
        if d.get("usage"):
            r["usage"] = d["usage"]
    return r


def echo(req):
    said = [m["content"] for m in req["messages"] if m["role"] == "user"][-1]
    if said == "fail":
        return 500, json.dumps({"error": {"message": "echo refused"}}).encode()
    return 200, json.dumps({
        "id": "echo", "object": "chat.completion", "model": "fixture-echo",
        "choices": [{"index": 0, "finish_reason": "stop",
                     "message": {"role": "assistant", "content": "echo: " + said}}],
        "usage": {"prompt_tokens": 1, "completion_tokens": 1}}).encode()


def serve(port, out):
    count = [0]
    lock = threading.Lock()
    held = [0, 0]                 # echo requests held now, and the most

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_POST(self):
            raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            with lock:
                count[0] += 1
                n = count[0]
            with open(os.path.join(out, "%03d.json" % n), "w") as f:
                json.dump({"path": self.path,
                           "type": self.headers.get("Content-Type", ""),
                           "body": raw.decode("utf-8", "replace")}, f)
            if self.path != "/v1/chat/completions":
                status, body = 404, b'{"error":{"message":"no such path"}}'
            elif self.stream(raw):
                return
            elif b'"fixture-echo"' in raw:
                with lock:
                    held[0] += 1
                    held[1] = max(held)
                    with open(os.path.join(out, "echo.max"), "w") as f:
                        f.write("%d\n" % held[1])
                time.sleep(0.5)
                with lock:
                    held[0] -= 1
                status, body = echo(json.loads(raw))
            else:
                try:
                    status, body = reply(json.loads(raw)["model"])
                except ValueError:
                    status, body = recorded("badjson")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def stream(self, raw):
            """Answers a streamed request from NAME.sse; FALSE when the
            request does not ask for one or has no stream recorded."""
            try:
                req = json.loads(raw)
            except ValueError:
                return False
            model = req.get("model", "")
            name = model[8:]
            if not req.get("stream"):
                return False
            if name == "streamcut":
                evs = events("stream")[:-1]
            elif name == "streamerror":
                evs = events("stream")[:3] + [
                    b'data: {"error": {"message": "boom mid-stream"}}\n\n']
            elif os.path.exists(os.path.join(HERE, name + ".sse")):
                evs = events(name)
            else:
                return False
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            for e in evs:
                self.wfile.write(b"%x\r\n" % len(e) + e + b"\r\n")
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
            self.close_connection = True
            return True

    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print("serving", flush=True)
    srv.serve_forever()


def judge(out, png):
    bad = []

    def want(label, got, expected):
        if got != expected:
            bad.append("%s: got %r, want %r" % (label, got, expected))

    names = sorted(x for x in os.listdir(out) if x.endswith(".json"))
    reqs = []
    for x in names:
        with open(os.path.join(out, x)) as f:
            r = json.load(f)
        want(x + " path", r["path"], "/v1/chat/completions")
        want(x + " content type", r["type"], "application/json")
        try:
            reqs.append(json.loads(r["body"]))
        except ValueError as e:
            bad.append("%s is not JSON: %s" % (x, e))
            reqs.append({})
    want("requests", len(reqs), 29)
    if len(reqs) != 29:
        print("\n".join(bad))
        return 1

    call = json.loads(recorded("toolcall")[1])["choices"][0]["message"]["tool_calls"][0]
    first = [{"role": "system", "content": "Answer briefly."},
             {"role": "user", "content": HARD + "\nSecond line."}]
    want("1 model", reqs[0].get("model"), "fixture-toolcall")
    want("1 max_tokens", reqs[0].get("max_tokens"), 4096)
    want("1 messages", reqs[0].get("messages"), first)
    want("1 tools", reqs[0].get("tools"), TOOLS)

    want("2 model", reqs[1].get("model"), "fixture-toolresult")
    want("2 messages", reqs[1].get("messages"), first + [
        {"role": "assistant", "content": "\n\n",
         "tool_calls": [{"id": call["id"], "type": "function",
                         "function": {"name": "mul",
                                      "arguments": call["function"]["arguments"]}}]},
        {"role": "tool", "tool_call_id": call["id"], "content": "391"}])
    want("2 tools", reqs[1].get("tools"), TOOLS)

    count = [{"role": "user", "content": "Count from 1 to 100."}]
    want("3 model", reqs[2].get("model"), "fixture-length")
    want("3 max_tokens", reqs[2].get("max_tokens"), 20)
    want("3 messages", reqs[2].get("messages"), count)
    want("3 no tools", "tools" in reqs[2], False)
    want("4 is 3 again: a cut-off reply is not recorded", reqs[3], reqs[2])

    with open(png, "rb") as f:
        url = "data:image/png;base64," + base64.b64encode(f.read()).decode()
    want("5 messages", reqs[4].get("messages"), [
        {"role": "user", "content": [
            {"type": "text", "text": "Describe this image in one sentence."},
            {"type": "image_url", "image_url": {"url": url}}]}])

    hi = [{"role": "user", "content": "hi"}]
    for i, m in ((5, "fixture-badjson"), (6, "fixture-500"),
                 (7, "fixture-notjson"), (8, "fixture-nochoices")):
        want("%d model" % (i + 1), reqs[i].get("model"), m)
        want("%d messages" % (i + 1), reqs[i].get("messages"), hi)

    # The streams (stage A4).  Every streamed request asks for the usage.
    co2 = [{"role": "user", "content": "Name the chemical formula of "
            "carbon dioxide, in one short sentence."}]
    for i, m in ((9, "fixture-stream"), (10, "fixture-stream"),
                 (12, "fixture-streamlength"), (13, "fixture-streamlength"),
                 (14, "fixture-500"), (15, "fixture-streamcut"),
                 (16, "fixture-streamerror")):
        want("%d model" % (i + 1), reqs[i].get("model"), m)
        want("%d stream" % (i + 1), reqs[i].get("stream"), True)
        want("%d usage asked" % (i + 1), reqs[i].get("stream_options"),
             {"include_usage": True})
    want("10 messages", reqs[9].get("messages"), co2)
    want("11 is 10 again: Next records nothing", reqs[10], reqs[9])
    # The request after Collect carries the answer the stream made, as
    # Python reads it from stream.sse.
    want("12 model", reqs[11].get("model"), "fixture-answer")
    want("12 not streamed", "stream" in reqs[11], False)
    want("12 messages", reqs[11].get("messages"), co2 + [
        {"role": "assistant", "content": assemble("stream")["content"]},
        {"role": "user", "content": "Thank you."}])
    want("13 max_tokens", reqs[12].get("max_tokens"), 10)
    want("14 is 13 again: a cut-off stream is not recorded", reqs[13], reqs[12])
    for i in (14, 15, 16):
        want("%d messages" % (i + 1), reqs[i].get("messages"), hi)

    # Llm.Batch: twelve prompts, four at a time, in any order.
    asked = []
    for i in range(17, 29):
        want("%d model" % (i + 1), reqs[i].get("model"), "fixture-echo")
        m = reqs[i].get("messages", [])
        want("%d system first" % (i + 1), m[:1], [{"role": "system", "content": "Echo."}])
        want("%d one prompt after it" % (i + 1), len(m), 2)
        asked += [x.get("content") for x in m[1:]]
    want("every prompt asked once", sorted(asked),
         sorted(["p%d" % k for k in range(12) if k != 5] + ["fail"]))
    try:
        with open(os.path.join(out, "echo.max")) as f:
            most = int(f.read())
    except OSError:
        most = 0
    want("the most echo requests held at once: inFlight", most, 4)

    for b in bad:
        print("FAIL", b)
    print("llmfix judge: %d requests, %d wrong" % (len(reqs), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    if sys.argv[1] == "serve":
        serve(int(sys.argv[2]), sys.argv[3])
    elif sys.argv[1] == "judge":
        sys.exit(judge(sys.argv[2], sys.argv[3]))
    else:
        sys.exit("usage: llmfix.py serve PORT OUT | judge OUT PNG")
