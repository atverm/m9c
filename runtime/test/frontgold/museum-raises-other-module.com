1:1-1 (* EXPECT-ERROR: unhandled RAISES ParseError from call to Json.Parse *)
2:1-6 (* A RAISES clause naming one module's exception covered a call raising\n   another module's of the same name: the accounting compared bare\n   names.  The compiler review observed it 2026-10-21 (C7), and the same\n   day the zarr proxy showed it: Grid.Build declares `RAISES Error', its\n   own, and let Attrs.Error through. *)
comments=2
