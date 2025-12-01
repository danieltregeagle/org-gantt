;;; org-gantt.el --- Create integrated pgf gantt charts from task headlines
;;

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;;; Commentary:
;;
;; This code implements the automatic creation of gantt charts via
;; pgfgantt from Org mode headlines.
;; It does so via a custom dynamic block that automatically generates
;; the required pgfgantt code.  It can use deadlines, schedules and
;; effort estimates, as well as TODO dependencies to generate the
;; gantt chart.  Optionally, the clocked time can be used to create
;; progress indication in the gantt chart.
;;
;; Refer to the file org-gantt-manual.org for more information.
;; That file is intended as a demonstration.  A pdf-exported version
;; of org-gantt-manual doubles as a complete manual to org-gantt.

;;; Code:

(require 'calendar)
(require 'cl-lib)
(require 'ob-latex) ; for org-babel-execute:latex

(require 'org-gantt-config)
(require 'org-gantt-context)
(require 'org-gantt-util)
(require 'org-gantt-time)
(require 'org-gantt-parse)
(require 'org-gantt-propagate)

;; Aliases for backward compatibility during refactoring
(defalias 'org-gantt-chomp 'org-gantt-util-chomp)
(defalias 'org-gantt-gethash 'org-gantt-util-gethash)
(defalias 'org-gantt-hashtable-equal 'org-gantt-util-hashtable-equal)
(defalias 'org-gantt-equal 'org-gantt-util-equal)
(defalias 'org-gantt-info-list-equal 'org-gantt-util-info-list-equal)
(defalias 'org-gantt-substring-if 'org-gantt-util-substring-if)
(defalias 'org-gantt-string-to-number 'org-gantt-util-string-to-number)
(defalias 'org-gantt-time-less-p 'org-gantt-util-time-less-p)
(defalias 'org-gantt-time-larger-p 'org-gantt-util-time-larger-p)
(defalias 'org-gantt-time-difference 'org-gantt-util-time-difference)
(defalias 'org-gantt-get-tags-style 'org-gantt-util-get-tags-style)
(defalias 'org-gantt-is-in-tags 'org-gantt-util-is-in-tags)
(defalias 'org-gantt-stats-cookie-to-progress 'org-gantt-util-stats-cookie-to-progress)
(defalias 'org-gantt-plist-to-alist 'org-gantt-util-plist-to-alist)
(defalias 'dbgmessage 'org-gantt-util-debug-message)

;; Time function compatibility wrappers (temporary during refactoring)
(defalias 'org-gantt-timestamp-to-time 'org-gantt-time-from-timestamp)

(defun org-gantt-strings-to-time
    (seconds-string minutes-string &optional hours-string
                    days-string weeks-string months-string years-string hours-per-day)
  "Compatibility wrapper for org-gantt-time-from-strings."
  (org-gantt-time-from-strings
   seconds-string minutes-string hours-string
   days-string weeks-string months-string years-string
   hours-per-day (plist-get org-gantt-options :work-free-days)))

(defun org-gantt-effort-to-time (effort &optional hours-per-day)
  "Compatibility wrapper for org-gantt-time-from-effort."
  (org-gantt-time-from-effort
   effort
   hours-per-day
   (plist-get org-gantt-options :work-free-days)))

(defun org-gantt-is-workday (time)
  "Compatibility wrapper for org-gantt-time-is-workday."
  (org-gantt-time-is-workday time (plist-get org-gantt-options :work-free-days)))

(defun org-gantt-change-workdays (time ndays change-function)
  "Compatibility wrapper for org-gantt-time-change-workdays."
  (org-gantt-time-change-workdays
   time ndays change-function
   (plist-get org-gantt-options :work-free-days)))

(defun org-gantt-day-end (time)
  "Compatibility wrapper for org-gantt-time-day-end."
  (org-gantt-time-day-end time (org-gantt-hours-per-day)))

(defalias 'org-gantt-day-start 'org-gantt-time-day-start)

(defun org-gantt-add-worktime (time change-time)
  "Compatibility wrapper for org-gantt-time-add-worktime."
  (org-gantt-time-add-worktime
   time change-time
   (org-gantt-hours-per-day)
   (plist-get org-gantt-options :work-free-days)))

(defun org-gantt-change-worktime (time change-time time-changer day-start-getter day-end-getter)
  "Compatibility wrapper for org-gantt-time-change-worktime."
  (org-gantt-time-change-worktime
   time change-time time-changer day-start-getter day-end-getter
   (org-gantt-hours-per-day)
   (plist-get org-gantt-options :work-free-days)))

(defun org-gantt-get-next-time (endtime)
  "Compatibility wrapper for org-gantt-time-next-start."
  (org-gantt-time-next-start
   endtime
   (org-gantt-hours-per-day)
   (plist-get org-gantt-options :work-free-days)))

(defun org-gantt-get-prev-time (starttime)
  "Compatibility wrapper for org-gantt-time-prev-end."
  (org-gantt-time-prev-end
   starttime
   (org-gantt-hours-per-day)
   (plist-get org-gantt-options :work-free-days)))

(defun org-gantt-downcast-endtime (endtime)
  "Compatibility wrapper for org-gantt-time-downcast-end."
  (org-gantt-time-downcast-end
   endtime
   (org-gantt-hours-per-day)
   (plist-get org-gantt-options :work-free-days)))

(defun org-gantt-upcast-starttime (starttime)
  "Compatibility wrapper for org-gantt-time-upcast-start."
  (org-gantt-time-upcast-start
   starttime
   (org-gantt-hours-per-day)
   (plist-get org-gantt-options :work-free-days)))

(defun org-gantt-get-day-ratio (time)
  "Compatibility wrapper for org-gantt-time-day-ratio."
  (org-gantt-time-day-ratio time (org-gantt-hours-per-day)))

(defalias 'org-gantt-get-month-ratio 'org-gantt-time-month-ratio)

;; Parse function compatibility wrappers (temporary during refactoring)
(defun org-gantt-get-planning-time (element timestamp-type)
  "Compatibility wrapper for org-gantt-parse-planning-time."
  (org-gantt-parse-planning-time element timestamp-type (org-gantt-hours-per-day)))

(defalias 'org-gantt-get-subheadlines 'org-gantt-parse-subheadlines)

(defalias 'org-gantt-subheadline-extreme 'org-gantt-parse-subheadline-extreme)

(defun org-gantt-get-start-time (element)
  "Compatibility wrapper for org-gantt-parse-start-time."
  (org-gantt-parse-start-time element (org-gantt-hours-per-day)))

(defun org-gantt-get-end-time (element)
  "Compatibility wrapper for org-gantt-parse-end-time."
  (org-gantt-parse-end-time element (org-gantt-hours-per-day)))

(defun org-gantt-subheadlines-effort (element effort-getter element-org-gantt-effort-prop)
  "Compatibility wrapper for org-gantt-parse-subheadlines-effort."
  (org-gantt-parse-subheadlines-effort element effort-getter element-org-gantt-effort-prop))

(defun org-gantt-get-effort (element element-org-gantt-effort-prop &optional use-subheadlines-effort)
  "Compatibility wrapper for org-gantt-parse-effort."
  (org-gantt-parse-effort
   element element-org-gantt-effort-prop
   (plist-get org-gantt-options :work-free-days)
   use-subheadlines-effort))

(defalias 'org-gantt-statistics-value 'org-gantt-parse-statistics-value)

(defalias 'org-gantt-get-flattened-properties 'org-gantt-parse-flattened-properties)

(defun org-gantt-create-id ()
  "Compatibility wrapper using global counter (deprecated).
This function maintains backward compatibility but uses a global variable.
New code should use org-gantt-context-next-id instead."
  (setq *org-gantt-id-counter*
        (+ 1 *org-gantt-id-counter*))
  (concat "uniqueid"
          (number-to-string *org-gantt-id-counter*)))

(defun org-gantt-create-gantt-info (element)
  "Compatibility wrapper for org-gantt-parse-create-info.
Creates a temporary context using global org-gantt-options."
  (let ((ctx (org-gantt-context-init (org-gantt-hours-per-day)
                                     (plist-get org-gantt-options :work-free-days))))
    (setf (org-gantt-context-options ctx) org-gantt-options)
    (setf (org-gantt-context-id-counter ctx) *org-gantt-id-counter*)
    (let ((result (org-gantt-parse-create-info element ctx)))
      (setq *org-gantt-id-counter* (org-gantt-context-id-counter ctx))
      result)))

(defun org-gantt-crawl-headlines (data)
  "Compatibility wrapper for org-gantt-parse-crawl-headlines.
Creates a temporary context using global org-gantt-options."
  (let ((ctx (org-gantt-context-init (org-gantt-hours-per-day)
                                     (plist-get org-gantt-options :work-free-days))))
    (setf (org-gantt-context-options ctx) org-gantt-options)
    (setf (org-gantt-context-id-counter ctx) *org-gantt-id-counter*)
    (let ((result (org-gantt-parse-crawl-headlines data ctx)))
      (setq *org-gantt-id-counter* (org-gantt-context-id-counter ctx))
      result)))

(defalias 'org-gantt-get-extreme-date-il 'org-gantt-parse-extreme-date)

;; Propagation function compatibility wrappers (temporary during refactoring)
(defun org-gantt-calculate-ds-from-effort (headline-list)
  "Compatibility wrapper for org-gantt-propagate-ds-from-effort."
  (let ((ctx (org-gantt-context-init (org-gantt-hours-per-day)
                                     (plist-get org-gantt-options :work-free-days))))
    (setf (org-gantt-context-info-list ctx) headline-list)
    (org-gantt-propagate-ds-from-effort ctx)
    (org-gantt-context-changed ctx)))

(defun org-gantt-propagate-order-timestamps (headline-list &optional is-ordered parent-start parent-end)
  "Compatibility wrapper for org-gantt-propagate-order-timestamps."
  (let ((ctx (org-gantt-context-init (org-gantt-hours-per-day)
                                     (plist-get org-gantt-options :work-free-days))))
    (org-gantt-propagate--order-timestamps-list
     headline-list is-ordered parent-start parent-end ctx)))

(defalias 'org-gantt-find-headline-with-id 'org-gantt-propagate--find-by-id)

(defun org-gantt-propagate-linked-to-timestamps (headline-list complete-headline-list)
  "Compatibility wrapper for org-gantt-propagate-linked-to."
  ;; This wrapper doesn't use context properly, so it won't populate link-hash
  ;; The main function should use the context-based version
  (let ((ctx (org-gantt-context-init (org-gantt-hours-per-day)
                                     (plist-get org-gantt-options :work-free-days))))
    (org-gantt-propagate--linked-to-recurse headline-list complete-headline-list ctx)))

(defun org-gantt-propagate-ds-up (headline-list &optional ordered)
  "Compatibility wrapper for org-gantt-propagate-dates-up."
  (org-gantt-propagate--dates-up-list headline-list ordered))

(defun org-gantt-propagate-summation-up (headline-list property subsum-getter &optional prioritize-subsums)
  "Compatibility wrapper for org-gantt-propagate-summation-up."
  (org-gantt-propagate--summation-up-list
   headline-list property subsum-getter prioritize-subsums))

(defalias 'org-gantt-get-subheadline-effort-sum 'org-gantt-propagate--effort-sum)

(defalias 'org-gantt-get-subheadline-progress-summation 'org-gantt-propagate--progress-sum)

(defun org-gantt-compute-progress (headline-list)
  "Compatibility wrapper for org-gantt-propagate-compute-progress."
  (org-gantt-propagate--compute-progress-list headline-list))

(defun org-gantt-propagate-tags-down (headline-list parent-tags)
  "Compatibility wrapper for org-gantt-propagate-tags-down."
  (org-gantt-propagate--tags-down-list headline-list parent-tags))

(defalias 'org-gantt-get-completion-percent 'org-gantt-propagate--completion-percent)

(defvar org-gant-hours-per-day-gv nil
  "Global variable for local hours-per-day.")

(defvar org-gantt-options nil
  "Global variable that keeps a plist of the current options.
Is filled with local or default options.")

(defvar *org-gantt-changed-in-propagation* nil
  "Global variable for checking if something was changed during propagation.")

(defvar *org-gantt-id-counter* 0
  "Global variable for creating ids.")

(defvar *org-gantt-link-hash* nil
  "Global variable for storing manually given links.
Is used to create the manual links between elements at the end.")

(defun org-gantt-hours-per-day ()
  "Get the hours per day."
  org-gantt-hours-per-day-gv)

(defun org-gantt-hours-per-day-time ()
  "Get hours per day as a time value."
  (org-gantt-time-hours-to-time (org-gantt-hours-per-day)))


(defun org-gantt-get-shifts (up-start down-end compress &optional subelements)
  "Return the string describing the shift for pgf-gantt.
Calculate the shift from UP-START and DOWN-END.
If compress is non-nil calculate month shifts,
otherwise, calculate day shifts.
Use \"group left shift=\" instead of \"bar left shift=\" for SUBELEMENTS."
  (concat
   (if subelements "group left shift=" "bar left shift=")
   (number-to-string
    (if compress
        (org-gantt-get-month-ratio up-start)
      (org-gantt-get-day-ratio up-start)))
   (if subelements ", group right shift=" ", bar right shift=")
   (number-to-string
    (if compress
        (* -1.0 (- 1.0  (org-gantt-get-month-ratio down-end)))
      (if (>  (org-gantt-get-day-ratio down-end) 0)
          (* -1.0 (- 1.0 (org-gantt-get-day-ratio down-end)))
        0)))))

(defun org-gantt-get-tags-style (tags tags-styles)
  "Return the style appropriate for the given TAGS as noted by TAGS-STYLE.
i.e. the first found style."
  (let ((style nil))
    (dolist (tag tags style)
      (and (not style) (setq style (cdr (assoc tag tags-styles)))))))

(defun org-gantt-is-in-tags (tags taglist)
  "Return true iff any member of TAGLIST is in TAGS."
  (let ((ismember nil))
    (dolist (ct taglist ismember)
      (setq ismember (or ismember (member ct tags))))))

(defun org-gantt-stats-cookie-to-progress (stats-cookie)
  "Return a string between 0 and 100 representing the value of STATS-COOKIE.
Return nil, if stats-cookie is not readable."
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

(defun org-gantt-will-render-anything-p (item default-date item-level)
  "Check if ITEM or its descendants will render anything.
ITEM-LEVEL is the level at which ITEM would be rendered."
  (let* ((start (gethash org-gantt-start-prop item))
         (end (gethash org-gantt-end-prop item))
         (tags (gethash org-gantt-tags-prop item))
         (parent-tags (gethash org-gantt-parent-tags-prop item))
         (item-subelements (gethash :subelements item))
         (ignore-tags (plist-get org-gantt-options :ignore-tags))
         (use-tags (plist-get org-gantt-options :use-tags))
         (no-date-headlines (plist-get org-gantt-options :no-date-headlines))
         (incomplete-date-headlines (plist-get org-gantt-options :incomplete-date-headlines))
         (maxlevel (plist-get org-gantt-options :maxlevel))
         (ignore-this nil)
         (ignore-only-this nil))

    ;; Replicate ignore-this logic from org-gantt-info-to-pgfgantt
    (cond ((and (not start) (not end))
           (when (equal no-date-headlines 'ignore)
             (setq ignore-this t)))
          ((not end)
           (when (equal incomplete-date-headlines 'ignore)
             (setq ignore-this t)))
          ((not start)
           (when (equal incomplete-date-headlines 'ignore)
             (setq ignore-this t))))

    (when (and ignore-tags (org-gantt-is-in-tags tags ignore-tags))
      (setq ignore-this t))

    ;; Replicate ignore-only-this logic
    (when (and use-tags
               (not (org-gantt-is-in-tags tags use-tags))
               (not (org-gantt-is-in-tags parent-tags use-tags)))
      (setq ignore-only-this t))

    ;; Check if anything will render:
    ;; - If ignore-this is true, nothing renders
    ;; - If ignore-only-this is false, the item itself renders
    ;; - If ignore-only-this is true, check if children render
    ;;   (children only render if level allows and some descendant is visible)
    (and (not ignore-this)
         (or (not ignore-only-this)
             (and item-subelements
                  (or (not maxlevel) (< item-level maxlevel))
                  (cl-some (lambda (child)
                             (org-gantt-will-render-anything-p
                              child default-date (+ item-level 1)))
                           item-subelements))))))

(defun org-gantt-has-visible-children-p (subelements default-date children-level)
  "Check if SUBELEMENTS contains any child that will actually render.
CHILDREN-LEVEL is the level at which the children would be rendered."
  (and subelements
       (cl-some (lambda (child)
                  (org-gantt-will-render-anything-p child default-date children-level))
                subelements)))

(defun org-gantt-info-to-pgfgantt (gi default-date level &optional prefix ordered linked last)
  "Create a pgfgantt string from gantt-info GI.
Prefix the created string with PREFIX.
ORDERED determines whether the current headaline is ordered
\(Required for correct linking of sub-subheadlines\).
Create a bar linked to the previous bar, if LINKED is non-nil.
LAST should be non-nil for the last gant-info in the Gant Chart."
  (when gi
    (let* ((subelements (gethash :subelements gi))
           (id (gethash org-gantt-id-prop gi))
           (start (gethash org-gantt-start-prop gi))
           (end (gethash org-gantt-end-prop gi))
           (up-start (org-gantt-upcast-starttime (gethash org-gantt-start-prop gi)))
           (down-end (org-gantt-downcast-endtime (gethash org-gantt-end-prop gi)))
           (effort (gethash org-gantt-effort-prop gi))
           (clocksum (gethash org-gantt-clocksum-prop gi))
           (progress (gethash org-gantt-progress-prop gi))
           (progress-str (and progress (number-to-string progress)))
           (stats-cookie (gethash org-gantt-stats-cookie-prop gi))
           (stats-cookie-str (and stats-cookie (org-gantt-stats-cookie-to-progress stats-cookie)))
           (tags (gethash org-gantt-tags-prop gi))
           (parent-tags (gethash org-gantt-parent-tags-prop gi))
           (compress (plist-get org-gantt-options :compress))
           (no-date-headlines (plist-get org-gantt-options :no-date-headlines))
           (incomplete-date-headlines (plist-get org-gantt-options :incomplete-date-headlines))
           (inactive-bar-style (plist-get org-gantt-options :inactive-bar-style))
           (inactive-group-style (plist-get org-gantt-options :inactive-group-style))
           (maxlevel (plist-get org-gantt-options :maxlevel))
           (tags-bar-style (plist-get org-gantt-options :tags-bar-style))
           (tags-group-style (plist-get org-gantt-options :tags-group-style))
           (tag-style-effect (plist-get org-gantt-options :tag-style-effect))
           (tag-style-to-subheadlines (equal tag-style-effect 'subheadlines))
           (ctag-group-style (or (org-gantt-get-tags-style tags tags-group-style)
                                 (and tag-style-to-subheadlines
                                      (org-gantt-get-tags-style parent-tags tags-group-style))))
           (ctag-bar-style (or (org-gantt-get-tags-style tags tags-bar-style)
                               (and tag-style-to-subheadlines
                                    (org-gantt-get-tags-style parent-tags tags-bar-style))))
           (ignore-tags (plist-get org-gantt-options :ignore-tags))
           (use-tags (plist-get org-gantt-options :use-tags))
           (is-milestone (org-gantt-is-in-tags tags (plist-get org-gantt-options :milestone-tags)))
           (show-progress (plist-get org-gantt-options :show-progress))
           (progress-source (plist-get org-gantt-options :progress-source))
           (inactive-style)
           (ignore-this nil)      ;ignore everything sub-this
           (ignore-only-this nil) ;ignore this, but maybe allow sub-this
           )
      ;; Set default dates if missing
      (cond ((and (not up-start) (not down-end))
             (setq up-start default-date)
             (setq down-end default-date))
            ((not down-end)
             (setq down-end up-start))
            ((not up-start)
             (setq up-start down-end)))
      ;; Check if this item or any descendants will render anything
      (setq ignore-this (not (org-gantt-will-render-anything-p gi default-date level)))
      ;; Check if only this item should be ignored (but maybe children should render)
      (when (and use-tags
                 (not (org-gantt-is-in-tags tags use-tags))
                 (not (org-gantt-is-in-tags parent-tags use-tags)))
        (setq ignore-only-this t))
      (unless ignore-this
        (concat
         (unless ignore-only-this
           (concat
            prefix
            (cond (is-milestone
                   (if linked "\\ganttlinkedmilestone" "\\ganttmilestone"))
                  ((org-gantt-has-visible-children-p subelements default-date (+ level 1))
                   (if linked "\\ganttlinkedgroup" "\\ganttgroup"))
                  (t
                   (if linked "\\ganttlinkedbar" "\\ganttbar")))
            "["
            (org-gantt-get-shifts up-start down-end compress
                      (and subelements
                           (org-gantt-has-visible-children-p subelements default-date (+ level 1))))
            (when id (concat ", name=" id))
            (cond
             ((equal show-progress 'always)
              (concat
               ", progress="
               (cond
                ((equal progress-source 'clocksum) progress-str)
                ((equal progress-source 'cookie) stats-cookie-str)
                ((equal progress-source 'clocksum-cookie) (or progress-str stats-cookie-str))
                ((equal progress-source 'cookie-clocksum) (or stats-cookie-str progress-str))
                (t nil))))
             ((and (equal show-progress 'if-exists)
                   (equal progress-source 'clocksum)
                   clocksum)
              (concat ",progress=" progress-str))
             ((and (equal show-progress 'if-exists)
                   (equal progress-source 'cookie)
                   stats-cookie)
              (concat ",progress=" stats-cookie-str))
             ((and (equal show-progress 'if-exists)
                   (equal progress-source 'clocksum-cookie)
                   (or clocksum stats-cookie))
              (concat ",progress=" (or progress-str stats-cookie-str)))
             ((and (equal show-progress 'if-exists)
                   (equal progress-source 'cookie-clocksum)
                   (or stats-cookie clocksum))
              (concat ",progress=" (or stats-cookie-str progress-str)))
             (t nil))

            ;; (when (or (equal show-progress 'always)
            ;;      (and (equal show-progress 'if-exists)
            ;;       (or (and (equal progress-source 'clocksum)
            ;;            clocksum)
            ;;           (and (equal progress-source 'clocksum)))))
            ;;              ;FIXME : use progress-prop here
            ;;   (concat
            ;;    ", progress="
            ;;    (if progress (number-to-string progress)
            ;;      (if stats-cookie stats-cookie "NIX") "0")))

            (cond ((or (and (not up-start) (not down-end) (equal no-date-headlines 'inactive))
                       (and (or (not up-start) (not down-end)) (equal incomplete-date-headlines 'inactive)))
                   (if subelements
                       (concat ", " inactive-group-style)
                     (concat ", " inactive-bar-style)))
                  ((and subelements ctag-group-style)
                   (concat ", " ctag-group-style))
                  ((and (not subelements) ctag-bar-style)
                   (concat ", " ctag-bar-style)))
            "]"
            "{"
            (apply #'concat (split-string (gethash :name gi) "%" t))
            "}"
            "{"
            (if is-milestone
                (format-time-string "%Y-%m-%d" start)
              (if up-start
                  (format-time-string "%Y-%m-%d" up-start)
                (if (not (equal no-date-headlines 'ignore))
                    (format-time-string "%Y-%m-%d" default-date))))
            "}"
            (unless is-milestone
              (concat
               "{"
               (if down-end
                   (format-time-string "%Y-%m-%d" down-end)
                 (if (not (equal no-date-headlines 'ignore))
                     (format-time-string "%Y-%m-%d" default-date)))
               "}"))
            (and (or subelements (null last)) "\\\\")
            (when org-gantt-output-debug-dates
              (concat
               "%"
               (when start
                 (format-time-string "%Y-%m-%d,%H:%M" start))
               " -- "
               (when effort
                 (concat
                  (number-to-string (floor (time-to-number-of-days effort)))
                  "d "
                  (format-time-string "%H:%M" effort)))
               (when clocksum
                 (concat
                  " -("
                  (number-to-string (floor (time-to-number-of-days clocksum)))
                  "d "
                  (format-time-string "%H:%M" effort)
                  ")- "))
               " -- "
               (when end
                 (format-time-string "%Y-%m-%d,%H:%M" end))))
            "\n"))
         (when (and subelements (or (not maxlevel) (< level maxlevel)))
           (org-gantt-info-list-to-pgfgantt
            subelements
            default-date
            (+ level 1)
            (concat prefix "  ")
            (or ordered (gethash :ordered gi)) last)))))))

(defun org-gantt-info-list-to-pgfgantt (data default-date level &optional prefix ordered last)
  "Return a pgfgantt string representing DATA.
Prefix each line of the created representation with PREFIX.
Create correctly linked representation, if ORDERED is non-nil."
  (apply #'concat
	 (org-gantt-info-to-pgfgantt (car data) default-date level prefix ordered nil (and last (null (cdr data))))
	 (cl-loop for datum on (cdr data)
		  collect
		  (org-gantt-info-to-pgfgantt (car datum) default-date level prefix ordered ordered (and last (null (cdr datum)))))))

(defun org-gantt-linkhash-to-pgfgantt (linkhash)
  "Return a pgfgantt string representing the links in LINKHASH."
  (dbgmessage "LINKED-HASH: %s" linkhash)
  (let ((retstring ""))
    (maphash
     (lambda (from tolist)
       (dolist (to tolist)
         (setq retstring
               (concat retstring "\\ganttlink{" from "}{" to "}\n"))))
     linkhash)
    retstring))

(defun org-gantt-days-to-vgrid-style (weekend workday weekend-style workday-style)
  "Return a vgrid-style for either WEEKEND or WORKDAY (whichever is non-nil).
Use WEEKEND-STYLE or WORKDAY-STYLE, resp., for as the style string."
  (or
   (when weekend
     (concat "*" (number-to-string weekend) weekend-style))
   (when workday
     (concat "*" (number-to-string workday) workday-style))))

(defun org-gantt-get-vgrid-style (start-time weekend-style workday-style)
  "Compute a vgrid style from the START-TIME, marking weekends.
Use WEEKEND-STYLE and WORKDAY-STYLE as templates for the style."
  (let* ((dow (string-to-number (format-time-string "%w" start-time)))
         (weekend-start (and (or (= 0 dow) (> dow 4)) (% (- 8 dow) 7)))
         (work-start (and (> dow 0) (< dow 5) (- 5 dow)))
         (weekend-middle (and (not weekend-start) 3))
         (work-middle (and (not work-start) 4))
         (weekend-end (and weekend-start (< weekend-start 3) (- 3 weekend-start)))
         (work-end (and work-start (< work-start 4) (- 4 work-start))))
    (concat
     "{"
     (org-gantt-days-to-vgrid-style weekend-start work-start weekend-style workday-style)
     ","
     (org-gantt-days-to-vgrid-style weekend-middle work-middle weekend-style workday-style)
     (when (or weekend-end work-end) ",")
     (org-gantt-days-to-vgrid-style weekend-end work-end weekend-style workday-style)
     "}")))

;; Used to pass params to org-babel:
(defun org-gantt-plist-to-alist (pl)
  "Transform property list PL into an association list."
  (let (al)
    (cl-loop for p on pl by #'cddr
	     collect (cons (car p) (cadr p))
	     )))

(defun dbgmessage (format-string &rest args)
  "FIXME: get rid of after debugging"
  (apply #'message format-string args))
;;  (let ((print-length nil) (print-level nil))
;;  (insert (apply #'format (concat format-string "\n") args))))

(defun org-dblock-write:org-gantt-chart (params)
  "The function that is called for updating gantt chart code.
PARAMS determine several options of the gantt chart."
  (setq *org-gantt-changed-in-propagation* t)
  (setq *org-gantt-id-counter* 0)
  (setq *org-gantt-link-hash* (make-hash-table))
  (let (id idpos id-as-string view-file view-pos)
    (when (setq id (plist-get params :id))
      (setq id-as-string (cond ((numberp id) (number-to-string id))
                               ((symbolp id) (symbol-name id))
                               ((stringp id) id)
                               (t "")))
      (cond ((not id) nil)
            ((eq id 'global) (setq view-pos (point-min)))
            ((eq id 'local))
            ((string-match "^file:\\(.*\\)" id-as-string)
             (setq view-file (match-string 1 id-as-string)
                   view-pos 1)
             (unless (file-exists-p view-file)
               (error "No such file: \"%s\"" id-as-string)))))
    (with-current-buffer
        (if view-file
            (get-file-buffer view-file)
          (current-buffer))
      (org-clock-sum)
      (setq org-gantt-hours-per-day-gv (or (plist-get params :hours-per-day) org-gantt-default-hours-per-day))
      (let* ((titlecalendar (or (plist-get params :title-calendar) org-gantt-default-title-calendar))
             (compressed-titlecalendar (or (plist-get params :compressed-title-calendar) org-gantt-default-compressed-title-calendar))
             (hgrid (if (plist-member params :hgrid) (plist-get params :hgrid) org-gantt-default-hgrid))
             (start-date (plist-get params :start-date))
             (end-date (plist-get params :end-date))
             (start-date-list (and start-date (org-parse-time-string start-date)))
             (end-date-list (and end-date (org-parse-time-string end-date)))
             (start-date-time (and start-date-list (apply 'encode-time start-date-list)))
             (end-date-time (and end-date-list (apply 'encode-time end-date-list)))
             (additional-parameters (plist-get params :parameters))
             (weekend-style (or (plist-get params :weekend-style) org-gantt-default-weekend-style))
             (workday-style (or (plist-get params :workday-style) org-gantt-default-workday-style))
             (today-value (plist-get params :today))
             (calc-progress (plist-get params :calc-progress))
             (id-subelements (plist-get params :use-id-subheadlines))
             (compress (plist-get params :compress))
             (tikz-options (plist-get params :tikz-options))
             (parsed-buffer (org-element-parse-buffer))
             (parsed-data
              (cond ((or (not id) (eq id 'global) view-file) parsed-buffer)
                    ((eq id 'local) (error "Local id handling not yet implemented"))
                    (t (org-element-map parsed-buffer 'headline
                         (lambda (element)
                           (if (equal (org-element-property :ID element) id)
                               (if id-subelements
                                   (cdr element)
                                 element)
                             nil))  nil t))))
             (org-gantt-info-list nil)
             (org-gantt-check-info-list nil))
        (setq org-gantt-options
              (list :work-free-days
                    (or (plist-get params :work-free-days) org-gantt-default-work-free-days)
                    :no-date-headlines
                    (or (plist-get params :no-date-headlines) org-gantt-default-no-date-headlines)
                    :incomplete-date-headlines
                    (or (plist-get params :incomplete-date-headlines) org-gantt-default-incomplete-date-headlines)
                    :inactive-bar-style
                    (or (plist-get params :inactive-bar-style) org-gantt-default-inactive-bar-style)
                    :inactive-group-style
                    (or (plist-get params :inactive-group-style) org-gantt-default-inactive-group-style)
                    :tags-bar-style
                    (or (plist-get params :tags-bar-style) org-gantt-default-tags-bar-style)
                    :tags-group-style
                    (or (plist-get params :tags-group-style) org-gantt-default-tags-group-style)
                    :tag-style-effect
                    (or (plist-get params :tag-style-effect) org-gantt-default-tag-style-effect)
                    :use-tags
                    (or (plist-get params :use-tags) org-gantt-default-use-tags)
                    :ignore-tags
                    (or (plist-get params :ignore-tags) org-gantt-default-ignore-tags)
                    :milestone-tags
                    (or (plist-get params :milestone-tags) org-gantt-default-milestone-tags)
                    :linked-to-property-keys
                    (or (plist-get params :linked-to-property-keys) org-gantt-default-linked-to-property-keys)
                    :show-progress
                    (or (plist-get params :show-progress) org-gantt-default-show-progress)
                    :progress-source
                    (or (plist-get params :progress-source) org-gantt-default-progress-source)
                    :compress
                    compress
                    :maxlevel
                    (or (plist-get params :maxlevel) org-gantt-default-maxlevel)))
        ;; Create context for propagation
        (let ((ctx (org-gantt-context-init (org-gantt-hours-per-day)
                                           (plist-get org-gantt-options :work-free-days))))
          (setf (org-gantt-context-options ctx) org-gantt-options)
          (setf (org-gantt-context-id-counter ctx) *org-gantt-id-counter*)
          (setf (org-gantt-context-changed ctx) t)  ; Initialize to enter loop

          ;; Parse headlines and store in context
          (setq org-gantt-info-list (org-gantt-crawl-headlines parsed-data))
          (when (not parsed-data)
            (error "Could not find element with :ID: %s" id))
          (setf (org-gantt-context-info-list ctx) org-gantt-info-list)

          ;; Run all propagation phases
          (org-gantt-propagate-all ctx)

          ;; Update global state from context
          (setq org-gantt-info-list (org-gantt-context-info-list ctx))
          (setq *org-gantt-link-hash* (org-gantt-context-link-hash ctx))
          (setq *org-gantt-id-counter* (org-gantt-context-id-counter ctx)))
                                        ;	(dbgmessage "%s" (pp org-gantt-info-list))
        (setq start-date-time
              (or start-date-time
                  (org-gantt-get-extreme-date-il
                   org-gantt-info-list
                   (lambda (info) (gethash org-gantt-start-prop info))
                   #'org-gantt-time-less-p)))
        (setq end-date-time
              (or end-date-time
                  (org-gantt-get-extreme-date-il
                   org-gantt-info-list
                   (lambda (info) (gethash org-gantt-end-prop info))
                   #'org-gantt-time-larger-p)))
        (let ((body (concat
                     (when tikz-options
                       (concat
                        "\\begin{tikzpicture}["
                        tikz-options
                        "]\n"))
                     "\\begin{ganttchart}[time slot format=isodate, "
                     "vgrid="
                     (org-gantt-get-vgrid-style start-date-time weekend-style workday-style)
                     (when hgrid
                       ", hgrid")
                     (when compress
                       ", compress calendar")
                     (when today-value
                       (concat
                        ", today="
                        (format-time-string
                         "%Y-%m-%d"
                         (if (equal t today-value)
                             (current-time)
                           (org-gantt-timestamp-to-time (org-parse-time-string today-value))))))
                     (when additional-parameters
                       (concat ", " additional-parameters))
                     "]{"
                     (format-time-string "%Y-%m-%d" start-date-time)
                     "}{"
                     (format-time-string "%Y-%m-%d" end-date-time)
                     "}\n"
                     "\\gantttitlecalendar{"
                     (if compress
                         compressed-titlecalendar
                       titlecalendar)
                     "}\\\\\n"
                     (org-gantt-info-list-to-pgfgantt org-gantt-info-list start-date-time 1 nil nil t)
                     (org-gantt-linkhash-to-pgfgantt *org-gantt-link-hash*)
                     "\\end{ganttchart}"
                     (when tikz-options
                       "\n\\end{tikzpicture}"))))
          (if (plist-get params :file)
              (progn
                (dbgmessage "%s" (org-gantt-plist-to-alist (append params (list :fit t :headers "\\usepackage{pgfgantt}\n"))))
                (dbgmessage "%s" body)
                (dbgmessage "%s" (org-babel-merge-params (org-gantt-plist-to-alist (append params (list :fit t :headers "\\usepackage{pgfgantt}\n")))))
                (org-babel-execute:latex body
                                         (org-babel-merge-params (org-gantt-plist-to-alist (append params (list :fit t :headers "\\usepackage{pgfgantt}\n")))))
                (insert (org-babel-result-to-file (plist-get params :file)))
                (org-redisplay-inline-images))
            (insert body))
          )))))

(defun org-insert-dblock:org-gantt-chart (filename)
  "Insert org-gantt dynamic block."
  (interactive "FImage output filename: ")
  (org-create-dblock
   (list :name "org-gantt"
         :file filename
         :imagemagick t
         :tikz-options "scale=1.5, every node/.style={scale=1.5}"
         :weekend-style "{draw=blue!10, line width=1pt}"
         :workday-style "{draw=blue!5, line width=.75pt}"
         :show-progress 'if-value
         :progress-source 'cookie-clocksum
         :no-date-headlines 'inactive
         :parameters "y unit title=.7cm, y unit chart=.9cm"
         :tags-group-style '(("test"."group label font=\\color{blue}")
                             ("toast"."group label font=\\color{green}"))
         :tags-bar-style '(("test"."bar label font=\\color{blue}")
                           ("toast"."bar label font=\\color{green}")))))

(provide 'org-gantt)

;;; org-gantt.el ends here
