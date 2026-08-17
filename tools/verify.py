#!/usr/bin/env python3
"""Compile every black-hole shader mode through a headless OpenGL context."""

import argparse
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile


REPO = Path(__file__).resolve().parents[1]
HEADER = """#version 430 core
layout(std140, binding = 0) uniform Globals {
    vec3 iResolution;
    float iTime;
    float iTimeFocus;
    float iTimeCursorChange;
    int iFocus;
    vec4 iDate;
    vec4 iCurrentCursorColor;
    vec4 iPreviousCursorColor;
};
layout(binding = 0) uniform sampler2D iChannel0;
"""
FOOTER = """out vec4 _outColor;
void main() { mainImage(_outColor, gl_FragCoord.xy); }
"""

MODES = (
    ("POMODORO", "MODE_POMODORO"),
    ("TOKENS", "MODE_TOKENS"),
    ("DEMO", "MODE_DEMO"),
)
QUALITIES = (
    ("LIGHTWEIGHT", "QUALITY_LIGHTWEIGHT"),
    ("BALANCED", "QUALITY_BALANCED"),
    ("MAXIMUM", "QUALITY_MAXIMUM"),
)


def replace_define(source: str, name: str, value: str) -> str:
    result, count = re.subn(
        rf"^#define[ \t]+{re.escape(name)}[ \t]+.*$",
        f"#define {name} {value}",
        source,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise ValueError(f"expected exactly one #define {name}, found {count}")
    return result


def build_glcheck(output: Path) -> None:
    flags = subprocess.run(
        ["pkg-config", "--cflags", "--libs", "egl", "gl"],
        check=True,
        text=True,
        capture_output=True,
    ).stdout
    subprocess.run(
        [
            os.environ.get("CC", "cc"),
            "-O2",
            "-Wall",
            "-Wextra",
            str(REPO / "tools" / "glcheck.c"),
            "-o",
            str(output),
            *shlex.split(flags),
        ],
        check=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shader", type=Path, default=REPO / "blackhole.glsl")
    parser.add_argument(
        "--glcheck",
        type=Path,
        help="prebuilt tools/glcheck executable (built temporarily if omitted)",
    )
    args = parser.parse_args()

    source = args.shader.resolve().read_text()
    failed = False
    environment = os.environ.copy()
    environment.setdefault("EGL_PLATFORM", "surfaceless")

    with tempfile.TemporaryDirectory(prefix="blackhole-verify-") as temp_name:
        temp = Path(temp_name)
        glcheck = args.glcheck.resolve() if args.glcheck else temp / "glcheck"
        if not glcheck.is_file():
            if args.glcheck:
                parser.error(f"glcheck executable not found: {glcheck}")
            build_glcheck(glcheck)

        for mode_name, mode_value in MODES:
            for quality_name, quality_value in QUALITIES:
                for cinematic in (0, 1):
                    for y_down in (0, 1):
                        variant = replace_define(source, "SIZE_MODE", mode_value)
                        variant = replace_define(
                            variant, "QUALITY_LEVEL", quality_value
                        )
                        variant = replace_define(
                            variant, "CINEMATIC", str(cinematic)
                        )
                        variant = replace_define(
                            variant, "GHOSTTY_Y_DOWN", str(y_down)
                        )
                        shader_path = temp / "variant.frag"
                        shader_path.write_text(HEADER + variant + FOOTER)
                        result = subprocess.run(
                            [str(glcheck), str(shader_path)],
                            text=True,
                            capture_output=True,
                            env=environment,
                        )
                        tag = (
                            f"MODE_{mode_name} QUALITY_{quality_name} "
                            f"CINEMATIC={cinematic} Y_DOWN={y_down}"
                        )
                        if result.returncode:
                            failed = True
                            detail = result.stderr.strip() or result.stdout.strip()
                            print("FAIL", tag, detail)
                        else:
                            print("PASS", tag)

    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
