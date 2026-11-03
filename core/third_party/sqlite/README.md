# SQLite

The SQLite 3.53.4 amalgamation, from https://sqlite.org/2026/sqlite-amalgamation-3530400.zip, backing the 3.x library store. #282 removes it along with the store.

Included: `sqlite3.c` and `sqlite3.h`. Excluded: `shell.c` and `sqlite3ext.h`. The compile options are in `CMakeLists.txt` here; the archive hashes are in `pinned-inputs.json`.
