"""Run: /usr/bin/python3 -m unittest discover -s ~/projects/personal-nix/skills/desk/tests"""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

DESK = Path(__file__).resolve().parent.parent / "bin" / "desk"
PY = "/usr/bin/python3"  # the launchd job runs on system python; keep 3.9-compatible


class DeskTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.now = "2026-09-30T09:00"  # Wednesday
        self.run_ok("init")
        self.run_ok("new-person", "Star Hall", "--email", "shall@apollomd.com", "--org", "ApolloMD")
        self.run_ok("new-person", "Tony Pereira", "--alias", "Anthony,Anthony Pereira", "--org", "ApolloMD")
        self.run_ok("new-project", "pace", "--title", "Pace", "--alias", "hermes")

    def tearDown(self):
        self.tmp.cleanup()

    def desk(self, *args, now=None):
        env = dict(os.environ, DESK_ROOT=str(self.root), DESK_NOW=now or self.now)
        return subprocess.run([PY, str(DESK), *args], capture_output=True, text=True, env=env)

    def run_ok(self, *args, now=None):
        r = self.desk(*args, now=now)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout

    def now_md(self):
        return (self.root / "NOW.md").read_text()

    def test_ids_increment_and_survive_archive(self):
        self.run_ok("add", "one")
        self.run_ok("add", "two")
        self.run_ok("done", "1")
        out = self.run_ok("add", "three")
        self.assertIn("T-0003", out)
        self.assertTrue(list(self.root.glob("tasks/done/2026-09/T-0001-*.md")))

    def test_fuzzy_people_and_projects(self):
        out = self.run_ok("add", "payroll export", "--people", "anthony", "--project", "hermes")
        self.assertIn("Tony Pereira", out)
        self.assertIn("pace", out)

    def test_unknown_person_refuses(self):
        r = self.desk("add", "x", "--people", "Mike")
        self.assertEqual(r.returncode, 3)
        self.assertIn("UNKNOWN person", r.stderr)
        self.assertFalse(list(self.root.glob("tasks/T-*.md")))

    def test_fifo_and_pin(self):
        self.run_ok("add", "first", "--priority", "P1", now="2026-09-30T09:00")
        self.run_ok("add", "second", "--priority", "P1", now="2026-09-30T09:05")
        self.run_ok("add", "third", "--priority", "P1", now="2026-09-30T09:10")
        now = self.now_md()
        self.assertLess(now.index("first"), now.index("second"))
        self.run_ok("top", "3", now="2026-09-30T10:00")
        now = self.now_md()
        self.assertLess(now.index("third"), now.index("first"))

    def test_due_soon_escalates_out_of_p2(self):
        self.run_ok("add", "far", "--priority", "P2", "--due", "2026-10-20")
        # Wed + 2 business days = Fri 10/02
        self.run_ok("add", "near", "--priority", "P2", "--due", "2026-10-02")
        now = self.now_md()
        due_block = now.split("## Due soon")[1].split("## P0")[0]
        self.assertIn("near", due_block)
        self.assertNotIn("far", due_block)
        p2_block = now.split("## P2")[1]
        self.assertNotIn("near", p2_block)

    def test_overdue_flag(self):
        self.run_ok("add", "late", "--priority", "P1", "--due", "2026-09-28")
        self.assertIn("OVERDUE", self.now_md())

    def test_suggested_p0_shows_at_top_without_promoting(self):
        out = self.run_ok("add", "feed down", "--suggest", "P0", "--reason", "outage")
        self.assertIn("⚠ suggests P0 (outage)", out)
        now = self.now_md()
        self.assertIn("Suggested P0", now)
        self.assertIn("- none", now.split("## P0")[1].split("## P1")[0])
        self.run_ok("set", "1", "priority=P0")
        self.assertNotIn("Suggested P0", self.now_md())

    def test_waiting_gets_nudge_not_priority(self):
        out = self.run_ok("add", "Star sends SOW", "--kind", "waiting", "--people", "Star")
        self.assertIn("nudge Mon 10/05", out)  # Wed + 3 business days
        r = self.desk("set", "1", "priority=P1")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("chase **Star Hall**", self.run_ok("render", now="2026-10-05T09:00"))

    def test_delegate_done_requires_handoff(self):
        self.run_ok("add", "ticket for export", "--kind", "delegate", "--priority", "P1")
        r = self.desk("done", "1")
        self.assertEqual(r.returncode, 4)
        out = self.run_ok("handoff", "1", "--to", "Tony", "--jira", "GDEV-9")
        self.assertIn("waiting", out)
        self.assertIn("GDEV-9", out)

    def test_ask_shows_in_prep(self):
        self.run_ok("add", "ask about budget", "--kind", "ask", "--people", "star")
        out = self.run_ok("prep", "star")
        self.assertIn("ask about budget", out.split("## Raise with them")[1].split("##")[0])

    def test_log_and_digest(self):
        self.run_ok("add", "ship thing", "--priority", "P1", "--project", "pace")
        self.run_ok("log", "1", "halfway")
        self.run_ok("done", "1", "shipped")
        out = self.run_ok("digest", "--since", "2026-09-28")
        self.assertIn("### pace", out)
        self.assertIn("halfway", out)

    def test_title_with_colon_roundtrips(self):
        self.run_ok("add", 'Fix: "quoted" thing # hash')
        self.assertIn('Fix: "quoted" thing # hash', self.run_ok("list"))
        self.run_ok("lint")

    def test_phi_scan(self):
        f = self.root / "t.txt"
        f.write_text("patient DOB 01/02/1980\nfine line\n")
        r = self.desk("phi-scan", str(f))
        self.assertEqual(r.returncode, 5)

    def test_stale(self):
        self.run_ok("add", "old", "--priority", "P1", now="2026-09-01T09:00")
        self.assertIn("still P1?", self.run_ok("stale"))


if __name__ == "__main__":
    unittest.main()
