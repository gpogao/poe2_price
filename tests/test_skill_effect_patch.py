import importlib.util
import sys
import unittest
import zipfile
from pathlib import Path
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "特效补丁" / "tools" / "poe2_skill_effect_patch.py"


def load_module():
    spec = importlib.util.spec_from_file_location("skill_effect_patch", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class StubFileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def test_stubs_loaded_for_known_extensions(self):
        stubs = self.module._load_stubs()
        self.assertIn(".pet", stubs)
        self.assertIn(".epk", stubs)
        self.assertIn(".trl", stubs)
        self.assertEqual(len(stubs[".pet"]), 14)
        self.assertEqual(len(stubs[".epk"]), 2)
        self.assertEqual(len(stubs[".trl"]), 14)

    def test_stub_for_pet_path(self):
        stubs = self.module._load_stubs()
        result = self.module._stub_for_path(
            "metadata/particles/arc/end.pet", stubs
        )
        self.assertIsNotNone(result)
        self.assertEqual(len(result), 14)

    def test_stub_for_epk_path(self):
        stubs = self.module._load_stubs()
        result = self.module._stub_for_path(
            "metadata/effects/spells/arc_03/archit.epk", stubs
        )
        self.assertIsNotNone(result)
        self.assertEqual(len(result), 2)

    def test_stub_for_trl_path(self):
        stubs = self.module._load_stubs()
        result = self.module._stub_for_path(
            "metadata/particles/monster_effects/lightning_bolt.trl", stubs
        )
        self.assertIsNotNone(result)
        self.assertEqual(len(result), 14)

    def test_no_stub_for_ao_path(self):
        stubs = self.module._load_stubs()
        result = self.module._stub_for_path(
            "metadata/characters/dex/dex.ao", stubs
        )
        self.assertIsNone(result)

    def test_no_stub_for_unknown_extension(self):
        stubs = self.module._load_stubs()
        result = self.module._stub_for_path(
            "some/random/file.txt", stubs
        )
        self.assertIsNone(result)


class ScopeResolutionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def test_all_returns_all_scopes(self):
        scopes = self.module._resolve_scopes("all")
        self.assertEqual(len(scopes), len(self.module.ALL_SCOPES))
        for s in self.module.ALL_SCOPES:
            self.assertIn(s, scopes)

    def test_single_scope(self):
        scopes = self.module._resolve_scopes("spells")
        self.assertEqual(scopes, ["spells"])

    def test_comma_separated_scopes(self):
        scopes = self.module._resolve_scopes("spells,mtx,monsters")
        self.assertEqual(scopes, ["spells", "mtx", "monsters"])

    def test_comma_separated_with_spaces(self):
        scopes = self.module._resolve_scopes("spells, mtx , monsters")
        self.assertEqual(scopes, ["spells", "mtx", "monsters"])

    def test_invalid_scope_raises(self):
        with self.assertRaises(ValueError):
            self.module._resolve_scopes("invalid_scope")


class BuildPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def test_build_spells_only_creates_zip(self):
        with TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / "test_effect.zip"
            report_path = Path(tmp) / "report.json"
            self.module.build_patch(
                scopes=["spells"],
                output_zip=zip_path,
                report=report_path,
            )
            self.assertTrue(zip_path.is_file())
            self.assertTrue(report_path.is_file())
            with zipfile.ZipFile(zip_path, "r") as zf:
                names = zf.namelist()
                self.assertGreater(len(names), 0)
                # All entries should be under metadata/effects/spells/
                for name in names:
                    self.assertTrue(
                        name.startswith("metadata/effects/spells/"),
                        f"unexpected path: {name}",
                    )
                    # All should be .pet, .epk, or .trl
                    self.assertTrue(
                        name.endswith((".pet", ".epk", ".trl")),
                        f"unexpected extension: {name}",
                    )

    def test_build_all_scopes(self):
        with TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / "test_all.zip"
            self.module.build_patch(
                scopes=list(self.module.ALL_SCOPES),
                output_zip=zip_path,
                report=None,
            )
            self.assertTrue(zip_path.is_file())
            with zipfile.ZipFile(zip_path, "r") as zf:
                count = len(zf.infolist())
                self.assertGreater(count, 10000)

    def test_deduplicate_paths(self):
        """Same path across multiple scopes should only appear once."""
        with TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / "test_dedup.zip"
            # spells and monsters have no overlap, but test with two calls
            self.module.build_patch(
                scopes=["spells", "mtx"],
                output_zip=zip_path,
                report=None,
            )
            with zipfile.ZipFile(zip_path, "r") as zf:
                names = zf.namelist()
                self.assertEqual(len(names), len(set(names)))


class CleanPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def test_clean_removes_effect_entries(self):
        with TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / "test_clean.zip"
            # Build patch first
            self.module.build_patch(
                scopes=["spells"],
                output_zip=zip_path,
                report=None,
            )
            before_count = 0
            with zipfile.ZipFile(zip_path, "r") as zf:
                before_count = len(zf.infolist())
            self.assertGreater(before_count, 0)

            # Clean spells scope
            self.module.clean_patch(
                scopes=["spells"],
                output_zip=zip_path,
                report=None,
            )
            with zipfile.ZipFile(zip_path, "r") as zf:
                after_count = len(zf.infolist())
            self.assertEqual(after_count, 0)

    def test_clean_nonexistent_zip_is_noop(self):
        with TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / "nonexistent.zip"
            # Should not raise
            self.module.clean_patch(
                scopes=["spells"],
                output_zip=zip_path,
                report=None,
            )


if __name__ == "__main__":
    unittest.main()
