# Milk Family: Usage and Privacy

Requires macOS 14 or later. Current version: 1.0.0, build 22.

## Getting started

Choose a common companion, then claim its first action card manually in Shop. Growth starts after that first draw. New saves use English; Settings lets you switch to Chinese. Updates preserve your existing language and progress. The regular and test apps use separate saves.

The app reads local Codex and Claude Code usage logs every 15 seconds. Existing history establishes a statistics baseline; only new actual usage adds growth. If no logs are found, choose the corresponding log folder in Settings and refresh. The app does not invent usage when logs are unavailable.

Each Milk Candy adds 150 Tokens of separate hatch progress. It does not add actual usage, coins or draws. When a usage increment finishes an egg, its remaining Tokens grow the newly hatched companion. Lowering difficulty can finish an egg immediately if its existing progress meets the new requirement. Earned actions stay unlocked.

## Desktop companion

Drag to move the companion, including partly into screen edges. Click to open the panel; right-click to choose an unlocked action. Positions are constrained again after a display is disconnected. You can also choose “Bring companion back on screen” in Settings or the menu bar's right-click menu.

The app respects macOS Reduce Motion and Reduce Transparency. With reduced motion, sprite and card effects pause. With reduced transparency, the panel uses a solid background.

## Local data and recovery

Regular saves: `~/Library/Application Support/奶家族/`.

Test saves: `~/Library/Application Support/奶家/`. Developer tools use a separate test save. Actual usage during a developer test is not later replayed as live growth.

Saved data includes companions, actions, cards, inventory, settings, an actual-usage deduplication ledger and a local cache of usage metadata and file offsets. The runtime has no network interface for uploading these records. The usage cache does not store prompts, response text, credentials or complete source log lines. Selected extra log folders and window positions are stored in the app's local preferences.

Before committing a changed save, the previous valid transaction is retained in `正式存档.上次有效.json`. The developer test save also has its own previous valid version. Reading a save does not rewrite it. If the primary save becomes unreadable and a valid backup exists, startup offers recovery. Restoring preserves the damaged file in `恢复前存档/` and can roll back the most recent operation. Without a valid backup, the app offers access to the save folder; it does not silently create an empty replacement.

Additional local update backups are kept in `~/Library/Application Support/奶家族更新备份/`. They are not included in application bundles or source checks.

## Uninstalling and reporting issues

Quit the app, then remove its App from `~/Applications/` and any desktop links. Save folders remain by default. You may remove the corresponding data and update-backup folders yourself when no longer needed. Source Codex and Claude Code logs are unaffected.

For issue reports, record the app version, page and reproduction steps. Remove private content and local paths before sharing screenshots or logs. Report issues at https://github.com/jaysoncbh/MilkFamily/issues.

## Current scope

The library contains 32 characters, 179 static actions and 175 cards. All 179 actions now have continuous animations, with 912 playback frames. The new batch of 79 groups and 466 frames is complete and visually checked, including 捧腹大笑 for all 32 characters. One-shot actions hold their final frame; looping actions follow their recorded timing. The installed builds use local ad-hoc signatures. Source is MIT-licensed; media rights are listed separately. Apple notarization and independent clean-Mac download acceptance are not complete.


## Home usage chart

Home shows today, this week, this month and all-time actual Tokens, followed by daily bars for the current calendar month. Weeks start on Monday. Dates use the local timezone; all-time includes available deduplicated local history. Hover or click a day for its exact count. Future days do not contain usage. These statistics include history from before installation and are separate from game growth rewards. Developer test Tokens do not affect the chart. No price estimate is inferred.

## 1.0.0 build 22

Added English interface names for 10 newer companions and eight special actions; all 32 companion names are checked in both languages. Original lettering inside card art is preserved. Source is MIT-licensed; artwork and display media require separate distribution review.
