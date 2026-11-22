# Llm

Llm is a client for a chat model behind the OpenAI-style API:
POST BASE/chat/completions, as sglang, vLLM, llama.cpp's server and
OpenAI serve it (docs/ml-plan.md, stage A1).

A Chat is a record the caller owns, like a Seq list.  Its storage
is in the POOL the caller names at every call, so the chat lives as
long as that pool.  It holds the server, the model, the messages
so far and the tools offered:

    Llm.Init (pool, c, 'http://localhost:30000/v1', 'qwen') ;
    Llm.User (pool, c, 'What is 17*23?') ;
    Llm.Send (pool, c, r) ;
    ... r.content, r.calls[i].name ...

Send records the model's answer in the chat, tool calls included.
So the next Send continues the conversation.  A tool's result goes
back by ToolResult, under the id of the call it answers.

Every string goes into the request through Json.Quote.  So a quote,
a backslash or a character past ASCII in a message cannot break the
request.  Every string of a Reply is decoded (Json.Text) and copied
into the pool.

A reply cut off by the token limit raises Truncated, unless the chat
allows it.  The model's reasoning counts against that limit: a
reasoning model can spend the whole limit reasoning and answer an
empty content.  The exception names both counts.

Parse reads a reply document without the network.  So a reply read
from a file is a Reply too, and the test holds the reading to
replies recorded from a real server.

### TYPE Chat

_(undocumented)_

- `url : STR` -- the API's base, ending in /v1
- `model : STR`
- `maxTokens : I64` -- max_tokens; reasoning counts in it
- `allowTruncated : BOOL` -- TRUE: a cut-off reply is answered
- `format : STR` -- response_format as JSON; '' for text
- `messages : Seq.Strs` -- each one compact JSON
- `tools : Seq.Strs` -- each one compact JSON

### TYPE Call

_(undocumented)_

- `id : STR` -- the id ToolResult answers under
- `name : STR`
- `arguments : STR` -- JSON text, as the model wrote it

### TYPE Reply

_(undocumented)_

- `content : STR` -- the answer, as the server sent it
- `reasoning : STR` -- reasoning_content; '' when none
- `finish : STR` -- stop, length, tool_calls
- `calls : SLICE OF Call`
- `promptTokens : I64`
- `completionTokens : I64` -- reasoning included
- `reasoningTokens : I64` -- 0 when the server does not say

### EXCEPTION ServerError

ServerError says the server answered, but not 200.  msg is the
start of what it said.

### EXCEPTION FormatError

FormatError reports a reply that is not a chat completion, or a
tool schema that is not a JSON object.

### EXCEPTION Truncated

Truncated says the reply hit maxTokens: completion tokens in
all, reasoning tokens of them.

### CONST DefaultMaxTokens

_(documented with the group below)_

### CONST ReplyCap

16 MB of reply, refused past it

### CONST ErrorShown

characters of an error body kept

### Init (VAR pool: POOL ; VAR c: Chat ; RO url: STR ; RO model: STR)

Init starts an empty chat with model at url, with
DefaultMaxTokens and no tools.

### System (VAR pool: POOL ; VAR c: Chat ; RO text: STR)

_(documented with the group below)_

### User (VAR pool: POOL ; VAR c: Chat ; RO text: STR)

_(documented with the group below)_

### UserImage (VAR pool: POOL ; VAR c: Chat ; RO text: STR ; RO mime: STR ; RO image: SLICE OF BYTE)

UserImage adds a user message of text and one image.  The image
goes as a base64 data URL; mime is its type, image/png say.

### Tool (VAR pool: POOL ; VAR c: Chat ; RO name: STR ; RO description: STR ; RO parameters: STR) RAISES FormatError

Tool offers the model a function.  parameters is its JSON schema
as text, an object.  Anything else raises FormatError.

### ToolResult (VAR pool: POOL ; VAR c: Chat ; RO callId: STR ; RO content: STR)

ToolResult adds the result of the call whose id is callId.

### Assistant (VAR pool: POOL ; VAR c: Chat ; RO r: Reply)

Assistant adds r as the model's message, its calls included.
Send does this itself.  It is for a chat rebuilt from replies
read elsewhere.

### Expect (VAR pool: POOL ; VAR c: Chat ; RO name: STR ; RO schema: STR) RAISES FormatError

Expect asks for the next answers as JSON that fits schema, a JSON
schema object as text, named name.  The server constrains its
output to it (sglang does; response_format json_schema).  The
answer is still text: the caller reads it, and a reader made by
tools/M9Tools.m9 checks it against the M9 type again.

### Free (VAR c: Chat)

Free asks for text again, after Expect.

### Messages (RO c: Chat) : I64

_(documented with the group below)_

### Body (RO c: Chat) : STR

Body answers the request Send would post, as JSON text.

### Send (VAR pool: POOL ; VAR c: Chat ; VAR r: Reply) RAISES Http.TransportError, ServerError, FormatError, Truncated, ValueRange

Send posts the chat and reads the reply into r, in pool.  It
records the reply in the chat.

### Parse (VAR pool: POOL ; RO doc: STR ; VAR r: Reply) RAISES FormatError, ValueRange

Parse reads a chat completion document into r, in pool.

### TYPE Delta

_(undocumented)_

- `content : STR` -- this piece of the answer; '' when none
- `reasoning : STR` -- this piece of reasoning_content
- `finish : STR` -- '' until the piece that ends the reply
- `promptTokens : I64` -- the usage, in the last piece; 0 before
- `completionTokens : I64`
- `reasoningTokens : I64`

### Stream (VAR pool: POOL ; RO c: Chat) : PTR Http.Stream IN pool RAISES Http.TransportError, ServerError, FormatError, ValueRange

Stream posts c for a streamed reply.  It asks for the usage too
(stream_options include_usage).  A status other than 200 raises
ServerError, with the server's message.  A chat with tools raises
FormatError, and nothing is sent.

### Next (VAR pool: POOL ; VAR s: PTR Http.Stream ; VAR d: Delta) : BOOL RAISES Http.TransportError, ServerError, FormatError, ValueRange

Next reads the next piece into d, in pool, and answers TRUE.  At
[DONE] it closes the stream and answers FALSE.  Lines that are not
data (comments, blank lines, event names) are passed over.  A
piece that is an error object raises ServerError with status 200,
the status the stream began with.  A stream that ends before
[DONE] raises FormatError.  Whatever Next raises, it has closed
the stream.

### Collect (VAR pool: POOL ; VAR c: Chat ; VAR s: PTR Http.Stream ; VAR r: Reply) RAISES Http.TransportError, ServerError, FormatError, Truncated, ValueRange

Collect reads every piece left into r, in pool, and records r in
c.  A reply cut off by the token limit raises Truncated unless c
allows it, as Send does, and is then not recorded.

### CONST MaxInFlight

_(documented with the group below)_

### Batch (VAR pool: POOL ; RO c: Chat ; RO prompts: SLICE OF STR ; inFlight: I64 ; VAR answers: SLICE OF STR ; VAR errors: SLICE OF STR) RAISES ValueRange

Batch sends c with prompts[k] as one more user message, for every
k, and puts the answer's content in answers[k], in pool.  A prompt
whose request failed gets '' there and the failure in errors[k],
the exception's name and fields, as `ServerError 500 boom`; errors
is '' for every prompt answered.  A failure ends only its own
prompt.  The answers are not recorded in c.  inFlight is 1 ..
MaxInFlight, else ValueRange.
