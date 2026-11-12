"""Exercise the actual photo schema, v5 migration, cover query and cascades."""
import json
import re
import sqlite3
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / 'lib/core/database/recipe_repository.dart').read_text(encoding='utf-8')

def schema(table):
    return re.search(rf'''(["'])(CREATE TABLE {table} .*?)\1''', source).group(2)

migration = re.search(r'"(ALTER TABLE finished_records .*?)"', source).group(1)
cover = re.search(r"'(SELECT f.image_path FROM finished_records .*?LIMIT 1)'", source).group(1)

def setup(legacy=False):
    db = sqlite3.connect(':memory:')
    db.execute('PRAGMA foreign_keys = ON')
    for table in ('recipes', 'recipe_versions', 'ingredients', 'cooking_steps', 'finished_records'):
        sql = schema(table)
        if legacy and table == 'finished_records':
            sql = sql.replace("image_paths TEXT NOT NULL DEFAULT '[]', ", '')
        db.execute(sql)
    db.execute("INSERT INTO recipes VALUES ('r', '菜谱', '未分类', '', NULL, 0, '2026-11-12', '2026-11-12')")
    for number in (1, 2):
        db.execute("INSERT INTO recipe_versions VALUES (?, 'r', ?, '版本', '', NULL, 0, '2026-11-12', '2026-11-12')", (f'v{number}', number))
    return db

old = setup(legacy=True)
old.execute("INSERT INTO finished_records VALUES ('old', 'v1', 'legacy.jpg', 4.5, '反馈', '改进', '2026-11-12')")
old.execute(migration)
row = old.execute('SELECT image_path, image_paths, rating, note FROM finished_records').fetchone()
assert row == ('legacy.jpg', '[]', 4.5, '反馈'), row
assert old.execute(cover, ('r',)).fetchone()[0] == 'legacy.jpg'
old.close()

db = setup()
paths = [f'{i}.jpg' for i in range(5)]
for number in (1, 2):
    db.execute('INSERT INTO finished_records VALUES (?, ?, ?, ?, 4.5, ?, ?, ?)', (f'f{number}', f'v{number}', paths[0], json.dumps(paths), '反馈', '改进', f'2026-11-{10+number}'))
assert json.loads(db.execute("SELECT image_paths FROM finished_records WHERE id='f1'").fetchone()[0]) == paths
assert db.execute(cover, ('r',)).fetchone()[0] == paths[0]
db.commit()
try:
    with db:
        db.execute("DELETE FROM finished_records WHERE version_id='v2'")
        db.execute("INSERT INTO finished_records VALUES ('bad', 'missing', NULL, '[]', NULL, '', '', '2026-11-12')")
except sqlite3.IntegrityError:
    pass
else:
    raise AssertionError('Invalid version reference accepted')
assert db.execute("SELECT COUNT(*) FROM finished_records WHERE version_id='v2'").fetchone()[0] == 1
db.execute("DELETE FROM recipe_versions WHERE id='v2'")
assert db.execute(cover, ('r',)).fetchone()[0] == paths[0]
assert db.execute('SELECT COUNT(*) FROM finished_records').fetchone()[0] == 1
db.execute("DELETE FROM recipes WHERE id='r'")
assert db.execute('SELECT COUNT(*) FROM finished_records').fetchone()[0] == 0
db.close()
print('PASS: v5 migration, five-photo storage, cover selection, transaction rollback and cascades')
