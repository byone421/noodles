"""Check recipe category migration and updates with SQLite, without Flutter."""
import re
import sqlite3
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / 'lib/core/database/recipe_repository.dart').read_text(encoding='utf-8')
db = sqlite3.connect(':memory:')
recipe_schema = re.search(r"'(CREATE TABLE recipes [^']+)'", source).group(1)
category_schema = re.search(r"'(CREATE TABLE recipe_categories [^']+)'", source).group(1)
db.execute(recipe_schema)
db.execute("INSERT INTO recipes VALUES ('r1', '家常面', '面食', '', NULL, 0, '2026-11-11', '2026-11-11')")
db.execute("INSERT INTO recipes VALUES ('r2', '自创菜', '自定义分类', '', NULL, 0, '2026-11-11', '2026-11-11')")
db.execute("INSERT INTO recipes VALUES ('r3', '带空格', ' 自定义分类 ', '', NULL, 0, '2026-11-11', '2026-11-11')")
db.execute("INSERT INTO recipes VALUES ('r4', '英文分类', 'dessert', '', NULL, 0, '2026-11-11', '2026-11-11')")
db.execute("INSERT INTO recipes VALUES ('r5', '大小写', ' DESSERT ', '', NULL, 0, '2026-11-11', '2026-11-11')")
db.execute("INSERT INTO recipes VALUES ('r6', '无分类', '   ', '', NULL, 0, '2026-11-11', '2026-11-11')")
db.execute(category_schema)
for name in ['家常菜', '快手菜', '面食', '汤羹', '烘焙']:
    db.execute('INSERT INTO recipe_categories VALUES (?)', (name,))
db.execute(re.search(r'"(INSERT OR IGNORE INTO recipe_categories[^"\n]+)"', source).group(1))
for sql in re.findall(r'"(UPDATE recipes SET category[^"\n]+)"', source):
    db.execute(sql)
assert db.execute('SELECT COUNT(*) FROM recipes').fetchone()[0] == 6
assert db.execute("SELECT COUNT(*) FROM recipe_categories WHERE name = '自定义分类'").fetchone()[0] == 1
assert db.execute('SELECT COUNT(*) FROM recipe_categories').fetchone()[0] == 7
assert db.execute("SELECT category FROM recipes WHERE id = 'r3'").fetchone()[0] == '自定义分类'
assert db.execute("SELECT category FROM recipes WHERE id = 'r4'").fetchone()[0] == db.execute("SELECT category FROM recipes WHERE id = 'r5'").fetchone()[0]
assert db.execute("SELECT category FROM recipes WHERE id = 'r6'").fetchone()[0] == '未分类'
db.commit()

with db:
    db.execute('UPDATE recipe_categories SET name = ? WHERE name = ?', ('主食', '面食'))
    db.execute('UPDATE recipes SET category = ? WHERE category = ?', ('主食', '面食'))
assert db.execute("SELECT category FROM recipes WHERE id = 'r1'").fetchone()[0] == '主食'
try:
    db.execute("INSERT INTO recipe_categories VALUES ('主食')")
    raise AssertionError('Duplicate category allowed')
except sqlite3.IntegrityError:
    pass
with db:
    db.execute('UPDATE recipes SET category = ? WHERE category = ?', ('未分类', '主食'))
    db.execute('DELETE FROM recipe_categories WHERE name = ?', ('主食',))
assert db.execute('SELECT COUNT(*) FROM recipes').fetchone()[0] == 6
assert db.execute("SELECT category FROM recipes WHERE id = 'r1'").fetchone()[0] == '未分类'
assert 'if (oldVersion < 3) await _createRecipeCategories(db);' in source
db.close()
print('PASS: v3 category migration preserves recipes and custom categories; rename, uniqueness and delete-to-uncategorized')
