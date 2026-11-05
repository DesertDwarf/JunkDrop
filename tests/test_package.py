"""Checks that the files and metadata that make up a release agree with each other."""
import glob
import os
import re
import unittest

from harness import ROOT, read, toc_lua_files


def toc_lines():
    return read(os.path.join(ROOT, "JunkDrop.toc")).splitlines()


def toc_header(key):
    for line in toc_lines():
        match = re.match(r"##\s*%s:\s*(.*)$" % re.escape(key), line.strip())
        if match:
            return match.group(1)
    return None


class Toc(unittest.TestCase):
    def test_every_file_the_toc_loads_exists(self):
        for line in toc_lines():
            line = line.strip().replace("\\", "/")
            if line and not line.startswith("#"):
                self.assertTrue(os.path.exists(os.path.join(ROOT, line)), "TOC lists a missing file: " + line)

    def test_every_lua_file_in_the_root_is_in_the_toc(self):
        in_root = {os.path.basename(p) for p in glob.glob(os.path.join(ROOT, "*.lua"))}
        self.assertEqual(in_root, set(toc_lua_files()))

    def test_interface_numbers_list_classic_era_first(self):
        numbers = [n.strip() for n in toc_header("Interface").split(",")]
        self.assertTrue(all(re.fullmatch(r"\d{5,6}", n) for n in numbers), numbers)
        # Older clients stop reading the line at the first comma, so the oldest must come first.
        self.assertEqual(numbers[0], "11509")
        self.assertEqual(numbers, sorted(numbers, key=int))

    def test_the_version_comes_from_the_release_tag(self):
        self.assertEqual(toc_header("Version"), "@project-version@")

    def test_the_curseforge_project_id_is_set(self):
        # The packager uploads to this project; a wrong or missing id publishes nowhere or elsewhere.
        self.assertEqual(toc_header("X-Curse-Project-ID"), "24848")

    def test_the_saved_variable_matches_the_code(self):
        self.assertEqual(toc_header("SavedVariables"), "JunkDropDB")


class Release(unittest.TestCase):
    def test_docs_exist(self):
        for name in ("README.md", "LICENSE", "CHANGELOG.md"):
            self.assertTrue(os.path.exists(os.path.join(ROOT, name)), name)

    def test_the_changelog_starts_with_a_version_heading(self):
        headings = [l for l in read(os.path.join(ROOT, "CHANGELOG.md")).splitlines() if l.startswith("## ")]
        self.assertRegex(headings[0], r"^## v\d+\.\d+\.\d+")

    def test_the_workflow_only_publishes_for_version_tags(self):
        workflow = read(os.path.join(ROOT, ".github", "workflows", "release.yml"))
        self.assertIn("- 'v*'", workflow)
        self.assertNotIn("- '**'", workflow)

    def test_repo_only_folders_stay_out_of_the_package(self):
        pkgmeta = read(os.path.join(ROOT, ".pkgmeta"))
        for folder in ("tools", "tests", "art", ".github"):
            self.assertRegex(pkgmeta, r"(?m)^\s*-\s*%s\s*$" % re.escape(folder))

    def test_the_machine_specific_deploy_list_is_not_committed(self):
        self.assertIn("tools/deploy-targets.txt", read(os.path.join(ROOT, ".gitignore")))


if __name__ == "__main__":
    unittest.main()
