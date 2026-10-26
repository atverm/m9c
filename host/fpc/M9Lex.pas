unit M9Lex;

{ M9 lexer -- the first thousandth of the bootstrap compiler (v0 host: FPC).

  Lexical decisions forced by implementation, now normative for the report:
  - Comments: (* ... *), NESTED, per Modula tradition.
  - Strings: 'x' or "x", no escape sequences; a string cannot contain its
    own delimiter (Wirth's rule; use the other quote).
  - Identifiers: letters then letters/digits. No underscores.
  - Integers: decimal, or hex as 0x1F. Reals: 1.5, 1.5e-3; the
    exponent requires a decimal point, so 1E5 is malformed, not a real.
  - Char literals: hex digits then C, as in 0AC = U+000A. The value
    must be a Unicode scalar (<= 10FFFF and not a surrogate).
  - A letter may never immediately follow a numeric literal. Before
    this rule 0AC lexed silently as IntLit 0 then Ident AC.
  - Wrapping arithmetic: +% -% *% are single tokens (report par 2.1).
  - .. is the range token (slices); . is member access; ambiguity 1..5
    resolved by longest-match on the dots, so 1..5 lexes INT DOTDOT INT.
  - Every token carries line and column; errors are tokens, not halts,
    so the parser can recover and a tool can report many errors at once. }

{$mode objfpc}{$H+}

interface

type
  TTokKind = (
    tkEOF, tkError,
    tkIdent, tkIntLit, tkRealLit, tkCharLit, tkStrLit,
    { keywords -- keep alphabetical; table below must match }
    tkAND, tkARRAY, tkBEGIN, tkBY, tkCASE, tkCONST, tkDEFINITION,
    tkDISPOSE, tkDIV, tkDO, tkELSE, tkELSIF, tkEND, tkEXCEPT,
    tkEXCEPTION, tkEXIT,
    tkFALSE, tkFINALLY, tkFOR, tkFROM, tkGRID, tkIF, tkIMPLEMENTATION, tkIMPORT,
    tkIN, tkIS, tkLOOP, tkMOD, tkMODULE, tkMONITOR, tkNEW, tkNONE,
    tkNOT, tkOF, tkOPT, tkOR, tkOWN, tkPOOL, tkPROCEDURE, tkPTR,
    tkKEPT, tkLINK, tkRAISE, tkRAISES, tkRECORD, tkRETURN, tkRO, tkSHARED, tkSIGNAL,
    tkSLICE,
    tkSOME, tkSTATEFUL, tkTHEN, tkTHREAD, tkTO, tkTRANSFER, tkTRUE,
    tkTYPE, tkUNSAFE, tkVAR, tkWAIT, tkWHILE,
    { operators and delimiters }
    tkAssign,                 { :=  }
    tkEq, tkNeq,              { =  # }
    tkLt, tkLe, tkGt, tkGe,   { <  <=  >  >= }
    tkPlus, tkMinus, tkStar, tkSlash,
    tkPlusWrap, tkMinusWrap, tkStarWrap,   { +%  -%  *% }
    tkLParen, tkRParen, tkLBrack, tkRBrack,
    tkComma, tkSemi, tkColon, tkDot, tkDotDot, tkBar, tkCaret
  );

  TToken = record
    kind      : TTokKind;
    text      : string;      { verbatim source slice; for tkError, message }
    line, col : Integer;
  end;

  { A comment, for callers that want the documentation rather than
    the program.  text is VERBATIM, delimiters included.  The M9 side
    is corpus/Lex.m9's Comment and comdiff holds the two to the same
    answer. }
  TComment = record
    line, col, endLine : Integer;
    text : string;
  end;

  TLexer = class
  private
    FSrc  : string;
    FPos  : Integer;         { 1-based index into FSrc }
    FLine : Integer;
    FCol  : Integer;
    FCollect : Boolean;
    FComs : array of TComment;
    FNCom : Integer;
    function Peek (ahead: Integer = 0): Char;
    procedure Advance;
    procedure Note (ln, cl, eln: Integer; const s: string);
    procedure SkipBlanksAndComments (var err: string;
                                     var eline, ecol: Integer);
    function MakeTok (k: TTokKind; const s: string;
                      ln, cl: Integer): TToken;
  public
    constructor Create (const Source: string);
    function Next: TToken;
    { Comments are NOT tokens and never will be: a comment token kind
      would move every count in lextest.golden.  Armed, the lexer also
      records each comment it skips; the token stream is untouched.
      Per-INSTANCE here because TLexer is a class; the M9 side keeps
      one module-level list because its Lexer is a record and Init
      takes no pool.  The two need not be shaped alike -- comdiff
      holds them to the same OUTPUT. }
    procedure Collect (on: Boolean);
    function ComCount: Integer;
    function ComAt (i: Integer): TComment;
  end;

function KindName (k: TTokKind): string;

implementation

uses SysUtils;

type
  TKw = record
    s : string;
    k : TTokKind;
  end;

const
  { alphabetical: binary-searchable }
  Keywords : array [0..61] of TKw = (
    (s:'AND';k:tkAND), (s:'ARRAY';k:tkARRAY), (s:'BEGIN';k:tkBEGIN),
    (s:'BY';k:tkBY), (s:'CASE';k:tkCASE), (s:'CONST';k:tkCONST),
    (s:'DEFINITION';k:tkDEFINITION), (s:'DISPOSE';k:tkDISPOSE),
    (s:'DIV';k:tkDIV), (s:'DO';k:tkDO), (s:'ELSE';k:tkELSE),
    (s:'ELSIF';k:tkELSIF), (s:'END';k:tkEND), (s:'EXCEPT';k:tkEXCEPT),
    (s:'EXCEPTION';k:tkEXCEPTION), (s:'EXIT';k:tkEXIT),
    (s:'FALSE';k:tkFALSE),
    (s:'FINALLY';k:tkFINALLY), (s:'FOR';k:tkFOR), (s:'FROM';k:tkFROM),
    (s:'GRID';k:tkGRID),
    (s:'IF';k:tkIF), (s:'IMPLEMENTATION';k:tkIMPLEMENTATION),
    (s:'IMPORT';k:tkIMPORT), (s:'IN';k:tkIN), (s:'IS';k:tkIS),
    (s:'KEPT';k:tkKEPT), (s:'LINK';k:tkLINK), (s:'LOOP';k:tkLOOP), (s:'MOD';k:tkMOD), (s:'MODULE';k:tkMODULE),
    (s:'MONITOR';k:tkMONITOR), (s:'NEW';k:tkNEW), (s:'NONE';k:tkNONE),
    (s:'NOT';k:tkNOT), (s:'OF';k:tkOF), (s:'OPT';k:tkOPT),
    (s:'OR';k:tkOR), (s:'OWN';k:tkOWN), (s:'POOL';k:tkPOOL),
    (s:'PROCEDURE';k:tkPROCEDURE), (s:'PTR';k:tkPTR),
    (s:'RAISE';k:tkRAISE), (s:'RAISES';k:tkRAISES),
    (s:'RECORD';k:tkRECORD), (s:'RETURN';k:tkRETURN),
    (s:'RO';k:tkRO),
    (s:'SHARED';k:tkSHARED), (s:'SIGNAL';k:tkSIGNAL),
    (s:'SLICE';k:tkSLICE), (s:'SOME';k:tkSOME),
    (s:'STATEFUL';k:tkSTATEFUL), (s:'THEN';k:tkTHEN),
    (s:'THREAD';k:tkTHREAD), (s:'TO';k:tkTO),
    (s:'TRANSFER';k:tkTRANSFER), (s:'TRUE';k:tkTRUE),
    (s:'TYPE';k:tkTYPE), (s:'UNSAFE';k:tkUNSAFE), (s:'VAR';k:tkVAR),
    (s:'WAIT';k:tkWAIT), (s:'WHILE';k:tkWHILE)
  );

function KindName (k: TTokKind): string;
begin
  Str (k, Result);
  Delete (Result, 1, 2);          { drop the tk prefix for display }
end;

function LookupKeyword (const s: string): TTokKind;
var
  lo, hi, mid, c : Integer;
begin
  lo := Low (Keywords);
  hi := High (Keywords);
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    c := CompareStr (s, Keywords[mid].s);
    if c = 0 then Exit (Keywords[mid].k)
    else if c < 0 then hi := mid - 1
    else lo := mid + 1;
  end;
  Result := tkIdent;
end;

{ ---------------- TLexer ---------------- }

constructor TLexer.Create (const Source: string);
begin
  FSrc := Source;
  FPos := 1;
  FLine := 1;
  FCol := 1;
  { a first line beginning #! names the program that runs this file
    as a script and is not M9 (report par 2); skipped to its line
    end, so the newline is counted and every line keeps its number }
  { a byte order mark (U+FEFF, EF BB BF) is skipped, the column
    stays 1 (mirrors Lex.Init) }
  if (Length (FSrc) >= 3) and (FSrc[1] = #$EF) and (FSrc[2] = #$BB) and
     (FSrc[3] = #$BF) then
    FPos := 4;
  if (Length (FSrc) >= FPos + 1) and (FSrc[FPos] = '#') and (FSrc[FPos + 1] = '!') then
    while (FPos <= Length (FSrc)) and (FSrc[FPos] <> #10) do
      Inc (FPos);
end;

{ ---- literals beyond 64 bits (mirrors Lex.m9's IntPast64, RealTooBig
  and the hex rule; the compiler review's F1, 2026-10-21): an integer
  literal is at most 64 bits, decimal or hex; a real does not round
  to infinity as an F64 -- held exactly against 2^1024 - 2^970 ---- }
const
  U64Top = '18446744073709551615';
  F64Top = '179769313486231580793728971405303415079934132710037826936173778980444968292764750946649017977587207096330286416692887910946555547851940402630657488671505820681908902000708383676273854845817711531764475730270069855571366959622842914819860834936475292719074168444365510704342711559699508093042880177904174497792';

function Significant (const run: string; from: Integer): Integer;
var i : Integer;
begin
  i := from;
  while (i < Length (run)) and (run[i] = '0') do Inc (i);
  Result := i;
end;

function IntPast64 (const run: string): Boolean;
var i, n, k : Integer;
begin
  i := Significant (run, 1);
  n := Length (run) - i + 1;
  if n <> Length (U64Top) then Exit (n > Length (U64Top));
  for k := 0 to n - 1 do
    if run[i + k] <> U64Top[k + 1] then Exit (run[i + k] > U64Top[k + 1]);
  Result := False;
end;

function RealTooBig (const run: string): Boolean;
var i, m, e, nInt, lead, n, j : Integer; neg : Boolean;
begin
  m := 1;
  while (m <= Length (run)) and not (run[m] in ['e', 'E']) do Inc (m);
  nInt := 0;
  while (nInt + 1 < m) and (run[nInt + 1] <> '.') do Inc (nInt);
  e := 0;
  if m <= Length (run) then
  begin
    i := m + 1;
    neg := False;
    if run[i] = '+' then Inc (i)
    else if run[i] = '-' then begin neg := True; Inc (i) end;
    while i <= Length (run) do
    begin
      if e < 100000 then e := e * 10 + (Ord (run[i]) - 48);
      Inc (i);
    end;
    if neg then e := -e;
  end;
  lead := 0;
  i := 1;
  while (i < m) and (run[i] in ['0', '.']) do
  begin
    if run[i] = '0' then Inc (lead);
    Inc (i);
  end;
  if i = m then Exit (False);
  n := nInt - lead + e;
  if n <> Length (F64Top) then Exit (n > Length (F64Top));
  j := 1;
  while i < m do
  begin
    if run[i] <> '.' then
    begin
      if j > Length (F64Top) then Exit (True);
      if run[i] <> F64Top[j] then Exit (run[i] > F64Top[j]);
      Inc (j);
    end;
    Inc (i);
  end;
  while j <= Length (F64Top) do
  begin
    if F64Top[j] <> '0' then Exit (False);
    Inc (j);
  end;
  Result := True;
end;

function TLexer.Peek (ahead: Integer): Char;
begin
  if FPos + ahead <= Length (FSrc) then
    Result := FSrc[FPos + ahead]
  else
    Result := #0;
end;

procedure TLexer.Advance;
begin
  { a line ends at LF, and at a CR no LF follows (mirrors Lex.Advance) }
  if (Peek = #10) or ((Peek = #13) and (Peek (1) <> #10)) then
  begin
    Inc (FLine);
    FCol := 1;
  end
  else if (Ord (Peek) and $C0) <> $80 then
    { a column is a Unicode scalar, as the M9 lexer counts (it reads
      the source decoded since 2026-10-09): a UTF-8 continuation byte
      is no column of its own }
    Inc (FCol);
  Inc (FPos);
end;

procedure TLexer.Collect (on: Boolean);
begin
  FCollect := on;
  if on then FNCom := 0;
end;

function TLexer.ComCount: Integer;
begin
  Result := FNCom;
end;

function TLexer.ComAt (i: Integer): TComment;
begin
  Result := FComs[i];
end;

procedure TLexer.Note (ln, cl, eln: Integer; const s: string);
begin
  if FNCom = Length (FComs) then
  begin
    if Length (FComs) = 0 then SetLength (FComs, 64)
    else SetLength (FComs, 2 * Length (FComs));
  end;
  FComs[FNCom].line := ln;
  FComs[FNCom].col := cl;
  FComs[FNCom].endLine := eln;
  FComs[FNCom].text := s;
  Inc (FNCom);
end;

procedure TLexer.SkipBlanksAndComments (var err: string;
                                        var eline, ecol: Integer);
var
  depth, cstart : Integer;
begin
  err := '';
  while True do
  begin
    while Peek in [' ', #9, #13, #10] do Advance;
    if (Peek = '(') and (Peek (1) = '*') then
    begin
      eline := FLine;
      ecol := FCol;
      cstart := FPos;
      depth := 0;
      repeat
        if (Peek = '(') and (Peek (1) = '*') then
        begin
          Inc (depth);
          Advance;
          Advance;
        end
        else if (Peek = '*') and (Peek (1) = ')') then
        begin
          Dec (depth);
          Advance;
          Advance;
          { FLine is still the line the closing delimiter sits on }
          if (depth = 0) and FCollect then
            Note (eline, ecol, FLine, Copy (FSrc, cstart, FPos - cstart));
        end
        else if Peek = #0 then
        begin
          err := 'unterminated comment (opened here)';
          Exit;
        end
        else
          Advance;
      until depth = 0;
    end
    else
      Exit;
  end;
end;

function TLexer.MakeTok (k: TTokKind; const s: string;
                         ln, cl: Integer): TToken;
begin
  Result.kind := k;
  Result.text := s;
  Result.line := ln;
  Result.col := cl;
end;

function TLexer.Next: TToken;
var
  ln, cl, start : Integer;
  err, run : string;
  q : Char;
  isReal, hasHexLetter : Boolean;
  cv : Int64;
begin
  SkipBlanksAndComments (err, ln, cl);
  if err <> '' then Exit (MakeTok (tkError, err, ln, cl));

  ln := FLine;
  cl := FCol;
  start := FPos;

  case Peek of
    #0 :
      { Peek answers #0 past the end; a NUL before it is a character }
      if FPos <= Length (FSrc) then
      begin
        Advance;
        Exit (MakeTok (tkError, 'unexpected character 0x00', ln, cl));
      end
      else
        Exit (MakeTok (tkEOF, '', ln, cl));

    'A'..'Z', 'a'..'z' :
      begin
        while Peek in ['A'..'Z', 'a'..'z', '0'..'9'] do Advance;
        Result := MakeTok (tkIdent, Copy (FSrc, start, FPos - start), ln, cl);
        Result.kind := LookupKeyword (Result.text);
        if Peek = '_' then
          Exit (MakeTok (tkError,
            'underscore is not part of an identifier in M9', FLine, FCol));
        Exit (Result);
      end;

    '0'..'9' :
      begin
        if (Peek = '0') and (Peek (1) = 'x') then
        begin
          Advance;
          Advance;
          if not (Peek in ['0'..'9', 'A'..'F', 'a'..'f']) then
            Exit (MakeTok (tkError, 'hex literal needs digits after 0x',
                           ln, cl));
          while Peek in ['0'..'9', 'A'..'F', 'a'..'f'] do Advance;
          if Peek in ['A'..'Z', 'a'..'z'] then
            Exit (MakeTok (tkError,
              'letter may not immediately follow a numeric literal',
              ln, cl));
          run := Copy (FSrc, start + 2, FPos - start - 2);
          if Length (run) - Significant (run, 1) + 1 > 16 then
            Exit (MakeTok (tkError, 'hex literal beyond 64 bits', ln, cl));
          Exit (MakeTok (tkIntLit, Copy (FSrc, start, FPos - start), ln, cl));
        end;
        { gather digits and uppercase hex letters, classify by shape:
          ...C is a char literal, pure decimal is an int (maybe a real
          with fraction/exponent to follow), anything else malformed }
        hasHexLetter := False;
        while Peek in ['0'..'9', 'A'..'F'] do
        begin
          if Peek in ['A'..'F'] then hasHexLetter := True;
          Advance;
        end;
        run := Copy (FSrc, start, FPos - start);
        if hasHexLetter then
        begin
          if run[Length (run)] <> 'C' then
            Exit (MakeTok (tkError,
              'malformed numeric literal; forms are 10, 0x1F, 1.5, ' +
              '1.5e-3, 0AC', ln, cl));
          if Peek in ['A'..'Z', 'a'..'z'] then
            Exit (MakeTok (tkError,
              'letter may not immediately follow a numeric literal',
              ln, cl));
          if not TryStrToInt64 ('$' + Copy (run, 1, Length (run) - 1), cv)
             or (cv > $10FFFF) then
            Exit (MakeTok (tkError,
              'char literal beyond Unicode scalar range (max 10FFFFC)',
              ln, cl));
          if (cv >= $D800) and (cv <= $DFFF) then
            Exit (MakeTok (tkError,
              'char literal is a surrogate code point, not a scalar',
              ln, cl));
          Exit (MakeTok (tkCharLit, run, ln, cl));
        end;
        isReal := False;
        { the 1..5 case: dot followed by dot is DOTDOT, not a real }
        if (Peek = '.') and (Peek (1) <> '.') then
        begin
          isReal := True;
          Advance;
          if not (Peek in ['0'..'9']) then
            Exit (MakeTok (tkError, 'digit required after decimal point',
                           ln, cl));
          while Peek in ['0'..'9'] do Advance;
          { exponent only after a decimal point; dotless 1E5 never
            gets here (E was gathered above and rejected as malformed) }
          if Peek in ['e', 'E'] then
          begin
            Advance;
            if Peek in ['+', '-'] then Advance;
            if not (Peek in ['0'..'9']) then
              Exit (MakeTok (tkError, 'digit required in exponent', ln, cl));
            while Peek in ['0'..'9'] do Advance;
          end;
        end;
        if Peek in ['A'..'Z', 'a'..'z'] then
          Exit (MakeTok (tkError,
            'letter may not immediately follow a numeric literal ' +
            '(char literal ends in C: 0AC; exponent needs a decimal ' +
            'point: 1.0e5)', ln, cl));
        run := Copy (FSrc, start, FPos - start);
        if isReal then
        begin
          if RealTooBig (run) then
            Exit (MakeTok (tkError,
              'real literal beyond F64 (it would be an infinity)', ln, cl));
          Exit (MakeTok (tkRealLit, run, ln, cl));
        end;
        if IntPast64 (run) then
          Exit (MakeTok (tkError,
            'integer literal beyond 64 bits (the largest is 18446744073709551615, ' +
            'a U64; above MAX (I64) a literal is a U64)',
            ln, cl));
        Exit (MakeTok (tkIntLit, run, ln, cl));
      end;

    '''', '"' :
      begin
        q := Peek;
        Advance;
        start := FPos;
        while (Peek <> q) and (Peek <> #0) and (Peek <> #10) do Advance;
        if Peek <> q then
          Exit (MakeTok (tkError, 'unterminated string', ln, cl));
        Result := MakeTok (tkStrLit, Copy (FSrc, start, FPos - start), ln, cl);
        Advance;
        Exit (Result);
      end;

    ':' : begin
            Advance;
            if Peek = '=' then begin Advance;
              Exit (MakeTok (tkAssign, ':=', ln, cl)) end;
            Exit (MakeTok (tkColon, ':', ln, cl));
          end;
    '.' : begin
            Advance;
            if Peek = '.' then begin Advance;
              Exit (MakeTok (tkDotDot, '..', ln, cl)) end;
            Exit (MakeTok (tkDot, '.', ln, cl));
          end;
    '<' : begin
            Advance;
            if Peek = '=' then begin Advance;
              Exit (MakeTok (tkLe, '<=', ln, cl)) end;
            Exit (MakeTok (tkLt, '<', ln, cl));
          end;
    '>' : begin
            Advance;
            if Peek = '=' then begin Advance;
              Exit (MakeTok (tkGe, '>=', ln, cl)) end;
            Exit (MakeTok (tkGt, '>', ln, cl));
          end;
    '+' : begin
            Advance;
            if Peek = '%' then begin Advance;
              Exit (MakeTok (tkPlusWrap, '+%', ln, cl)) end;
            Exit (MakeTok (tkPlus, '+', ln, cl));
          end;
    '-' : begin
            Advance;
            if Peek = '%' then begin Advance;
              Exit (MakeTok (tkMinusWrap, '-%', ln, cl)) end;
            Exit (MakeTok (tkMinus, '-', ln, cl));
          end;
    '*' : begin
            Advance;
            if Peek = '%' then begin Advance;
              Exit (MakeTok (tkStarWrap, '*%', ln, cl)) end;
            Exit (MakeTok (tkStar, '*', ln, cl));
          end;
    '=' : begin Advance; Exit (MakeTok (tkEq, '=', ln, cl)) end;
    '#' : begin Advance; Exit (MakeTok (tkNeq, '#', ln, cl)) end;
    '/' : begin Advance; Exit (MakeTok (tkSlash, '/', ln, cl)) end;
    '(' : begin Advance; Exit (MakeTok (tkLParen, '(', ln, cl)) end;
    ')' : begin Advance; Exit (MakeTok (tkRParen, ')', ln, cl)) end;
    '[' : begin Advance; Exit (MakeTok (tkLBrack, '[', ln, cl)) end;
    ']' : begin Advance; Exit (MakeTok (tkRBrack, ']', ln, cl)) end;
    ',' : begin Advance; Exit (MakeTok (tkComma, ',', ln, cl)) end;
    ';' : begin Advance; Exit (MakeTok (tkSemi, ';', ln, cl)) end;
    '|' : begin Advance; Exit (MakeTok (tkBar, '|', ln, cl)) end;
    '^' : begin Advance; Exit (MakeTok (tkCaret, '^', ln, cl)) end;
  else
    begin
      Advance;
      if Ord (FSrc[start]) < $80 then
        Exit (MakeTok (tkError,
          Format ('unexpected character 0x%2.2x', [Ord (FSrc[start])]),
          ln, cl));
      { past ASCII the scalar the UTF-8 sequence spells, U+XXXX
        (mirrors Lex.Next, which reads the source decoded) }
      cv := Ord (FSrc[start]);
      if cv >= $F0 then cv := cv and $07
      else if cv >= $E0 then cv := cv and $0F
      else cv := cv and $1F;
      while (FPos <= Length (FSrc)) and ((Ord (FSrc[FPos]) and $C0) = $80) do
      begin
        cv := (cv shl 6) or (Ord (FSrc[FPos]) and $3F);
        Advance;
      end;
      if cv >= $100000 then
        Exit (MakeTok (tkError, 'unexpected character U+' + IntToHex (cv, 6), ln, cl))
      else if cv >= $10000 then
        Exit (MakeTok (tkError, 'unexpected character U+' + IntToHex (cv, 5), ln, cl));
      Exit (MakeTok (tkError, 'unexpected character U+' + IntToHex (cv, 4), ln, cl));
    end;
  end;
end;

end.
