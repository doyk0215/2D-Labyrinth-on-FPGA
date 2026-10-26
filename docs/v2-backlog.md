# v2.0 Backlog — 2D Labyrinth on FPGA

Features deferred past the graded v1.0 build. Each entry says why it came up, what it should do, and how to check it. Story details for v1.0 stay in `_bmad-output/planning-artifacts/epics.md`.

## 1. Long-press BTNC full reset

**Why.** Since Story 4.2 (PR #40), BTNC is a short-press button: in MENU it confirms the stage, and in GENERATE, PLAY or WIN it returns to MENU. The only full reset is the power-on reset (`por_reset`). If the design ever locks up in MENU or in the OLED path, the only way out is to reprogram the board.

**What.**
- Holding BTNC for a long press (for example 2 s, a parameter such as `LONG_PRESS_CYCLES`) asserts the same full reset as power-on: game, menu, mouse and OLED.
- A short press keeps its Story 4.2 meaning: confirm in MENU, return to MENU elsewhere.
- The long press must not also fire the short-press action, either when it is first pressed or when it is released.

**Where.** `rtl/My_Top_Module.v`: extend the BTNC debouncer (`button_press_debounce`) with a held-time counter, or add a small long-press detector, and OR its pulse into the reset that `por_reset` drives.

**Check.**
- Testbench: a short press still confirms or returns to MENU; a long press from each state resets everything (including the OLED, which a short press does not reset) and causes no extra stage start.
- Board: hold BTNC in MENU, during generation and while playing; the OLED re-initialises and the game returns to MENU each time.
