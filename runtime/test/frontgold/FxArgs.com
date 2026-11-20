3:1-7 (* FxArgs holds the argument that is a slice in brackets (report par\n   2.2.5, 2026-11-19): alone, among other arguments, nested in a call\n   that is itself an element, and in a call statement.  A subscript\n   stays a subscript beside it.  The Pascal parser does not read the\n   form, so the record is the M9 side's own. *)
comments=1
