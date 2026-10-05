/* gui.c -- the M9 GUI example's whole foreign boundary: native widgets
   through libui-ng (Cocoa on macOS, Win32 on Windows, GTK 3 on Linux),
   offered to M9 as plain ints.

   Three choices make the M9 side safe code, with no ADR and no UNSAFE:

   - a widget is a small number, its index in this file's table, so no
     pointer ever crosses the boundary;
   - text crosses one byte at a time: gui_put appends a byte to the
     OUT buffer, which the next call that takes text uses (a title, a
     label); gui_get_text copies a widget's text into the IN buffer,
     which gui_byte reads back;
   - a click is an EVENT, queued here and answered by gui_next, which
     runs libui's loop until there is one.  Nothing in C calls into M9,
     so an M9 procedure never runs on a C stack it cannot see.

   Text is UTF-8 both ways.  Every procedure is [SERIAL] in the M9
   declaration: this file has state, and a GUI has one thread. */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "ui.h"

#define MAXW 64                  /* widgets */
#define MAXT 4096                /* bytes of text either way */
#define MAXQ 64                  /* queued events */

enum { KLabel, KEntry, KButton };

static uiWindow *win;
static uiBox *box;
static int nw;
static int kind[MAXW];
static uiControl *ctl[MAXW];

static char out[MAXT + 1];       /* text M9 is handing over */
static int nout;
static char in[MAXT + 1];        /* text M9 is reading back */
static int nin;

static int queue[MAXQ];
static int qhead, qtail;

static void push (int ev)
{
  if ((qtail + 1) % MAXQ != qhead) { queue[qtail] = ev; qtail = (qtail + 1) % MAXQ; }
}

static int onClosing (uiWindow *w, void *data)
{
  (void) w; (void) data;
  push (-1);
  uiQuit ();
  return 1;                      /* let libui destroy the window */
}

static void onClicked (uiButton *b, void *data)
{
  (void) b;
  push ((int) (intptr_t) data);
}

/* the OUT buffer, as a C string, and emptied for the next text */
static const char *take (void)
{
  out[nout] = 0;
  nout = 0;
  return out;
}

void gui_put (int byte)
{
  if (nout < MAXT) out[nout++] = (char) byte;
}

/* the window, titled with the OUT text, holding one vertical box that
   every widget is appended to.  0, or -1 when the platform's GUI
   cannot start (no display, say) */
int gui_open (int width, int height)
{
  uiInitOptions o;
  memset (&o, 0, sizeof o);
  const char *err = uiInit (&o);
  if (err != NULL) { uiFreeInitError (err); return -1; }
  win = uiNewWindow (take (), width, height, 0);
  uiWindowSetMargined (win, 1);
  uiWindowOnClosing (win, onClosing, NULL);
  box = uiNewVerticalBox ();
  uiBoxSetPadded (box, 1);
  uiWindowSetChild (win, uiControl (box));
  return 0;
}

static int add (int k, uiControl *c)
{
  if (nw == MAXW) return -1;
  kind[nw] = k;
  ctl[nw] = c;
  uiBoxAppend (box, c, 0);
  return nw++;
}

/* a label, a one-line entry, a button: each with the OUT text, each
   answering its number (a button's number is the event its click
   queues) */
int gui_label (void)  { return add (KLabel, uiControl (uiNewLabel (take ()))); }

int gui_entry (void)
{
  uiEntry *e = uiNewEntry ();
  uiEntrySetText (e, take ());
  return add (KEntry, uiControl (e));
}

int gui_button (void)
{
  uiButton *b = uiNewButton (take ());
  int id = add (KButton, uiControl (b));
  uiButtonOnClicked (b, onClicked, (void *) (intptr_t) id);
  return id;
}

/* the widget's text becomes the OUT text; 0, or -1 for no such widget
   or one without settable text */
int gui_set_text (int id)
{
  const char *t = take ();
  if (id < 0 || id >= nw) return -1;
  switch (kind[id]) {
  case KLabel: uiLabelSetText (uiLabel (ctl[id]), t); return 0;
  case KEntry: uiEntrySetText (uiEntry (ctl[id]), t); return 0;
  default: return -1;
  }
}

/* the widget's text into the IN buffer: its length in bytes, -1 for
   no such widget or one without text to read */
int gui_get_text (int id)
{
  char *t;
  if (id < 0 || id >= nw) return -1;
  if (kind[id] == KEntry) t = uiEntryText (uiEntry (ctl[id]));
  else if (kind[id] == KLabel) t = uiLabelText (uiLabel (ctl[id]));
  else return -1;
  nin = (int) strlen (t);
  if (nin > MAXT) nin = MAXT;
  memcpy (in, t, (size_t) nin);
  uiFreeText (t);
  return nin;
}

/* byte i of the IN text, -1 past its end */
int gui_byte (int i)
{
  return (i >= 0 && i < nin) ? (unsigned char) in[i] : -1;
}

void gui_show (void)
{
  uiControlShow (uiControl (win));
  uiMainSteps ();
}

/* the next event: a button's number, or -1 when the window has been
   closed.  Runs the platform's event loop, waiting, until there is
   one. */
int gui_next (void)
{
  while (qhead == qtail) {
    if (!uiMainStep (1)) { push (-1); break; }
  }
  int ev = queue[qhead];
  qhead = (qhead + 1) % MAXQ;
  if (ev == -1) { uiUninit (); qhead = qtail = 0; }
  return ev;
}
