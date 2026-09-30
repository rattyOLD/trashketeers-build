import re
import sys
import collections
import openpyxl

rows = [r for r in openpyxl.load_workbook(sys.argv[1]).active.iter_rows(values_only=True) if r and r[0]]
kinds = collections.Counter(r[1] for r in rows)
print("Записей:", len(rows), dict(kinds))

sessions = collections.defaultdict(list)
for r in rows:
    m = re.match(r"\[(\w+) \+(\d+)s\]", str(r[3]))
    if m:
        sessions[m.group(1)].append((int(m.group(2)), r[1], str(r[3])))
print("Сессий:", len(sessions), " с корректным концом:", sum(1 for v in sessions.values() if any(k == "session_end" for _, k, _ in v)))

print("\nFPS по перф-отчётам:")
for r in rows:
    if r[1] == "perf":
        m = re.search(r"fps avg (\d+), 1% low (\d+) \| (\w+) hero=(\w+).*?draws=(\d+)", str(r[3]))
        if m:
            print("  ", m.group(3), m.group(4), "avg", m.group(1), "low", m.group(2), "draws", m.group(5))

print("\nСрабатывания авто-качества:", sum(1 for r in rows if r[1] == "adapt"))
print("\nЗабеги:")
for r in rows:
    if r[1] == "run":
        print("  ", str(r[3]).split("\n")[0][:220])
print("\nСмерти вкладки в бою:", sum(1 for r in rows if r[1] == "prev_session_died"))
print("\nОшибки:")
for text, n in collections.Counter(str(r[3]).split("] ", 1)[-1].split("\n")[0][:120] for r in rows if r[1] == "error").most_common(10):
    print("  ", n, text)
print("\nЗагрузка:")
for r in rows:
    if r[1] == "load":
        print("  ", str(r[3]).split("\n")[0][:200])
