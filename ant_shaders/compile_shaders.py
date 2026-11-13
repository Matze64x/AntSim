"""Compile every shader entry point in this directory to SPIR-V.

Compiles each entry point of the Slang files next to this script in parallel and reports which ones succeeded and which
failed; the `.spv` files are written to `bin/`. An entry point is a function marked with [shader("<stage>")], whose stage
is passed to slangc. This only validates the shaders: the engine compiles them itself at runtime.
"""

import os
import re
import shutil
import subprocess
import sys

WHITE = "\033[0m"
RED = "\033[91m"
GREEN = "\033[92m"
BOLD = "\033[1m"

# [shader("stage")], further attributes, then the function's return type and name
ENTRY_POINT = re.compile(r'\[shader\("(\w+)"\)\]\s*(?:\[[^\]]*\]\s*)*[\w<>:]+\s+(\w+)\s*\(')


def build_command(shader_dir, bin_dir, filename, stage, entry):
	in_path = os.path.join(shader_dir, filename)
	out_path = os.path.join(bin_dir, f"{filename}.{entry}.spv")
	# mirrors the search paths the engine itself adds: the shader root and the vkte-bundled shaders for `import vkte;`
	vkte_shader_dir = os.path.join(shader_dir, "..", "dependencies", "vkTurboEngine", "shaders", "vkte")
	return ["slangc", "-target", "spirv", "-emit-spirv-directly", "-profile", "spirv_1_5+all", "-fvk-use-scalar-layout", "-fvk-use-entrypoint-name", "-matrix-layout-column-major", "-I", shader_dir, "-I", vkte_shader_dir, "-entry", entry, "-stage", stage, "-o", out_path, in_path]


def main():
	shader_dir = os.path.dirname(os.path.realpath(__file__))
	# the files with entry points are those directly in this directory; include/ and shared/ hold modules
	shaders = sorted(f for f in os.listdir(shader_dir) if f.endswith(".slang") and os.path.isfile(os.path.join(shader_dir, f)))
	if shutil.which("slangc") is None:
		print(f"{RED}slangc not found on PATH{WHITE}", file=sys.stderr)
		return 1

	bin_dir = os.path.join(shader_dir, "bin")
	os.makedirs(bin_dir, exist_ok=True)

	jobs = []
	for filename in shaders:
		with open(os.path.join(shader_dir, filename)) as file:
			entry_points = ENTRY_POINT.findall(file.read())
		for stage, entry in entry_points:
			args = build_command(shader_dir, bin_dir, filename, stage, entry)
			proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
			jobs.append((f"{filename}:{entry}", proc))
	if not jobs:
		print("No shaders found.")
		return 0
	print(f"Compiling {len(jobs)} entry points into {os.path.relpath(bin_dir)}/...\n")

	results = []
	for name, proc in jobs:
		output, _ = proc.communicate()
		results.append((name, proc.returncode == 0, output))

	succeeded = [r for r in results if r[1]]
	failed = [r for r in results if not r[1]]

	for name, _, output in sorted(succeeded):
		print(f"{GREEN}  OK  {WHITE}{name}")
		# warnings
		if output.strip(): sys.stdout.write(output)
	for name, _, output in sorted(failed):
		print(f"{RED}{BOLD}FAIL  {name}{WHITE}")
		sys.stdout.write(output)

	print()
	summary_color = GREEN if not failed else RED
	print(f"{summary_color}{BOLD}{len(succeeded)}/{len(results)} entry points compiled successfully.{WHITE}")
	return 0 if not failed else 1


if __name__ == "__main__":
	sys.exit(main())
