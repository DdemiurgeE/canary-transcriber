"""Regression tests for the actual embedded batch Python (no MLX needed)."""
import ast
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys
import types
import wave
from unittest.mock import patch


class GigaAMRuntimeTests(unittest.TestCase):
    def run_adapter(self, frames, timestamps=False, failure=None):
        calls = []
        cache_clears = []
        temp_paths = []

        def transcribe(path, word_timestamps=False):
            with wave.open(str(path), "rb") as audio:
                count = audio.getnframes()
                data = audio.readframes(count)
            calls.append((count, data, word_timestamps))
            temp_paths.append(Path(path))
            if count > 25 * 16000:
                raise ValueError("Too long wav file, use 'transcribe_longform' method.")
            if count <= 200:
                raise RuntimeError("Padding size should be less than input dimension")
            if failure:
                raise failure
            return types.SimpleNamespace(text=f"part{len(calls)}")

        torch = types.SimpleNamespace(
            backends=types.SimpleNamespace(mps=types.SimpleNamespace(is_available=lambda: True)),
            mps=types.SimpleNamespace(empty_cache=lambda: cache_clears.append(True)))
        model = types.SimpleNamespace(transcribe=transcribe)
        gigaam = types.SimpleNamespace(load_model=lambda *a, **kw: model)
        env = {"profile_id": "russian-gigaam-v3", "language": "ru", "timestamps": timestamps,
               "resolve_cached_model": lambda name: name, "Path": Path,
               "tempfile": tempfile, "wave": wave}
        load_functions(["make_transcriber"], env)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.wav"
            # Non-silent deterministic PCM verifies no dropped/duplicated frames.
            data = bytes(range(256)) * ((frames * 2 + 255) // 256)
            data = data[:frames * 2]
            with wave.open(str(source), "wb") as audio:
                audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                audio.writeframes(data)
            with patch.dict(sys.modules, {"torch": torch, "gigaam": gigaam}):
                adapter = env["make_transcriber"]("gigaam", "v3_e2e_rnnt")
                if failure:
                    with self.assertRaisesRegex(type(failure), str(failure)):
                        adapter(source)
                    result = None
                else:
                    result = adapter(source)
            self.assertEqual(source.read_bytes()[44:], data)
            self.assertEqual(b"".join(call[1] for call in calls), data if not failure else calls[0][1])
            self.assertTrue(all(call[2] == timestamps for call in calls))
        self.assertTrue(all(not path.exists() for path in temp_paths))
        return result, calls, cache_clears

    def test_short_audio_uses_one_call(self):
        result, calls, _ = self.run_adapter(10 * 16000)
        self.assertEqual(result, "part1")
        self.assertEqual(len(calls), 1)

    def test_default_30_second_chunk_is_bounded(self):
        result, calls, _ = self.run_adapter(30 * 16000)
        self.assertEqual(result, "part1\npart2")
        self.assertTrue(all(call[0] <= 20 * 16000 for call in calls))

    def test_speaker_segment_over_limit_is_bounded(self):
        result, calls, _ = self.run_adapter(25 * 16000 + 1, timestamps=True)
        self.assertEqual(len(calls), 2)
        self.assertEqual(result, "part1\npart2")

    def test_unchunked_audio_preserves_final_partial_frame(self):
        result, calls, clears = self.run_adapter(81 * 16000 + 1)
        self.assertEqual(len(calls), 5)
        self.assertEqual(len(clears), 5)
        self.assertEqual(result, "part1\npart2\npart3\npart4\npart5")

    def test_one_frame_tail_after_20_seconds_is_rebalanced(self):
        _, calls, _ = self.run_adapter(20 * 16000 + 1)
        self.assertEqual(len(calls), 2)
        self.assertTrue(all(200 < call[0] <= 20 * 16000 for call in calls))

    def test_one_frame_tail_after_40_seconds_is_rebalanced(self):
        _, calls, _ = self.run_adapter(40 * 16000 + 1)
        self.assertEqual(len(calls), 3)
        self.assertTrue(all(200 < call[0] <= 20 * 16000 for call in calls))

    def test_exact_20_second_boundary_uses_one_call(self):
        _, calls, _ = self.run_adapter(20 * 16000)
        self.assertEqual(len(calls), 1)

    def test_failure_is_not_swallowed_and_cleans_resources(self):
        _, _, clears = self.run_adapter(30 * 16000, failure=RuntimeError("decoder failed"))
        self.assertEqual(len(clears), 1)

SOURCE = Path(__file__).resolve().parents[2] / "Sources/CanaryTranscriberLib/TranscriptionViewModel.swift"
SCRIPT = SOURCE.read_text().split('let script = #"""', 1)[1].split('"""#', 1)[0]
TREE = ast.parse(SCRIPT)
FUNCTIONS = {node.name: node for node in ast.walk(TREE) if isinstance(node, ast.FunctionDef)}


def load_functions(names, environment):
    nodes = [FUNCTIONS[name] for name in names]
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(SOURCE), "exec"), environment)


class BatchRuntimeTests(unittest.TestCase):
    def test_memory_retry_resolves_ffmpeg_and_transcribes_both_halves(self):
        calls = []
        commands = []

        def transcribe(path):
            calls.append(str(path))
            if len(calls) == 1:
                raise RuntimeError("Insufficient Memory")
            return "first" if len(calls) == 2 else "second"

        class SubprocessFixture:
            DEVNULL = subprocess.DEVNULL

            @staticmethod
            def run(command, **kwargs):
                commands.append(command)

        env = {"Path": Path, "subprocess": SubprocessFixture,
               "transcribe_chunk": transcribe,
               "resolve_ffmpeg": lambda: "/fixture/ffmpeg",
               "FFMPEG_CHUNK_TIMEOUT_SECONDS": 180}
        load_functions(["is_memory_failure", "transcribe_with_bounded_retry"], env)
        actual = env["transcribe_with_bounded_retry"]("chunk.wav", 10, 40, "/tmp", "chunk")
        self.assertEqual(actual, "first\nsecond")
        self.assertEqual(len(commands), 2)
        self.assertEqual([cmd[0] for cmd in commands], ["/fixture/ffmpeg"] * 2)
        self.assertEqual([cmd[cmd.index("-ss") + 1] for cmd in commands], ["10", "25.0"])


if __name__ == "__main__":
    unittest.main()
