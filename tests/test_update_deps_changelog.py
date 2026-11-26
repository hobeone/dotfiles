#!/usr/bin/env python3
"""Offline unit tests for home/bin/update-deps-changelog."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import pathlib
import unittest
from unittest import mock

SCRIPT_PATH = pathlib.Path(__file__).resolve().parent.parent / "home" / "bin" / "update-deps-changelog"


def load_module():
    loader = importlib.machinery.SourceFileLoader("update_deps_changelog", str(SCRIPT_PATH))
    spec = importlib.util.spec_from_loader("update_deps_changelog", loader)
    assert spec is not None
    mod = importlib.util.module_from_spec(spec)
    import sys
    sys.modules[spec.name] = mod
    loader.exec_module(mod)
    return mod


M = load_module()


class ParseDiffTests(unittest.TestCase):
    def test_parse_go_mod_diff(self):
        diff = "\n".join([
            "--- a/go.mod",
            "+++ b/go.mod",
            "-go 1.25.0",
            "+go 1.25.1",
            "-\tgithub.com/pressly/goose/v3 v3.30.1",
            "+\tgithub.com/pressly/goose/v3 v3.30.2",
            "-\tgithub.com/sethvargo/go-retry v0.5.0 // indirect",
            "+\tgolang.org/x/net v0.35.0 // indirect",
        ])
        changes = M.parse_go_mod_diff(diff)
        by_name = {c.name: c for c in changes}
        self.assertEqual(by_name["go"].old_ver, "1.25.0")
        self.assertEqual(by_name["go"].new_ver, "1.25.1")
        self.assertTrue(by_name["go"].is_go_runtime)

        self.assertEqual(by_name["github.com/pressly/goose/v3"].kind, "updated")
        self.assertTrue(by_name["github.com/pressly/goose/v3"].direct)

        self.assertEqual(by_name["github.com/sethvargo/go-retry"].kind, "removed")
        self.assertFalse(by_name["github.com/sethvargo/go-retry"].direct)

        self.assertEqual(by_name["golang.org/x/net"].kind, "added")
        self.assertFalse(by_name["golang.org/x/net"].direct)

    def test_parse_bun_lock_diff_and_normalize(self):
        self.assertEqual(M.normalize_bun_pkg_name("svelte"), "svelte")
        self.assertEqual(M.normalize_bun_pkg_name("@sveltejs/kit"), "@sveltejs/kit")
        self.assertEqual(M.normalize_bun_pkg_name("rolldown/@oxc-project/types"), "@oxc-project/types")
        self.assertEqual(M.normalize_bun_pkg_name("svelte/devalue"), "devalue")

        diff = "\n".join([
            "--- a/ui/bun.lock",
            "+++ b/ui/bun.lock",
            '-    "svelte": ["svelte@5.58.0", "", {}, "sha512-a"],',
            '+    "svelte": ["svelte@5.59.2", "", {}, "sha512-b"],',
            '-    "obug": ["obug@2.2.1", "", {}, "sha512-c"],',
            '+    "obug": ["obug@3.0.0", "", {}, "sha512-d"],',
        ])
        changes = M.parse_bun_lock_diff(diff, {"svelte"})
        by_name = {c.name: c for c in changes}
        self.assertTrue(by_name["svelte"].direct)
        self.assertFalse(by_name["svelte"].is_major_bump)
        self.assertFalse(by_name["obug"].direct)
        self.assertTrue(by_name["obug"].is_major_bump)


class TagAndChangelogTests(unittest.TestCase):
    def test_extract_version_from_tag(self):
        self.assertEqual(M.extract_version_from_tag("v8.4.0", "vite", "vite"), "8.4.0")
        self.assertIsNone(M.extract_version_from_tag("create-vite@9.4.0", "vite", "vite"))
        self.assertEqual(M.extract_version_from_tag("svelte@5.59.2", "svelte", "svelte"), "5.59.2")
        self.assertEqual(
            M.extract_version_from_tag("@sveltejs/kit@3.4.1", "@sveltejs/kit", "kit"),
            "3.4.1",
        )
        self.assertIsNone(
            M.extract_version_from_tag("@sveltejs/adapter-node@5.0.0", "@sveltejs/kit", "kit")
        )

    def test_parse_markdown_changelog_range_sqlite_style(self):
        changelog = """# Changelog

 - 2026-11-22 v1.63.0:
     - **A zero-length BLOB now reads as an empty `[]byte` instead of nil**
     - **Fix a crash in the pre-update hook on a row SQLite cannot read.**

 - 2026-11-07 v1.62.0:
     - Old release note that should not be included.
"""
        matched = M.parse_markdown_changelog_range(changelog, "v1.62.0", "v1.63.0")
        self.assertEqual(len(matched), 1)
        self.assertEqual(matched[0][0], "1.63.0")
        self.assertIn("Fix a crash", matched[0][1])

    def test_extract_highlights_classification_and_false_positive_guard(self):
        dep = M.DepChange(ecosystem="npm", name="demo", old_ver="1.0.0", new_ver="1.1.0")
        body = """
