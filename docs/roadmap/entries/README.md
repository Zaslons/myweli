# Roadmap entries — one file per change

Every merged change adds **one new file** here instead of editing a shared list.

```
docs/roadmap/entries/YYYY-MM-DD-<short-slug>.md
```

The file holds the entry exactly as it reads in the log, starting with its
status marker:

```markdown
- 🟢 **What changed, and where (area, YYYY-MM-DD).** The prose, in French,
  saying what was wrong, what it cost, what was measured rather than assumed,
  and which mutations were watched red.
```

Read the whole log, newest first:

```bash
./tool/roadmap-log.sh          # everything
./tool/roadmap-log.sh 2026-08  # one month
```

## Why one file per entry

Because the old convention put every entry at the **same line** of the same
file. `docs/ROADMAP.md` §1.8 is newest-first, so each pull request inserted at
the top — and every rebase therefore conflicted, guaranteed, every time. On
2026-08-23 that happened on nine consecutive merges, and twice the resolution
went wrong in the same way: a shell line ran `git add` after a failed assertion
and committed the conflict markers.

Two branches adding two differently-named files cannot conflict. That is the
whole idea; there is nothing else to it.

**Entries before 2026-08-24 stay in `docs/ROADMAP.md` §1.8.** They are not
migrated — three hundred entries of history rewritten in one commit would be a
worse thing to review than the problem it fixes. The list there is closed, and
carries a pointer to this directory.
