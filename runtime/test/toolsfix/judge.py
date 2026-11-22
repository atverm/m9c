#!/usr/bin/env python3
"""judge.py OUT checks what ToolsTest printed against the schemas Offer
made, for runtime/test/llmtools.sh; judge.py answers OUT checks what
AnswersTest printed against the schemas a chat asked with.  It needs
only Python's standard library.

The schemas are read from the BODY line: the request Llm would send.
validate() is a JSON Schema check of the subset M9Tools writes (type,
minimum, maximum, enum, items, properties, required,
additionalProperties false), written here
and not taken from M9.  For each call it decides from the schema alone
whether the arguments are acceptable.  Run must agree.  It refuses
exactly the calls the schema refuses, with an argument error.  It
answers the others, or an exception of the procedure, never an
argument error.
"""
import json
import sys

ARGUMENT_ERRORS = ("missing argument", "unknown argument", "is not a number",
                   "is not an integer", "is out of range", "is not true or false",
                   "is not a string", "the arguments are not", "no tool named")


def kind(v):
    if isinstance(v, bool):
        return "boolean"
    if isinstance(v, int):
        return "integer"
    if isinstance(v, float):
        return "integer" if v.is_integer() else "number"
    if isinstance(v, str):
        return "string"
    return "other"


def validate(schema, v, where="the value"):
    """validate answers why v fails schema, or None: type, minimum,
    maximum, enum, items, properties, required, additionalProperties."""
    t = schema["type"]
    k = "array" if isinstance(v, list) else "object" if isinstance(v, dict) else kind(v)
    if t == "number":
        if k not in ("integer", "number"):
            return where + " is not a number"
    elif t != k:
        return where + " is not " + t
    if "minimum" in schema and v < schema["minimum"]:
        return where + " below minimum"
    if "maximum" in schema and v > schema["maximum"]:
        return where + " above maximum"
    if "enum" in schema and v not in schema["enum"]:
        return where + " is not in the enum"
    if t == "array":
        for i, x in enumerate(v):
            why = validate(schema["items"], x, "%s[%d]" % (where, i))
            if why:
                return why
    if t == "object":
        props = schema["properties"]
        for name in schema["required"]:
            if name not in v:
                return "missing " + name
        if schema.get("additionalProperties") is False:
            for name in v:
                if name not in props:
                    return "unknown " + name
        for name, x in v.items():
            why = validate(props[name], x, name)
            if why:
                return why
    return None


def answers(out):
    """answers holds AnswersTest's lines: a text is read into its record
    exactly when it fits the schema the chat asked with."""
    lines = open(out, encoding="utf-8").read().splitlines()
    schemas = {}
    for l in lines:
        if l.startswith("BODY ") and not l.startswith("BODY free "):
            name, body = l[5:].split(" ", 1)
            schemas[name] = json.loads(body)["response_format"]["json_schema"]["schema"]
    free = [l for l in lines if l.startswith("BODY free ")]
    bad = 0
    if len(free) != 1 or "response_format" in json.loads(free[0][10:]):
        print("FAIL: Free did not ask for text again")
        bad += 1
    n = 0
    for l in lines:
        if l.startswith("BODY ") or " (with newlines first) " in l:
            continue
        head, result = l.split(" -> ", 1)
        name, text = head.split(" ", 1)
        n += 1
        try:
            why = validate(schemas[name], json.loads(text))
        except ValueError:
            why = "not JSON"
        if (why is None) != result.startswith("ok "):
            bad += 1
            print("FAIL: %s %s: the schema says %s, Parse answered %s"
                  % (name, text, why or "acceptable", result))
    print("judge: %d answers, %d schemas, %d disagreements" % (n, len(schemas), bad))
    return 1 if bad else 0


def main(out):
    lines = open(out, encoding="utf-8").read().splitlines()
    body = [l for l in lines if l.startswith("BODY ")]
    if len(body) != 1:
        print("FAIL: no BODY line")
        return 1
    tools = {t["function"]["name"]: t["function"]["parameters"]
             for t in json.loads(body[0][5:])["tools"]}
    bad = 0
    n = 0
    for l in lines:
        if l.startswith("BODY "):
            continue
        head, result = l.split(" -> ", 1)
        name, args = head.split(" ", 1)
        n += 1
        try:
            parsed = json.loads(args)
        except ValueError:
            parsed = None
        if name not in tools:
            why = "no such tool"
        elif parsed is None:
            why = "not JSON"
        else:
            why = validate(tools[name], parsed, "the arguments")
            if why == "the arguments is not object":
                why = "not an object"
        refused = result.startswith('{"error":') and any(e in result for e in ARGUMENT_ERRORS)
        if (why is not None) != refused:
            bad += 1
            print("FAIL: %s %s: the schema says %s, Run answered %s"
                  % (name, args, why or "acceptable", result))
    print("judge: %d calls, %d tools, %d disagreements with the schemas" % (n, len(tools), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    if sys.argv[1] == "answers":
        sys.exit(answers(sys.argv[2]))
    sys.exit(main(sys.argv[1]))
