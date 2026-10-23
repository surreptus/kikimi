"""Shared output format for the dictionary builders.

Each built file is a SQLite database with:
  entries(id INTEGER PRIMARY KEY, headword TEXT, reading TEXT, gloss TEXT)
  meta(key TEXT PRIMARY KEY, value TEXT)

Rows are inserted most-useful-first, so `ORDER BY id` is the display order. There is no language column: the
app assigns the language of the profile that owns the file when it imports it.
"""
import os
import sqlite3

MAX_SENSES = 10


def format_senses(senses):
    """senses: list of (label, [glosses]). A label is shown only when it changes from the previous sense."""
    lines, previous = [], None
    for number, (label, glosses) in enumerate(senses[:MAX_SENSES], start=1):
        text = "; ".join(glosses)
        prefix = f"({label}) " if label and label != previous else ""
        previous = label or previous
        lines.append(f"{number}. {prefix}{text}")
    return "\n".join(lines)


def write_database(path, rows, meta):
    """rows: iterable of (headword, reading_or_None, gloss) in display order."""
    if os.path.exists(path):
        os.remove(path)
    db = sqlite3.connect(path)
    db.execute("PRAGMA journal_mode = DELETE")
    db.execute("CREATE TABLE entries (id INTEGER PRIMARY KEY, headword TEXT NOT NULL, reading TEXT, gloss TEXT NOT NULL)")
    db.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    db.executemany("INSERT INTO entries (headword, reading, gloss) VALUES (?, ?, ?)", rows)
    db.executemany("INSERT INTO meta VALUES (?, ?)", sorted(meta.items()))
    db.commit()
    count = db.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
    db.execute("VACUUM")
    db.close()
    return count
