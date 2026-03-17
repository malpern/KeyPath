import io
import tarfile
import unittest
from unittest import mock

from Scripts.generate_keyboard_detection_index import (
    MAX_FETCH_BYTES,
    DetectionRecord,
    GenerationError,
    build_override_records,
    derive_qmk_path_from_via_member,
    format_hex,
    load_via_exact_records,
    merge_exact_records,
)


def make_via_tarball(files):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        for name, payload in files.items():
            encoded = payload.encode()
            info = tarfile.TarInfo(name=f"the-via-keyboards-sha/{name}")
            info.size = len(encoded)
            archive.addfile(info, io.BytesIO(encoded))
    return buffer.getvalue()


class GenerateKeyboardDetectionIndexTests(unittest.TestCase):
    def test_format_hex_rejects_malformed_ids(self):
        with self.assertRaises(GenerationError):
            format_hex("0xZZZZ", field="vendorId", context="fixture")

    def test_format_hex_rejects_out_of_range_values(self):
        with self.assertRaises(GenerationError):
            format_hex(0x1_0000, field="vendorId", context="fixture")
        with self.assertRaises(GenerationError):
            format_hex("0x10000", field="productId", context="fixture")

    def test_via_loader_parses_representative_definitions(self):
        tarball = make_via_tarball({
            "v3/crkbd/crkbd.json": '{"name":"Crkbd","vendorId":"0x4653","productId":"0x0001"}',
            "v3/boardsource/unicorne/unicorne.json": '{"name":"Unicorne","vendorId":"0x1209","productId":"0x2303"}',
        })
        metadata = {
            "crkbd": {"name": "Corne", "manufacturer": "foostan"},
            "boardsource/unicorne": {"name": "Unicorne", "manufacturer": "Boardsource"},
        }
        aliases = {"crkbd": "corne"}

        with mock.patch("Scripts.generate_keyboard_detection_index.fetch_via_revision", return_value="deadbeef"), \
             mock.patch("Scripts.generate_keyboard_detection_index.fetch_url_bytes", return_value=tarball):
            resolved, stats = load_via_exact_records(metadata, aliases)

        self.assertEqual(stats["parsedFiles"], 2)
        self.assertIn("4653:0001", resolved)
        self.assertEqual(resolved["4653:0001"].qmk_path, "crkbd")
        self.assertEqual(resolved["4653:0001"].built_in_layout_id, "corne")
        self.assertEqual(resolved["1209:2303"].qmk_path, "boardsource/unicorne")

    def test_derive_qmk_path_from_via_member_prefers_directory_path(self):
        self.assertEqual(derive_qmk_path_from_via_member("the-via-keyboards-sha/v3/wavtype/p01_ultra/via.json"), "wavtype/p01_ultra")
        self.assertEqual(derive_qmk_path_from_via_member("the-via-keyboards-sha/v3/bakeneko60.json"), "bakeneko60")

    def test_merge_prefers_override_then_via_then_qmk(self):
        qmk = {
            "4653:0001": DetectionRecord(
                match_key="4653:0001",
                match_type="exactVIDPID",
                source="qmk",
                confidence="high",
                display_name="Sofle Rev1",
                manufacturer=None,
                qmk_path="sofle/rev1",
                built_in_layout_id="sofle",
            )
        }
        via = {
            "4653:0001": DetectionRecord(
                match_key="4653:0001",
                match_type="exactVIDPID",
                source="via",
                confidence="high",
                display_name="Sofle",
                manufacturer=None,
                qmk_path="sofle",
                built_in_layout_id="sofle",
            )
        }
        override = build_override_records(
            [{
                "vendorId": "0x4653",
                "productId": "0x0001",
                "displayName": "Sofle Override",
                "qmkPath": "sofle",
                "builtInLayoutId": "sofle",
            }],
            {"sofle": "sofle"},
        )

        merged, conflicts, unresolved = merge_exact_records(qmk, via, override)

        self.assertEqual(merged["4653:0001"].source, "override")
        self.assertEqual(merged["4653:0001"].display_name, "Sofle Override")
        self.assertEqual(len(conflicts), 2)
        self.assertEqual(unresolved, [])

    def test_fetch_url_bytes_enforces_size_limit(self):
        too_large = b"x" * (MAX_FETCH_BYTES + 1)

        class Response:
            def __enter__(self):
                self.offset = 0
                return self

            def __exit__(self, exc_type, exc, tb):
                return False

            def read(self, size):
                if self.offset >= len(too_large):
                    return b""
                chunk = too_large[self.offset:self.offset + size]
                self.offset += len(chunk)
                return chunk

        with mock.patch("Scripts.generate_keyboard_detection_index.urllib.request.urlopen", return_value=Response()):
            from Scripts.generate_keyboard_detection_index import fetch_url_bytes

            with self.assertRaises(GenerationError):
                fetch_url_bytes("https://example.com/big.tar.gz")


if __name__ == "__main__":
    unittest.main()
