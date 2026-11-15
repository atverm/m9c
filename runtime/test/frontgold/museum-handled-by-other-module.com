1:1-1 (* EXPECT-ERROR: unhandled RAISES ParseError from call to Json.Parse *)
2:1-7 (* Exception names were compared BARE.  A handler for one module's\n   ParseError was taken to catch another's, and a RAISES clause naming\n   one covered a call raising the other.  The compiler review observed\n   it 2026-10-21 (C6, C7, C8): a program handling `EB.Error' around a\n   call raising EA.Error compiled and died "unhandled Error".  Csv and\n   Json both declare a ParseError, which is the shape in the library. *)
comments=2
