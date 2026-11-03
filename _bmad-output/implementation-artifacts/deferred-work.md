# Deferred work

- source_spec: `_bmad-output/implementation-artifacts/spec-9-1-place-and-draw-item-boxes.md`
  summary: Decide whether an item box may sit right next to the start or goal cell, once Story 9.2 makes boxes pick-ups.
  decision_9_2: Keep existing placement, as requested by CJX on 2026-11-02; revisit during Story 9.8 board playtesting.
  evidence: Story 9.1 places a box anywhere in its quadrant except the start and goal cells, so a box can be next to the spawn (quadrant 2) or the goal (quadrant 0); with pickup on ball-centre entry (9.2) a debuff could trigger within the first second. Settle at the 9.2 design or the 9.8 playtest.

- source_spec: `_bmad-output/implementation-artifacts/spec-n20-stage.md`
  summary: `tb/run_current_stories.tcl` stops at its first failing bench, and 17 of its 50 benches already fail on main 3fdc74d (menu-era top benches, `tb_maze_gen` N = 5 boxes, OLED/menu/switch unit benches), so the documented full regression has not passed end to end since the menu work.
  evidence: Runs of every bench on main 3fdc74d and on feature/n20-stage give the same 17 failures with identical messages; for example `tb_menu_ctrl: default EASY stage menu/config incorrect cfg=05` and `tb_top_story14_integration: seed was reused for the next generation`.
- source_spec: `_bmad-output/implementation-artifacts/spec-n20-stage.md`
  summary: Several benches call `$fatal` inside a `fail` task, which xsim does not stop on, so a failing `tb_top_win_indication` (and others) keeps running and hangs the regression after its timeout message.
  evidence: On main 3fdc74d, `tb_top_win_indication` printed its `timeout` FAIL and then ran for over 2 hours until killed; replacing `$fatal` with `$finish` in those `fail` tasks would end the run.
- source_spec: `_bmad-output/implementation-artifacts/spec-n20-stage.md`
  summary: The N = 20 benches (`tb/run_n20.tcl`, including the N <= 15 golden-checksum bench) are not part of `run_current_stories.tcl`, so the standard regression does not guard N <= 15 maze equivalence.
  evidence: `run_current_stories.tcl` lists its benches explicitly and compiles without `-i tb`, which `tb_maze_gen_golden.v` needs for its `.vh`; fold them in when the stale benches above are repaired.
- source_spec: `_bmad-output/implementation-artifacts/spec-n20-stage.md`
  summary: `maze_gen`'s DFS stack is built from flip-flops (about 4,000 FF at 400 x 10 bits) because it has two write sites (`stack[0]` in S_INIT and `stack[sp]` in S_WCELL); one shared write port would let Vivado map it to LUT RAM.
  evidence: Routed hierarchy on feature/n20-stage shows `gen_i` at 4,180 FF (2,225 on main 3fdc74d); total 6,882 FF is 16.5%, inside the 30% cap, so this is headroom, not a failure. Re-run the golden checksums after any change.
