"""Run the app's SQL against SQLite: python test/inventory_database_check.py."""
import re
import sqlite3
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
inventory = (root / 'lib/core/database/inventory_repository.dart').read_text(encoding='utf-8')
recipes = (root / 'lib/core/database/recipe_repository.dart').read_text(encoding='utf-8')

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'migration.db'
    db = sqlite3.connect(path)
    db.execute('PRAGMA foreign_keys = ON')
    # Start with the existing recipe schema and data, then apply v2 additions.
    for sql in re.findall(r"'(CREATE TABLE [^']+)'", recipes):
        db.execute(sql)
    db.execute("INSERT INTO recipes VALUES ('recipe', '面条', '面食', '', NULL, 0, '2026-11-11', '2026-11-11')")
    for sql in re.findall(r"'(CREATE (?:TABLE|INDEX) [^']+)'", inventory):
        db.execute(sql)
    db.execute('INSERT INTO inventory_settings VALUES (1, 7, 15, 30)')
    db.execute("INSERT INTO inventory_categories VALUES (1, '厨房', '食材', 0)")
    db.execute("INSERT INTO inventory_categories VALUES (2, '日常用品', '', 1)")
    values = ('牛奶', '2026-11-18', 1, '冰箱', '2 瓶', '2026-11-11', '7', '天', None, '12.50', '冷藏', '[]')
    insert = 'INSERT INTO inventory_items(name, expiry_date, category_id, location, quantity, production_date, storage_duration, storage_unit, purchase_date, purchase_price, remark, image_paths) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)'
    db.execute(insert, values)
    db.execute(insert, values)
    queries = re.findall(r"'(SELECT [^']+)'", inventory)
    item_sql = next(sql for sql in queries if sql.startswith('SELECT i.*'))
    category_sql = next(sql for sql in queries if sql.startswith('SELECT c.*'))
    assert [row[-1] for row in db.execute(item_sql)] == ['厨房', '厨房']
    assert [row[-1] for row in db.execute(category_sql)] == [2, 0]
    db.execute("UPDATE inventory_categories SET name = '厨房食材' WHERE id = 1")
    assert db.execute(item_sql).fetchone()[-1] == '厨房食材'
    try:
        db.execute("INSERT INTO inventory_categories VALUES (3, '厨房食材', '', 0)")
        raise AssertionError('duplicate category accepted')
    except sqlite3.IntegrityError:
        pass
    try:
        db.execute('UPDATE inventory_settings SET near_days = 20 WHERE id = 1')
        raise AssertionError('invalid reminder order accepted')
    except sqlite3.IntegrityError:
        pass
    db.execute('UPDATE inventory_settings SET near_days = 3 WHERE id = 1')
    db.execute('DELETE FROM inventory_categories WHERE id = 1')
    assert db.execute('SELECT COUNT(*) FROM inventory_items WHERE category_id IS NULL').fetchone()[0] == 2
    assert all(row[-1] is None for row in db.execute(item_sql))
    db.commit()
    db.close()
    db = sqlite3.connect(path)
    assert db.execute('SELECT title FROM recipes').fetchone()[0] == '面条'
    assert db.execute('SELECT COUNT(*) FROM inventory_items').fetchone()[0] == 2
    assert db.execute('SELECT near_days FROM inventory_settings').fetchone()[0] == 3
    assert not db.execute('PRAGMA foreign_key_check').fetchall()
    db.close()

print('PASS: migration preserves recipes; joins, counts, rename, duplicate/range constraints, category deletion and reopen persistence')
