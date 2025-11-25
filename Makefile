EMACS ?= emacs
BATCH = $(EMACS) -batch -Q -L .

.PHONY: test test-quick clean compile regression

test: compile
	$(BATCH) -L test -l test/org-gantt-test-runner.el \
	         -f org-gantt-run-all-tests

test-quick:
	$(BATCH) -L test -l ert -l test/org-gantt-util-test.el \
	         -f ert-run-tests-batch-and-exit

regression:
	$(BATCH) -L test -l test/org-gantt-test-runner.el \
	         -f org-gantt-run-regression-test

compile:
	$(BATCH) -f batch-byte-compile org-gantt.el

clean:
	rm -f *.elc test/*.elc
