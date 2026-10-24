"""Run from this directory: python3 test_builders.py"""
import gzip
import json
import os
import sqlite3
import tempfile
import unittest

import build_jmdict
import build_kaikki_es

JMDICT = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE JMdict [
<!ENTITY v1 "Ichidan verb">
<!ENTITY vt "transitive verb">
<!ENTITY n "noun (common) (futsuumeishi)">
<!ENTITY uk "word usually written using kana alone">
]>
<!-- JMdict created: 2026-01-02 -->
<JMdict>
<entry>
<ent_seq>1</ent_seq>
<k_ele><keb>食べる</keb><ke_pri>ichi1</ke_pri></k_ele>
<r_ele><reb>たべる</reb><re_pri>ichi1</re_pri></r_ele>
<sense><pos>&v1;</pos><pos>&vt;</pos><gloss>to eat</gloss></sense>
<sense><gloss>to live on (e.g. a salary)</gloss><gloss>to live off</gloss></sense>
</entry>
<entry>
<ent_seq>2</ent_seq>
<k_ele><keb>綺麗</keb></k_ele>
<r_ele><reb>きれい</reb></r_ele>
<sense><pos>&n;</pos><misc>&uk;</misc><gloss>pretty &amp; clean</gloss></sense>
</entry>
<entry>
<ent_seq>3</ent_seq>
<k_ele><keb>日本</keb></k_ele>
<r_ele><reb>にほん</reb><re_restr>日本</re_restr></r_ele>
<r_ele><reb>にっぽん</reb></r_ele>
<r_ele><reb>ひのもと</reb><re_nokanji/></r_ele>
<sense><pos>&n;</pos><gloss>Japan</gloss></sense>
</entry>
<entry>
<ent_seq>4</ent_seq>
<r_ele><reb>ゆっくり</reb></r_ele>
<sense><gloss>slowly</gloss></sense>
</entry>
<entry>
<ent_seq>5</ent_seq>
<k_ele><keb>時</keb><ke_pri>ichi1</ke_pri></k_ele>
<k_ele><keb>秋</keb></k_ele>
<r_ele><reb>とき</reb><re_pri>ichi1</re_pri></r_ele>
<sense><pos>&n;</pos><gloss>time</gloss></sense>
</entry>
<entry>
<ent_seq>6</ent_seq>
<k_ele><keb>秋</keb><ke_pri>ichi1</ke_pri></k_ele>
<r_ele><reb>あき</reb><re_pri>ichi1</re_pri></r_ele>
<sense><pos>&n;</pos><gloss>autumn</gloss></sense>
</entry>
</JMdict>
"""


def rows(path):
    db = sqlite3.connect(path)
    try:
        return db.execute("SELECT headword, reading, gloss FROM entries ORDER BY id").fetchall()
    finally:
        db.close()


class JMdictTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.src = os.path.join(self.dir.name, "JMdict_e.gz")
        with gzip.open(self.src, "wt", encoding="utf-8") as f:
            f.write(JMDICT)
        self.out = os.path.join(self.dir.name, "ja.sqlite")
        build_jmdict.build(self.src, self.out)
        self.rows = rows(self.out)

    def tearDown(self):
        self.dir.cleanup()

    def test_common_entries_come_first(self):
        self.assertEqual(self.rows[0][:2], ("食べる", "たべる"))

    def test_glosses_are_numbered_with_pos_names_not_expansions(self):
        gloss = self.rows[0][2]
        self.assertEqual(gloss, "1. (v1, vt) to eat\n2. to live on (e.g. a salary); to live off")

    def test_standard_entities_still_decode(self):
        gloss = dict(((h, r), g) for h, r, g in self.rows)[("綺麗", "きれい")]
        self.assertIn("pretty & clean", gloss)

    def test_usually_kana_adds_kana_headword(self):
        self.assertIn(("きれい", "きれい"), [(h, r) for h, r, _ in self.rows])

    def test_kanji_only_entries_do_not_add_kana_headword(self):
        self.assertNotIn(("たべる", "たべる"), [(h, r) for h, r, _ in self.rows])

    def test_reading_restrictions_and_nokanji(self):
        pairs = [(h, r) for h, r, _ in self.rows if h == "日本"]
        self.assertEqual(sorted(pairs), [("日本", "にっぽん"), ("日本", "にほん")])
        self.assertNotIn("ひのもと", [r for _h, r, _g in self.rows])

    def test_kana_only_entry(self):
        self.assertIn(("ゆっくり", "ゆっくり"), [(h, r) for h, r, _ in self.rows])

    def test_lookups_are_indexed_because_the_app_reads_the_file_in_place(self):
        db = sqlite3.connect(self.out)
        try:
            indexes = {row[1] for row in db.execute("SELECT * FROM sqlite_master WHERE type = 'index'")}
            plan = " ".join(str(r) for r in db.execute(
                "EXPLAIN QUERY PLAN SELECT id FROM entries WHERE headword = ? OR reading = ?", ("x", "y")))
        finally:
            db.close()
        self.assertTrue({"entries_headword", "entries_reading"} <= indexes)
        self.assertIn("USING INDEX", plan)
        self.assertNotIn("SCAN entries", plan)

    def test_a_spelling_with_no_priority_of_its_own_does_not_outrank_the_real_word(self):
        # 時 (toki) lists 秋 as an alternate spelling with no priority; the autumn entry 秋 (aki) has its own.
        # A lookup takes the first row, so the readings of 秋 must come out aki first.
        readings = [r for h, r, _g in self.rows if h == "秋"]
        self.assertEqual(readings, ["あき", "とき"])
        toki = [r for h, r, _g in self.rows if h == "時"]
        self.assertEqual(toki, ["とき"], "the main spelling of 時 is unaffected")

    def test_meta(self):
        meta = dict(sqlite3.connect(self.out).execute("SELECT key, value FROM meta").fetchall())
        self.assertEqual(meta["source_created"], "2026-01-02")


class KaikkiTests(unittest.TestCase):
    def test_spanish_only_forms_dropped_and_merged(self):
        lines = [
            {"word": "casa", "lang_code": "es", "pos": "noun",
             "senses": [{"glosses": ["house"]}, {"glosses": ["home"]}, {"glosses": ["house", "household"]}]},
            {"word": "casa", "lang_code": "es", "pos": "verb",
             "senses": [{"glosses": ["to marry"]}, {"glosses": ["third-person form of casar"], "form_of": [{"word": "casar"}]}]},
            {"word": "casas", "lang_code": "es", "pos": "noun",
             "senses": [{"glosses": ["plural of casa"], "form_of": [{"word": "casa"}]}]},
            {"word": "house", "lang_code": "en", "pos": "noun", "senses": [{"glosses": ["a building"]}]},
        ]
        with tempfile.TemporaryDirectory() as d:
            src, out = os.path.join(d, "k.jsonl"), os.path.join(d, "es.sqlite")
            with open(src, "w", encoding="utf-8") as f:
                f.write("\n".join(json.dumps(x) for x in lines))
            self.assertEqual(build_kaikki_es.build(src, out), 1)
            self.assertEqual(rows(out), [("casa", None, "1. (noun) house; home; household\n2. (verb) to marry")])


if __name__ == "__main__":
    unittest.main()
