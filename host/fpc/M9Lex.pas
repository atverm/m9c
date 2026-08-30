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
    tkRAISE, tkRAISES, tkRECORD, tkRETURN, tkRO, tkSHARED, tkSIGNAL,
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
  Keywords : array [0..59] of TKw = (
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
    (s:'LOOP';k:tkLOOP), (s:'MOD';k:tkMOD), (s:'MODULE';k:tkMODULE),
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
  if Peek = #10 then
  begin
    Inc (FLine);
    FCol := 1;
  end
  else
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
        if isReal then
          Exit (MakeTok (tkRealLit, Copy (FSrc, start, FPos - start), ln, cl))
        else
          Exit (MakeTok (tkIntLit, Copy (FSrc, start, FPos - start), ln, cl));
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
      Exit (MakeTok (tkError,
        Format ('unexpected character 0x%2.2x', [Ord (FSrc[start])]),
        ln, cl));
    end;
  end;
end;

end.
