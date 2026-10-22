# Snug

Private menu bar manager. Build: `./build.sh` → `build/Snug.app`. Build log: ~/Documents/Dex/06-Resources/Snug/SNUG-LOG.md

Keep a build log for this project at SNUG-LOG.md, and maintain it as we work.

WHAT IT'S FOR

Working docs (CLAUDE.md, README) describe what's true now and get pruned when
something is superseded, which is correct for working and useless for looking
back. Git history has what changed but not why. This file holds the rest:
decisions, what we got wrong, and what the numbers were at the time.

Assume I'll use it to reflect on the project and possibly write publicly about
it. It's raw material for me, not a finished account. My framing goes on top
later; yours should stay out of the way.

RECORD, DON'T DRAMATISE

This is the rule that matters most, because the failure mode is subtle.

Write down what happened and what it cost. Don't narrate it. No "the day
everything changed", no "a hard-won lesson", no calling a normal bug a crisis or
a normal week a turning point. If something took three attempts, say it took
three attempts. That's more interesting than any adjective, and it lets me
decide later whether it was a big deal.

Specifically:
  - Prefer numbers to intensifiers. "Cost 4 hours and one destructive migration"
    over "a painful detour".
  - No superlatives about the project's trajectory. You don't know yet.
  - Don't editorialise my decisions, and don't praise them.
  - Section headings should say what the entry contains, not sell it.

ENTRY FORMAT

One entry per working session, dated, newest at the bottom. Scannable first,
prose only where prose earns it.

  ## YYYY-MM-DD

  **Shipped**
  - One line each. What now exists that didn't before.

  **Decisions**
  - What was decided, what was rejected, and the reason. Include mine and yours.

  **Went wrong**
  - Wrong turns, surprising bugs, wasted work. Name the cause, and the cost in
    time, money or rework. Include your own mistakes. This is the section that's
    worth reading later and the one you'll be tempted to skip.

  **Numbers**
  - Anything measurable: users, cost per operation, spend, conversion, timings.
    Unrecoverable if not written down now.

  **Quips**
  - Whatever I said in passing that is worth keeping, one line each, in my
    words. A reaction, a half-formed reason, a thing I noticed. These are not
    decisions and must not be tidied into them: a quip is evidence of what I
    thought at the time, and the value is in it being unfinished.

  **Open**
  - Carried forward: unresolved questions, known risks, things waiting on me.

Omit any section with nothing real in it. An empty "Went wrong" is fine; a
padded one is not.

ASK ME THINGS

At the end of a working session, write the entry and show me a short recap: what
shipped, what's open, what needs me next. Keep it to something I can read in
twenty seconds.

Ask in the moment, rather than at session end, when you notice:
  - I made a call you don't fully understand the reasoning for. Get the reason
    while I still remember it.
  - Something didn't work and I seemed to have a view on why.
  - I changed direction. Capture what prompted it, not just the new direction.

USE THE WAIT. The best moment to ask is the one where I am already waiting:
a build running, a test suite, a long install, a subagent working. Say the
question then, in one line, and carry on with the work while I answer or
don't. That beat costs me nothing, which is the whole reason it is the right
one -- an interruption during work is a tax on the work, and the same question
asked while I watch a progress bar is free.

One question, not a list. If I do not answer, do not ask again in that gap and
do not ask a second time later; it was not worth an interruption or it would
have been asked as one.

Tell me once in a session, the first time such a gap comes up, that I can note
something myself without stopping:

    familiar quip "the box-sizing thing was mine, not Tailwind's"

Once. It goes into today's entry under Quips. A tool that reminds you it exists
every time you might use it has become the thing it was supposed to save you
from.

COMPACTION

When the session is compacted, treat it as a real event worth recording rather
than a housekeeping blip. Before the context is summarised away, append a dated
entry closing out what the compaction is compressing, headed
"## YYYY-MM-DD (compacted)". Keep it to what a future reader would actually
need. The compaction summary is a view; the log entry is the record. If nothing
happened since the last entry, append a one-line Open carry-forward rather than
padding.

MAINTENANCE

  - Append-only. Never edit or delete an earlier entry to tidy the history. A
    corrected entry loses the mistake, which was the point of keeping it.
  - Write entries as part of the work, not batched at the end. The reasoning is
    gone by then, and the reasoning is what this is for.
  - Plain language. No "leveraged", "streamlined", "robust". If a thing broke,
    say it broke.
  - If there's history before today, reconstruct a skeleton from git log and
    file history, but mark those entries as reconstructed. They record what
    happened and not why, and that difference matters.
  - Keep a note in the working doc pointing here, so this doesn't get orphaned.
