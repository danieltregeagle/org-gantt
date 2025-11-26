;;; org-gantt-propagate-test.el --- Tests for org-gantt-propagate -*- lexical-binding: t -*-

;;; Code:

(require 'ert)
(require 'org-gantt-propagate)
(require 'org-gantt-parse)
(require 'org-gantt-context)
(require 'org-gantt-config)

(defun org-gantt-test-make-propagate-context ()
  "Create context for propagation tests."
  (let ((ctx (org-gantt-context-init 8 '(0 6))))
    (setf (org-gantt-context-options ctx)
          '(:milestone-tags ("milestone")
            :linked-to-property-keys (:LINKED-TO)
            :calc-progress nil))
    ctx))

(defun org-gantt-test-parse-and-propagate (org-string)
  "Parse ORG-STRING and run propagation, return context."
  (let ((ctx (org-gantt-test-make-propagate-context)))
    (with-temp-buffer
      (insert org-string)
      (org-mode)
      (let ((parsed (org-element-parse-buffer)))
        (setf (org-gantt-context-info-list ctx)
              (org-gantt-parse-crawl-headlines parsed ctx))))
    (org-gantt-propagate-all ctx)
    ctx))

;;; Date from Effort Tests

(ert-deftest org-gantt-propagate-test-ds-from-effort-forward ()
  "Test calculating end date from start + effort."
  (let* ((ctx (org-gantt-test-parse-and-propagate
               "* Task\nSCHEDULED: <2025-01-06 Mon>\n:PROPERTIES:\n:EFFORT: 2d\n:END:\n"))
         (info (car (org-gantt-context-info-list ctx)))
         (end-date (gethash org-gantt-end-prop info)))
    (should end-date)
    ;; Monday + 2 days = Wednesday
    (let ((decoded (decode-time end-date)))
      (should (= 8 (nth 3 decoded))))))  ; Jan 8

(ert-deftest org-gantt-propagate-test-ds-from-effort-backward ()
  "Test calculating start date from end + effort."
  (let* ((ctx (org-gantt-test-parse-and-propagate
               "* Task\nDEADLINE: <2025-01-10 Fri>\n:PROPERTIES:\n:EFFORT: 2d\n:END:\n"))
         (info (car (org-gantt-context-info-list ctx)))
         (start-date (gethash org-gantt-start-prop info)))
    (should start-date)
    ;; Friday (deadline at 8am) - 2 days = Wednesday
    (let ((decoded (decode-time start-date)))
      (should (= 8 (nth 3 decoded))))))  ; Jan 8

;;; Ordered Propagation Tests

(ert-deftest org-gantt-propagate-test-ordered-sequential ()
  "Test that ordered tasks get sequential dates."
  (let* ((ctx (org-gantt-test-parse-and-propagate
               (concat "* Project\n"
                       ":PROPERTIES:\n:ORDERED: t\n:END:\n"
                       "** Task 1\nSCHEDULED: <2025-01-06 Mon>\n"
                       ":PROPERTIES:\n:EFFORT: 2d\n:END:\n"
                       "** Task 2\n:PROPERTIES:\n:EFFORT: 2d\n:END:\n"
                       "** Task 3\n:PROPERTIES:\n:EFFORT: 1d\n:END:\n")))
         (project (car (org-gantt-context-info-list ctx)))
         (tasks (gethash :subelements project))
         (task1 (nth 0 tasks))
         (task2 (nth 1 tasks))
         (task3 (nth 2 tasks)))
    ;; Task 2 should start when Task 1 ends
    (should (gethash org-gantt-start-prop task2))
    ;; Task 3 should start when Task 2 ends
    (should (gethash org-gantt-start-prop task3))))

;;; Upward Propagation Tests

(ert-deftest org-gantt-propagate-test-dates-up ()
  "Test that parent dates come from children."
  (let* ((ctx (org-gantt-test-parse-and-propagate
               (concat "* Parent\n"
                       "** Child 1\nSCHEDULED: <2025-01-06 Mon> DEADLINE: <2025-01-08 Wed>\n"
                       "** Child 2\nSCHEDULED: <2025-01-10 Fri> DEADLINE: <2025-01-15 Wed>\n")))
         (parent (car (org-gantt-context-info-list ctx)))
         (start (gethash org-gantt-start-prop parent))
         (end (gethash org-gantt-end-prop parent)))
    ;; Parent start should be earliest child start (Jan 6)
    (should (= 6 (nth 3 (decode-time start))))
    ;; Parent end should be latest child end (Jan 15)
    (should (= 15 (nth 3 (decode-time end))))))

;;; Effort Summation Tests

(ert-deftest org-gantt-propagate-test-effort-sum ()
  "Test that parent effort is sum of children."
  (let* ((ctx (org-gantt-test-parse-and-propagate
               (concat "* Parent\n"
                       "** Child 1\n:PROPERTIES:\n:EFFORT: 2d\n:END:\n"
                       "** Child 2\n:PROPERTIES:\n:EFFORT: 3d\n:END:\n")))
         (parent (car (org-gantt-context-info-list ctx)))
         (effort (gethash org-gantt-effort-prop parent)))
    ;; Parent effort should be 5 days = 40 hours = 144000 seconds
    (should effort)
    (should (= (* 5 8 3600) (time-to-seconds effort)))))

;;; Progress Tests

(ert-deftest org-gantt-propagate-test-progress-from-clocksum ()
  "Test progress calculation from clocksum/effort."
  (let* ((ctx (org-gantt-test-parse-and-propagate
               "* Task\n:PROPERTIES:\n:EFFORT: 2d\n:CLOCKSUM: 8:00\n:END:\n"))
         (info (car (org-gantt-context-info-list ctx)))
         (progress (gethash org-gantt-progress-prop info)))
    ;; 8 hours of 16 hours (2 days) = 50%
    (should (= 50 progress))))

;;; Tag Propagation Tests

(ert-deftest org-gantt-propagate-test-tags-down ()
  "Test that parent tags propagate to children."
  (let* ((ctx (org-gantt-test-parse-and-propagate
               (concat "* Parent :important:\n"
                       "** Child 1 :urgent:\n"
                       "*** Grandchild\n")))
         (parent (car (org-gantt-context-info-list ctx)))
         (child (car (gethash :subelements parent)))
         (grandchild (car (gethash :subelements child))))
    ;; Child should have parent's tags in :parent-tags
    (should (member "important" (gethash org-gantt-parent-tags-prop child)))
    ;; Grandchild should have both parent and grandparent tags
    (should (member "important" (gethash org-gantt-parent-tags-prop grandchild)))
    (should (member "urgent" (gethash org-gantt-parent-tags-prop grandchild)))))

;;; Link Hash Tests

(ert-deftest org-gantt-propagate-test-linked-to ()
  "Test that LINKED-TO creates entries in link hash."
  (let* ((ctx (org-gantt-test-parse-and-propagate
               (concat "* Task A\n:PROPERTIES:\n:ID: task-a\nEFFORT: 2d\n:END:\n"
                       "SCHEDULED: <2025-01-06 Mon>\n"
                       "* Task B\n:PROPERTIES:\n:LINKED-TO: task-a\n:END:\n")))
         (link-hash (org-gantt-context-link-hash ctx)))
    ;; There should be a link from task-a to the generated ID of task-b
    (should (gethash "task-a" link-hash))))

;;; Convergence Tests

(ert-deftest org-gantt-propagate-test-convergence ()
  "Test that propagation converges."
  (let ((ctx (org-gantt-test-make-propagate-context)))
    (with-temp-buffer
      (insert (concat "* Complex\n"
                     ":PROPERTIES:\n:ORDERED: t\n:END:\n"
                     "** A\nSCHEDULED: <2025-01-06 Mon>\n"
                     ":PROPERTIES:\n:EFFORT: 2d\n:END:\n"
                     "** B\n:PROPERTIES:\n:EFFORT: 3d\n:END:\n"
                     "** C\n:PROPERTIES:\n:EFFORT: 1d\n:END:\n"))
      (org-mode)
      (setf (org-gantt-context-info-list ctx)
            (org-gantt-parse-crawl-headlines (org-element-parse-buffer) ctx)))
    ;; Should converge in reasonable iterations
    (let ((iterations (org-gantt-propagate-all-dates ctx)))
      (should (< iterations 10)))))

(provide 'org-gantt-propagate-test)
;;; org-gantt-propagate-test.el ends here
