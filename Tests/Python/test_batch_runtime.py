"""Regression tests for the actual embedded batch Python (no MLX needed)."""
import ast
from pathlib import Path
import subprocess
import tempfile
import unittest

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
