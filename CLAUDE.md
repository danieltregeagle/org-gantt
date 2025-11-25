# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**org-gantt** is an Emacs Lisp package that creates pgfgantt-based Gantt charts from Org-mode headlines. It converts org headlines with schedules, deadlines, effort estimates, and clock values into LaTeX/pgfgantt code for PDF export.

**Current Status**: Monolithic architecture (~1560 lines in single file) undergoing structured refactoring into modular components.

## Refactoring Project

This codebase is being refactored following the strategy outlined in `org-gantt-refactor-docs/`. The refactoring aims to:

- Split monolithic `org-gantt.el` into 8 modular components
- Eliminate 5 global mutable variables via context-based state management
- Add 50+ unit tests
- Improve maintainability and testability

**Key Invariants:**
- Preserve exact functional behavior (no user-visible changes)
- Maintain backward compatibility with existing org files
- Follow Emacs Lisp conventions and style

**Refactoring Documentation:**
- See `org-gantt-refactor-docs/README.md` for phase overview
- See `org-gantt-refactor-docs/00-MASTER-GUIDE.org` for execution protocol
- Each phase has detailed instructions in `org-gantt-refactor-docs/XX-phase-*.org`

## Architecture

### Current (Monolithic)
- Single file: `org-gantt.el` (~1560 lines)
- 5 global mutable variables (`org-gantt-hours-per-day-gv`, `org-gantt-options`, `*org-gantt-changed-in-propagation*`, `*org-gantt-id-counter*`, `*org-gantt-link-hash*`)
- Main entry point: `org-dblock-write:org-gantt-chart` (175 lines)
- 22 `defcustom` configuration variables
- 12 `defconst` property/option constants

### Target (Modular)
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
└── test/
    ├── org-gantt-test-runner.el
    └── org-gantt-*-test.el   # 8 test files per module
```

## Key Concepts

### Gantt Info Data Structure
- Hash table representing a headline with properties:
  - `:name` - headline title
  - `:startdate`, `:enddate` - computed from schedules/deadlines
  - `:effort` - effort estimate
  - `:clocksum` - clocked time (24-hour basis)
  - `:progress` - completion percentage
  - `:tags`, `:parent-tags` - filtering/styling
  - `:id` - unique identifier for linking
  - `:subelements` - list of child gantt-infos

### Processing Pipeline
1. **Parse** (`org-gantt-crawl-headlines`): Org AST → gantt-info list
2. **Propagate** (multiple functions): Compute missing dates/efforts through tree
3. **Render** (`org-gantt-info-to-pgfgantt`): gantt-info → pgfgantt LaTeX code

### Time Handling
- All times use Emacs `time` values (internal representation)
- Workday calculations respect `hours-per-day` and `work-free-days` (weekends)
- Time propagation: ordered tasks chain sequentially, unordered use min/max
- Upcasting/downcasting normalizes times to day boundaries

## Development Workflow

### Testing (To Be Implemented in Phase 0)
```bash
make test        # Run unit tests (ert-based)
make regression  # Compare output against baseline
make clean       # Remove test artifacts
```

### Manual Testing
Load in Emacs and test with `org-gantt-manual.org`:
```elisp
(load-file "org-gantt.el")
;; Open org-gantt-manual.org
;; Place cursor in dynamic block
;; C-c C-c to update block
```

### Git Workflow
- **Always commit before each refactoring phase**
- Branch `refactoring` contains work in progress
- Use descriptive commit messages: "Complete phase N: [description]"

## Important Functions

### Entry Points
- `org-dblock-write:org-gantt-chart` - Main dynamic block handler
- `org-insert-dblock:org-gantt-chart` - Interactive block insertion

### Core Processing
- `org-gantt-crawl-headlines` - Parse org AST into gantt-info structures
- `org-gantt-propagate-order-timestamps` - Compute sequential task dates
- `org-gantt-calculate-ds-from-effort` - Compute dates from effort estimates
- `org-gantt-propagate-ds-up` - Propagate dates from children to parents
- `org-gantt-info-to-pgfgantt` - Render gantt-info to pgfgantt LaTeX

### Time Calculations
- `org-gantt-add-worktime` / `org-gantt-change-worktime` - Add/subtract work time
- `org-gantt-is-workday` - Check if date is workday
- `org-gantt-effort-to-time` - Parse effort strings (e.g., "2d 4:30")

## Common Pitfalls

1. **Global State**: When refactoring, ensure context is threaded through all function calls
2. **Time Zone Issues**: All time calculations use local timezone; regression tests may be sensitive
3. **Property Keywords**: Use constants like `org-gantt-start-prop` not hardcoded `:startdate`
4. **Hash Table Equality**: Use `org-gantt-equal` / `org-gantt-hashtable-equal` for comparisons
5. **Ordered vs Unordered**: Different propagation logic for `:ORDERED:` properties

## Code Style

- Use `lexical-binding: t` in all new files
- Prefix all functions with `org-gantt-` (no internal `--` convention yet)
- Docstrings for all public functions
- Keep functions under 60 lines (target for refactored code)
- Use `cl-lib` (not old `cl` package)
- Follow Emacs Lisp conventions: `setq` in `let`, `dolist` for iteration

## Resources

- Manual: `org-gantt-manual.org` (user-facing documentation)
- Refactoring Docs: `org-gantt-refactor-docs/` (phase-by-phase guides)
- pgfgantt package: https://www.ctan.org/pkg/pgfgantt
