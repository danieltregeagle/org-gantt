;;; org-gantt-context-test.el --- Tests for org-gantt-context -*- lexical-binding: t -*-

;;; Code:

(require 'ert)
(require 'org-gantt-context)

(ert-deftest org-gantt-context-test-create-defaults ()
  "Test context creation with defaults."
  (let ((ctx (org-gantt-context-init)))
    (should (= 8 (org-gantt-context-hours-per-day ctx)))
    (should (equal '(0 6) (org-gantt-context-work-free-days ctx)))
    (should (eq t (org-gantt-context-changed ctx)))
    (should (= 0 (org-gantt-context-id-counter ctx)))
    (should (hash-table-p (org-gantt-context-link-hash ctx)))))

(ert-deftest org-gantt-context-test-create-custom ()
  "Test context creation with custom values."
  (let ((ctx (org-gantt-context-init 6 '(0))))
    (should (= 6 (org-gantt-context-hours-per-day ctx)))
    (should (equal '(0) (org-gantt-context-work-free-days ctx)))))

(ert-deftest org-gantt-context-test-id-generation ()
  "Test unique ID generation."
  (let ((ctx (org-gantt-context-init)))
    (should (string= "org-gantt-id-0" (org-gantt-context-next-id ctx)))
    (should (string= "org-gantt-id-1" (org-gantt-context-next-id ctx)))
    (should (string= "org-gantt-id-2" (org-gantt-context-next-id ctx)))
    (should (= 3 (org-gantt-context-id-counter ctx)))))

(ert-deftest org-gantt-context-test-changed-flag ()
  "Test changed flag manipulation."
  (let ((ctx (org-gantt-context-init)))
    (should (eq t (org-gantt-context-changed ctx)))
    (org-gantt-context-reset-for-propagation ctx)
    (should (eq nil (org-gantt-context-changed ctx)))
    (org-gantt-context-mark-changed ctx)
    (should (eq t (org-gantt-context-changed ctx)))))

(ert-deftest org-gantt-context-test-link-hash ()
  "Test link hash operations."
  (let ((ctx (org-gantt-context-init)))
    (org-gantt-context-add-link ctx "task-a" "task-b")
    (org-gantt-context-add-link ctx "task-a" "task-c")
    (org-gantt-context-add-link ctx "task-b" "task-d")
    (let ((hash (org-gantt-context-link-hash ctx)))
      (should (equal '("task-c" "task-b") (gethash "task-a" hash)))
      (should (equal '("task-d") (gethash "task-b" hash))))))

(ert-deftest org-gantt-context-test-options ()
  "Test options access."
  (let ((ctx (org-gantt-context-init)))
    (setf (org-gantt-context-options ctx)
          '(:show-progress always :maxlevel 3))
    (should (eq 'always (org-gantt-context-get-option ctx :show-progress)))
    (should (= 3 (org-gantt-context-get-option ctx :maxlevel)))
    (should (eq nil (org-gantt-context-get-option ctx :missing)))
    (should (eq 'default (org-gantt-context-get-option ctx :missing 'default)))))

;;; org-gantt-context-test.el ends here