### Fixes
- Fix XSS vulnerability in template rendering (CVE-2026-9999)
- Fix brackets inside quoted values breaking class parsing
- breaking: remove legacy `foo` option
- Fix nil pointer crash when closing connection &nbsp;-&nbsp; <samp>(abc123)</samp>
- chore(deps): bump foo to 2.0.0
- browser:
- Add new color token
"""
        hs = M.extract_highlights_from_body(dep, body, "v1.1.0", "https://example.com")
        cats = {h.text: h.category for h in hs}
        self.assertEqual(cats["Fix XSS vulnerability in template rendering (CVE-2026-9999)"], "security")
        self.assertEqual(cats["Fix brackets inside quoted values breaking class parsing"], "notable")
        self.assertEqual(cats["breaking: remove legacy `foo` option"], "breaking")
        self.assertEqual(cats["Fix nil pointer crash when closing connection"], "critical")
        self.assertEqual(cats["Add new color token"], "notable")
        # Noise and stub subheading must be filtered out
        self.assertTrue(all("chore(deps)" not in t for t in cats))
        self.assertTrue(all(t != "browser:" for t in cats))


class OsvSecurityTests(unittest.TestCase):
    def test_osv_fixed_remaining_dedup_and_priority(self):
        deps = [
            M.DepChange(ecosystem="npm", name="vite", old_ver="6.0.0", new_ver="6.1.0", direct=True),
            M.DepChange(ecosystem="Go", name="go", old_ver="1.25.0", new_ver="1.25.1", direct=True, is_go_runtime=True),
        ]
        batch_resp = {
            "results": [
                # vite old: has GHSA-crit and GHSA-still
                {"vulns": [{"id": "GHSA-crit"}, {"id": "GHSA-still"}]},
                # vite new: GHSA-crit fixed, GHSA-still remains
                {"vulns": [{"id": "GHSA-still"}]},
                # go stdlib old: has GO-2026-1 and GHSA-dup (same CVE!)
                {"vulns": [{"id": "GO-2026-1"}, {"id": "GHSA-dup"}]},
                # go stdlib new: both fixed
                {"vulns": []},
            ]
        }
        vuln_details = {
            "GHSA-crit": {
                "id": "GHSA-crit",
                "aliases": ["CVE-2026-1111"],
                "database_specific": {"severity": "CRITICAL"},
                "summary": "Arbitrary file read in dev server",
            },
            "GHSA-still": {
                "id": "GHSA-still",
                "aliases": ["CVE-2026-2222"],
                "database_specific": {"severity": "LOW"},
                "summary": "Minor info leak",
            },
            "GO-2026-1": {
                "id": "GO-2026-1",
                "aliases": ["CVE-2026-3333"],
                "database_specific": {"severity": "HIGH"},
                "summary": "net/http request smuggling",
            },
            "GHSA-dup": {
                "id": "GHSA-dup",
                "aliases": ["CVE-2026-3333"],
                "database_specific": {"severity": "HIGH"},
                "summary": "net/http request smuggling duplicate",
            },
        }

        def fake_get(url, headers=None, timeout=10):
            vid = url.rsplit("/", 1)[-1]
            return vuln_details.get(vid)

        with mock.patch.object(M, "http_post_json", return_value=batch_resp), \
             mock.patch.object(M, "http_get_json", side_effect=fake_get):
            fixed, remaining = M.query_osv_security(deps)

        # Duplicate CVE-2026-3333 must be merged, and CRITICAL must sort ahead of HIGH.
        self.assertEqual(len(fixed), 2)
        self.assertEqual(fixed[0].severity, "CRITICAL")
        self.assertEqual(fixed[0].dep_name, "vite")
        self.assertEqual(fixed[1].severity, "HIGH")
        self.assertEqual(fixed[1].dep_name, "go")

        self.assertEqual(len(remaining), 1)
        self.assertEqual(remaining[0].vuln_id, "GHSA-still")

        # Security fixes must appear at the very top of the formatted report.
        rep = M.format_report(deps, fixed, remaining, [], use_color=False)
        sec_idx = rep.index("=== SECURITY FIXES ===")
        rem_idx = rep.index("=== WARNING: REMAINING VULNERABILITIES")
        self.assertLess(sec_idx, rem_idx)
        self.assertIn("[CRITICAL] vite (6.0.0 -> 6.1.0): GHSA-crit / CVE-2026-1111", rep)

        commit_sec = M.format_commit_security_summary(fixed)
        self.assertIn("Security fixes (2):", commit_sec)
        self.assertIn("[CRITICAL] vite: GHSA-crit / CVE-2026-1111", commit_sec)


if __name__ == "__main__":
    unittest.main()
