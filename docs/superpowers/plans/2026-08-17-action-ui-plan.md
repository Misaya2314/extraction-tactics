# 行动模式 UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为原型战术场景增加底部“移动/攻击”行动栏，并让行动模式分别过滤蓝色移动高亮和红色攻击高亮。

**Architecture:** 在现有 `PrototypeController` 内增加一个轻量的行动模式状态，不改变移动、攻击、AP、射程和视线的底层执行器。现有 `MoveHighlights` 与 `AttackHighlights` 继续作为两个独立的 3D 层，底部 HUD 通过两个按钮调用控制器的模式切换方法。

**Tech Stack:** Godot 4.7、强类型 GDScript、现有 SceneTree headless integration tests。

---

### Task 1: Add failing integration coverage for action modes

**Files:**
- Modify: `tests/integration/move_highlights_test.gd`

- [x] **Step 1: Write the failing assertions**

Add tests that instantiate `prototype_main.tscn`, assert that a selected player starts in `MOVE` mode, and verify that `_set_action_mode` changes visibility so only the selected mode's highlight layer is visible. Add a click guard test that places a visible enemy in range, confirms a movement-mode click does not spend AP or damage the enemy, then switches to attack mode and confirms the same click can attack.

- [x] **Step 2: Run the focused test and verify the failure**

Run:

```powershell
& 'D:\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/integration/move_highlights_test.gd
```

Expected: the test fails because `ACTION_MODE_MOVE`, `ACTION_MODE_ATTACK`, and `_set_action_mode` are not yet implemented and the current refresh shows both tactical highlight layers.

### Task 2: Implement controller action-mode state and filtered highlights

**Files:**
- Modify: `scripts/gameplay/prototype_controller.gd`

- [x] **Step 1: Add typed mode constants, state, and button references**

Add `ACTION_MODE_MOVE`/`ACTION_MODE_ATTACK`, default the `action_mode` to move, and add typed `@onready` references for the two HUD buttons and their action bar. Connect both buttons in `_ready()`.

- [x] **Step 2: Implement mode switching and button state refresh**

Add `_set_action_mode(mode: int)`, `_on_move_action_pressed()`, `_on_attack_action_pressed()`, and `_refresh_action_bar()`. Reject invalid modes, update button pressed states, and disable both buttons unless a living player unit is selected during a player-action phase with the corresponding AP cost available.

- [x] **Step 3: Filter `_refresh_highlights()` by the current mode**

Keep object visibility, vision overlay, and enemy range overlay behavior unchanged. Set `MoveHighlights.visible` only for move mode and `AttackHighlights.visible` only for attack mode. Generate reachable cells only in move mode and visible in-range enemies only in attack mode.

- [x] **Step 4: Make cell clicks obey the selected mode**

Keep unit selection and existing loot/extraction handling. In move mode, only reachable cells call `_try_move_selected`; in attack mode, only an enemy whose cell is currently attack-highlighted calls `_attack_with_unit`. A click on the wrong kind of target must not issue the other action.

- [x] **Step 5: Preserve mode after selection and action while refreshing UI**

Selecting another player resets to move mode as specified. Movement/attack completion calls the existing refresh path and leaves the current mode intact. All paths that clear selection or reach a terminal state refresh the action bar.

### Task 3: Add the bottom action bar to the main scene

**Files:**
- Modify: `scenes/main/prototype_main.tscn`

- [x] **Step 1: Add a bottom anchored `PanelContainer` under `HUD`**

Create a bottom-centered action bar with an `HBoxContainer`, “移动” and “攻击” buttons, minimum sizes, and a compact style consistent with the existing HUD controls. It must not cover the existing inventory, loot, extraction, or result panels when those panels are open.

- [x] **Step 2: Connect button signals**

Connect both `pressed` signals to the controller methods added in Task 2 and keep scene paths stable for typed `@onready` references.

### Task 4: Run focused and regression verification

**Files:**
- Test: `tests/integration/move_highlights_test.gd`
- Test: `tests/integration/prototype_main_test.gd`
- Test: `tests/integration/runtime_session_loop_test.gd`
- Test: `tests/perception/perception_core_test.gd`

- [x] **Step 1: Run the focused action-mode test**

Run the headless `move_highlights_test.gd` command from Task 1 and require `MOVE_HIGHLIGHTS_TEST: PASS` with exit code 0.

- [x] **Step 2: Run scene, runtime, and perception regressions**

Run each listed script through the same Godot headless command. Require exit code 0 and the script's `PASS` marker; investigate any new parse, scene-instantiation, or behavior failure before continuing.

- [x] **Step 3: Inspect the final diff and preserve unrelated work**

Run `git status --short` and `git diff --check`. Confirm only the action UI files and the new plan/test files are added by this task, while existing map edits remain intact.
