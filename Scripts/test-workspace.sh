#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
swift build
# Command Line Tools do not ship XCTest. Link the real debug target without its app entry point.
python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import subprocess,sys
root=Path(sys.argv[1])
binary=Path(subprocess.check_output(['swift','build','--show-bin-path'],text=True).strip())
sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
objects=[p for p in (binary/'Moi.product/Objects.LinkFileList').read_text().splitlines() if Path(p).name!='MoiApp.swift.o']
assert objects, 'Build target objects first'
subprocess.run(['swiftc','-parse-as-library','-sdk',sdk,'-module-cache-path',str(root/'.build/manual-module-cache'),'-I',str(binary/'Modules'),str(root/'Tests/WorkspaceTests.swift'),*objects,'-o',str(root/'.build/moi-workspace-tests')],check=True)
subprocess.run([str(root/'.build/moi-workspace-tests')],check=True)
PY
