import subprocess
import os
import sys

TOOLS_DIR = os.path.join(os.path.dirname(__file__), "tools_src")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "downloads")
os.makedirs(OUTPUT_DIR, exist_ok=True)

tools = [
    ("blue_magic_v65.py", "BlueMagicv6.5"),
    ("darkgpt.py", "DarkGPT"),
    ("blue_magic_panel.py", "BlueMagicPanel"),
    ("mullvad.py", "Mullvad"),
    ("volt_executor.py", "VoltExecutor"),
    ("arcane_fortnite.py", "ArcaneFortnite"),
    ("vanish.py", "Vanish"),
]

for script, name in tools:
    exe_path = os.path.join(OUTPUT_DIR, f"{name}.exe")
    if os.path.exists(exe_path):
        print(f"[SKIP] {name}.exe already exists.")
        continue

    script_path = os.path.join(TOOLS_DIR, script)
    print(f"\n{'='*50}")
    print(f"  Building: {name}")
    print(f"{'='*50}")
    
    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--onefile",
        "--noconsole",
        "--name", name,
        "--distpath", OUTPUT_DIR,
        "--workpath", os.path.join(os.path.dirname(__file__), "build_temp"),
        "--specpath", os.path.join(os.path.dirname(__file__), "build_temp"),
        script_path,
    ]
    
    result = subprocess.run(cmd, capture_output=False)
    if result.returncode == 0:
        print(f"  [OK] {name}.exe built successfully!")
    else:
        print(f"  [FAIL] {name}.exe FAILED!")

print(f"\n{'='*50}")
print(f"  All builds complete!")
print(f"  Output: {OUTPUT_DIR}")
print(f"{'='*50}")
