# org-gantt.el Refactoring Guide

Complete prompt collection for refactoring org-gantt.el using Claude Code.

## Overview

This collection contains step-by-step prompts to refactor the monolithic
`org-gantt.el` (~1560 lines) into a modular architecture with:

- 8 separate modules
- Context-based state management (no globals)
- 50+ unit tests
- Clear separation of concerns

## Quick Start

1. Copy your `org-gantt.el` to a working directory
2. Initialize git: `git init && git add . && git commit -m "Initial"`
3. Follow the phases in order, using Claude Code for each

## Phase Summary

| Phase | File                     | Description           | Risk   | Sessions |
|-------|--------------------------|-----------------------|--------|----------|
| 0     | 01-phase-setup.org       | Test infrastructure   | None   | 1        |
| 1     | 02-phase-config.org      | Extract configuration | Low    | 1        |
| 2     | 03-phase-context.org     | Create context struct | Low    | 1        |
| 3     | 04-phase-util.org        | Extract utilities     | Low    | 1        |
| 4     | 05-phase-time.org        | Extract time module   | Medium | 2        |
| 5     | 06-phase-parse.org       | Extract parse module  | Medium | 2        |
| 6     | 07-phase-propagate.org   | Extract propagation   | High   | 3        |
| 7     | 08-phase-render.org      | Extract render module | Medium | 2        |
| 8     | 09-phase-core.org        | Refactor core         | High   | 2        |
| 9     | 10-phase-integration.org | Final cleanup         | Medium | 2        |

**Total: ~17 Claude Code sessions over ~11 weeks**

## File Structure

```
org-gantt-refactoring/
├── 00-MASTER-GUIDE.org      # Overview and execution protocol
├── 01-phase-setup.org       # Phase 0: Test infrastructure
├── 02-phase-config.org      # Phase 1: Configuration extraction
├── 03-phase-context.org     # Phase 2: Context struct
├── 04-phase-util.org        # Phase 3: Utilities
├── 05-phase-time.org        # Phase 4: Time module
├── 06-phase-parse.org       # Phase 5: Parse module
├── 07-phase-propagate.org   # Phase 6: Propagation
├── 08-phase-render.org      # Phase 7: Render module
├── 09-phase-core.org        # Phase 8: Core refactoring
├── 10-phase-integration.org # Phase 9: Final integration
└── README.md                # This file
```

## Each Phase Document Contains

1. **Objective** - What the phase accomplishes
2. **Prompt for Claude Code** - Copy/paste into Claude Code
3. **Verification Steps** - Commands to verify success
4. **Test File** - Unit tests for the phase
5. **Success Criteria** - Checklist before proceeding
6. **Rollback Instructions** - How to undo if needed

## Using with Claude Code

For each phase:

1. **Commit current state**
   ```bash
   git add -A && git commit -m "Before phase N"
   ```

2. **Open the phase document** and copy the prompt

3. **Paste into Claude Code** with your `org-gantt.el` file

4. **Review the output** before accepting changes

5. **Run verification steps** from the document

6. **Run tests**
   ```bash
   make test        # Unit tests
   make regression  # Output comparison
   ```

7. **Commit if passing**
   ```bash
   git add -A && git commit -m "Complete phase N"
   ```

## Expected Outcome

After all phases, you'll have:

```
org-gantt/
├── org-gantt.el              # Entry point (requires all modules)
├── org-gantt-config.el       # 22 defcustom, 12 defconst
├── org-gantt-context.el      # Context struct (~6 functions)
├── org-gantt-util.el         # 15 utility functions
├── org-gantt-time.el         # 17 time functions
├── org-gantt-parse.el        # 13 parse functions
├── org-gantt-propagate.el    # 15 propagation functions
├── org-gantt-render.el       # 12 render functions
├── org-gantt-core.el         # 5 core functions
├── Makefile                  # Build automation
└── test/
    ├── org-gantt-test-runner.el
    ├── org-gantt-*-test.el   # 8 test files
    └── test-fixtures/
        ├── sample-gantt.org
        └── expected-output.tex
```

## Architecture Highlights

### Before (Problems)
- 5 global mutable variables
- 175-line "god function"
- Untestable time calculations
- Circular dependencies
- No unit tests

### After (Solutions)
- Zero global state (context struct)
- Functions < 60 lines
- Pure functions with explicit parameters
- Clear module dependencies
- 50+ unit tests

## Tips

- **Always commit before each phase** - Easy rollback if needed
- **Run regression test after each phase** - Catch breakage early
- **Don't skip phases** - Later phases depend on earlier ones
- **Review Claude Code output** - Verify logic is preserved
- **Ask Claude Code to explain** - If something looks wrong

## Troubleshooting

**Tests fail after extraction:**
- Check that all `require` statements are present
- Verify function signatures match new conventions
- Ensure context is threaded through properly

**Regression test fails:**
- Compare output character by character
- Check date calculations (timezone issues?)
- Verify options are being read correctly

**Byte-compilation warnings:**
- Add missing `require` statements
- Check for undefined functions
- Ensure lexical-binding is t

## Timeline

Conservative estimate: 11-14 weeks
Aggressive estimate: 6-8 weeks

The timeline depends on:
- Familiarity with Emacs Lisp
- Thoroughness of testing
- Number of issues encountered
