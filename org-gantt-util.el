;;; org-gantt-util.el --- Utility functions for org-gantt -*- lexical-binding: t -*-

;; Copyright (C) 2025

;;; Commentary:
;;
;; Pure utility functions for org-gantt. These functions:
;; - Have no side effects
;; - Do not access global state
;; - Are safe to call from any context
;; - Handle nil inputs gracefully where appropriate

;;; Code:

(require 'cl-lib)

;;; String Utilities

(defun org-gantt-util-chomp (str)
  "Chomp leading and tailing whitespace from STR."
  (replace-regexp-in-string (rx (or (: bos (* (any " \t\n")))
                                    (: (* (any " \t\n")) eos)))
                            ""
                            str))

;;; Hash Table Utilities

(defun org-gantt-util-gethash (key table &optional dflt)
  "Look up KEY in TABLE and return its associated value.
If KEY is not found, or TABLE is nil, return DFLT which defaults to nil.
This is a nil-safe version of `gethash'."
  (if table
      (gethash key table dflt)
    dflt))

(defun org-gantt-util-hashtable-equal (table1 table2)
  "Return non-nil if TABLE1 and TABLE2 are hash tables with the same contents."
  (and (= (hash-table-count table1)
          (hash-table-count table2))
       (catch 'flag (maphash (lambda (x y)
                               (or (org-gantt-util-equal (gethash x table2) y)
                                   (throw 'flag nil)))
                             table1)
              (throw 'flag t))))

(defun org-gantt-util-equal (item1 item2)
  "Return non-nil if ITEM1 is equal to ITEM2, including hash tables."
  (if (and (hash-table-p item1) (hash-table-p item2))
      (org-gantt-util-hashtable-equal item1 item2)
    (equal item1 item2)))

(defun org-gantt-util-info-list-equal (il1 il2)
  "Return non-nil if IL1 is equal to IL2, including hash tables."
  (or (and (not il1) (not il2))
      (and (org-gantt-util-equal (car il1) (car il2))
           (org-gantt-util-info-list-equal (cdr il1) (cdr il2)))))

;;; Safe Conversion Utilities

(defun org-gantt-util-substring-if (string from to)
  "Return substring if STRING, FROM and TO are non-nil and FROM < TO.
Otherwise return nil."
  (and string from to (< from to) (substring string from to)))

(defun org-gantt-util-string-to-number (string)
  "Return `string-to-number' of STRING or 0 if STRING is nil."
  (if string (string-to-number string) 0))

;;; Time Comparison Utilities

(defun org-gantt-util-time-less-p (t1 t2)
  "Return non-nil if T1 is before T2.
Handles nil values: any time is considered less than nil."
  (and t1
       (or (not t2)
           (time-less-p t1 t2))))

(defun org-gantt-util-time-larger-p (t1 t2)
  "Return non-nil if T1 is later than T2.
Handles nil values: any time is larger than nil."
  (and t1
       (or (not t2)
           (time-less-p t2 t1))))

(defun org-gantt-util-time-difference (t1 t2)
  "Calculate the absolute difference between T1 and T2.
No matter which is larger, the resulting difference is always positive."
  (if (time-less-p t1 t2)
      (time-subtract t2 t1)
    (time-subtract t1 t2)))

;;; Tag Utilities

(defun org-gantt-util-get-tags-style (tags tags-styles)
  "Return the style appropriate for the given TAGS from TAGS-STYLES.
Returns the first matching style found."
  (let ((style nil))
    (dolist (tag tags style)
      (and (not style) (setq style (cdr (assoc tag tags-styles)))))))

(defun org-gantt-util-is-in-tags (tags taglist)
  "Return non-nil if any member of TAGLIST is in TAGS."
  (let ((ismember nil))
    (dolist (ct taglist ismember)
      (setq ismember (or ismember (member ct tags))))))

(defun org-gantt-util-stats-cookie-to-progress (stats-cookie)
  "Return a string between 0 and 100 representing the value of STATS-COOKIE.
Handles both percentage format [X%] and fraction format [X/Y].
Return nil if STATS-COOKIE is not readable."
  (let ((trimmed-cookie (substring stats-cookie 1 (- (length stats-cookie) 1))))
    (cond ((string-match "%" trimmed-cookie)
           (substring trimmed-cookie 0 (- (length trimmed-cookie) 1)))
          ((string-match "/" trimmed-cookie)
           (let* ((listy (split-string trimmed-cookie "/"))
                  (dividend (string-to-number (car listy)))
                  (divisor (string-to-number (cadr listy)))
                  (progress (* 100 (/ (float dividend) divisor))))
             (number-to-string progress)))
          (t nil))))

;;; Data Conversion

(defun org-gantt-util-plist-to-alist (pl)
  "Transform property list PL into an association list."
  (cl-loop for p on pl by #'cddr
	   collect (cons (car p) (cadr p))))

;;; Debug Support

(defvar org-gantt-util-debug nil
  "When non-nil, enable debug message output.")

(defun org-gantt-util-debug-message (format-string &rest args)
  "Print debug message if `org-gantt-util-debug' is non-nil.
FORMAT-STRING and ARGS are passed to `message'."
  (when org-gantt-util-debug
    (apply #'message (concat "[org-gantt] " format-string) args)))

(provide 'org-gantt-util)
;;; org-gantt-util.el ends here
