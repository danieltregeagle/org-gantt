;;; org-gantt-test-runner.el --- Test runner for org-gantt -*- lexical-binding: t -*-

;; Copyright (C) 2025

;; This file is not part of GNU Emacs.

;;; Commentary:
;; Master test runner for org-gantt refactoring verification.
;; Provides functions to run all tests and regression tests.

;;; Code:

(require 'ert)
(require 'org)

(defvar org-gantt-test-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing test files.")

(defvar org-gantt-fixture-directory
  (expand-file-name "test-fixtures" org-gantt-test-directory)
  "Directory containing test fixtures.")

(defun org-gantt-test-load-all ()
  "Load all org-gantt test files."
  (dolist (file (directory-files org-gantt-test-directory t "-test\\.el$"))
    (load file nil t)))

(defun org-gantt-run-all-tests ()
  "Run all org-gantt tests and exit with appropriate code."
  (org-gantt-test-load-all)
  (let ((stats (ert-run-tests-batch-and-exit)))
    stats))

(defun org-gantt-run-regression-test ()
  "Run regression test comparing output to expected."
  (require 'org-gantt)
  (let* ((test-file (expand-file-name "sample-gantt.org"
                                      org-gantt-fixture-directory))
         (expected-file (expand-file-name "expected-output.tex"
                                          org-gantt-fixture-directory))
         (expected (with-temp-buffer
                     (insert-file-contents expected-file)
                     (buffer-string)))
         (actual (with-temp-buffer
                   (insert-file-contents test-file)
                   (org-mode)
                   (org-clock-sum) ;; Required for clocksum to work
                   (goto-char (point-min))
                   (search-forward "#+BEGIN: org-gantt-chart")
                   (beginning-of-line)
                   (org-update-dblock)
                   (goto-char (point-min))
                   (search-forward "#+BEGIN: org-gantt-chart")
                   (forward-line 1)
                   (let ((start (point)))
                     (search-forward "#+END:")
                     (beginning-of-line)
                     (buffer-substring-no-properties start (point))))))
    (if (string= (string-trim expected) (string-trim actual))
        (progn
          (message "Regression test PASSED")
          (kill-emacs 0))
      (message "Regression test FAILED")
      (message "Expected:\n%s" expected)
      (message "Actual:\n%s" actual)
      (kill-emacs 1))))

(provide 'org-gantt-test-runner)
;;; org-gantt-test-runner.el ends here
