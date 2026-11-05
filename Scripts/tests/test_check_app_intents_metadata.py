import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "check_app_intents_metadata", ROOT / "Scripts/check-app-intents-metadata.py"
)
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)

SOURCES = {
    "A.swift": "struct GetThing: AppIntent {\n}\n",
    "B.swift": "public struct DoThing: Sendable, AppIntent {\n}\n",
    "C.swift": "struct ThingEntity: AppEntity {\n}\nenum Mode: String, AppEnum {\n}\n",
    "D.swift": "struct Shortcuts: AppShortcutsProvider {\n}\nstruct NotAnIntent: View {\n}\n",
    "E.swift": "@available(macOS 26, *)\npublic struct OpenThing<T>: OpenIntent {\n}\n"
    "extension Kind: AppEnum {\n}\n",
}

COMPLETE = {
    "actions": {"GetThing": {}, "DoThing": {}, "OpenThing": {}},
    "entities": {"ThingEntity": {}},
    "enums": [{"identifier": "Mode"}, {"identifier": "Kind"}],
    "autoShortcutProviderMangledName": "4Test9ShortcutsV",
    "autoShortcuts": [{}],
}


class CheckAppIntentsMetadataTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name)
        self.sources = self.root / "Sources"
        self.sources.mkdir()
        for name, text in SOURCES.items():
            (self.sources / name).write_text(text)

    def tearDown(self):
        self.directory.cleanup()

    def run_check(self, extract):
        path = self.root / "extract.actionsdata"
        path.write_text(json.dumps(extract))
        return checker.main(["check", str(path), str(self.sources)])

    def test_finds_declared_types(self):
        declared = checker.declared_types(self.sources)
        self.assertEqual(sorted(declared["AppIntent"]), ["DoThing", "GetThing", "OpenThing"])
        self.assertEqual(declared["AppEntity"], ["ThingEntity"])
        self.assertEqual(sorted(declared["AppEnum"]), ["Kind", "Mode"])
        self.assertEqual(declared["AppShortcutsProvider"], ["Shortcuts"])

    def test_complete_extract_passes(self):
        self.assertEqual(self.run_check(COMPLETE), 0)

    def test_missing_intent_fails(self):
        extract = dict(COMPLETE, actions={"GetThing": {}})
        self.assertEqual(self.run_check(extract), 1)

    def test_missing_entity_or_enum_fails(self):
        self.assertEqual(self.run_check(dict(COMPLETE, entities={})), 1)
        self.assertEqual(self.run_check(dict(COMPLETE, enums=[])), 1)

    def test_missing_shortcuts_provider_fails(self):
        extract = dict(COMPLETE, autoShortcutProviderMangledName="", autoShortcuts=[])
        self.assertEqual(self.run_check(extract), 1)

    def test_unreadable_extract_fails(self):
        path = self.root / "extract.actionsdata"
        path.write_text("not json")
        self.assertEqual(checker.main(["check", str(path), str(self.sources)]), 1)


if __name__ == "__main__":
    unittest.main()
