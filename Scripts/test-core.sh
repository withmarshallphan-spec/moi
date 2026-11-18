#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SDK_PATH="${MOI_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
MODULE_CACHE="$ROOT_DIR/.build/manual-module-cache"
mkdir -p "$MODULE_CACHE"

swiftc \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR/Sources/MoiApp/Models/Models.swift" \
  "$ROOT_DIR/Sources/MoiApp/Models/SeedData.swift" \
  "$ROOT_DIR/Sources/MoiApp/Services/ScheduleEngine.swift" \
  "$ROOT_DIR/Sources/MoiApp/Services/NotificationIdentity.swift" \
  "$ROOT_DIR/Sources/MoiApp/Services/NextUpEngine.swift" \
  "$ROOT_DIR/Sources/MoiApp/Services/DayAnswers.swift" \
  "$ROOT_DIR/Sources/MoiApp/Services/MoiVoice.swift" \
  "$ROOT_DIR/Sources/MoiApp/Services/MoiPersona.swift" \
  "$ROOT_DIR/Sources/MoiApp/Services/DesktopTidy.swift" \
  "$ROOT_DIR/Sources/MoiApp/Services/MoiCommand.swift" \
  "$ROOT_DIR/Sources/MoiApp/Services/MacModels.swift" \
  "$ROOT_DIR/Sources/MoiApp/Services/BrainChain.swift" \
  "$ROOT_DIR/Sources/MoiApp/Services/DeadlinePlaybook.swift" \
  "$ROOT_DIR/Sources/MoiApp/Services/ReminderVoice.swift" \
  "$ROOT_DIR/Sources/MoiApp/Models/QuickAddParser.swift" \
  "$ROOT_DIR/Tests/CoreFixtures.swift" \
  "$ROOT_DIR/Tests/CoreTests.swift" \
  -o "$ROOT_DIR/.build/moi-core-tests"

"$ROOT_DIR/.build/moi-core-tests"
