;;; org-gantt-config-test.el --- Tests for org-gantt-config -*- lexical-binding: t -*-

;;; Code:

(require 'ert)
(require 'org-gantt-config)

(ert-deftest org-gantt-config-test-hours-per-day-default ()
  "Test default hours per day value."
  (should (= 8 org-gantt-default-hours-per-day)))

(ert-deftest org-gantt-config-test-work-free-days-default ()
  "Test default work-free days (weekend)."
  (should (equal '(0 6) org-gantt-default-work-free-days)))

(ert-deftest org-gantt-config-test-property-keys-exist ()
  "Test that all property key constants are defined."
  (should (eq :startdate org-gantt-start-prop))
  (should (eq :enddate org-gantt-end-prop))
  (should (eq :effort org-gantt-effort-prop))
  (should (eq :clocksum org-gantt-clocksum-prop))
  (should (eq :progress org-gantt-progress-prop))
  (should (eq :stats-cookie org-gantt-stats-cookie-prop))
  (should (eq :tags org-gantt-tags-prop))
  (should (eq :parent-tags org-gantt-parent-tags-prop))
  (should (eq :id org-gantt-id-prop))
  (should (eq :blocker org-gantt-blocker-prop))
  (should (eq :trigger org-gantt-trigger-prop))
  (should (eq :linked-to org-gantt-linked-to-prop)))

(ert-deftest org-gantt-config-test-show-progress-options ()
  "Test that show-progress accepts valid symbols."
  (should (memq nil '(nil if-exists always)))
  (should (memq 'if-exists '(nil if-exists always)))
  (should (memq 'always '(nil if-exists always))))

(ert-deftest org-gantt-config-test-progress-source-options ()
  "Test that progress-source has valid options."
  (should (memq 'clocksum '(clocksum cookie clocksum-cookie cookie-clocksum)))
  (should (memq 'cookie-clocksum '(clocksum cookie clocksum-cookie cookie-clocksum))))

(ert-deftest org-gantt-config-test-milestone-tags-default ()
  "Test default milestone tags."
  (should (equal '("milestone") org-gantt-default-milestone-tags)))

;;; org-gantt-config-test.el ends here
