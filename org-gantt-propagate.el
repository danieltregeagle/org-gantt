;;; org-gantt-propagate.el --- Property propagation for org-gantt -*- lexical-binding: t -*-

;; Copyright (C) 2025

;;; Commentary:
;;
;; Functions for propagating properties through the gantt-info tree.
;;
;; Propagation runs in a fixed-point loop until no changes occur:
;; 1. Calculate dates from effort (if effort + one date exists)
;; 2. Propagate ordered dependencies (next task starts when previous ends)
;; 3. Propagate dates upward (parent spans children)
;; 4. Propagate linked-to dependencies (manual links)
;;
;; After date convergence, single-pass propagation for:
;; 5. Effort summation (sum child efforts to parent)
;; 6. Progress computation (from clocksum/effort)
;; 7. Progress summation (weighted by effort)
;; 8. Tag propagation (downward to children)
;;
;; All functions accept the context as their first parameter and
;; use context accessors instead of global variables.

;;; Code:

(require 'cl-lib)
(require 'org-gantt-config)
(require 'org-gantt-context)
(require 'org-gantt-util)
(require 'org-gantt-time)

;;; Main Propagation Entry Point

(defun org-gantt-propagate-all (ctx)
  "Run all propagation phases on CTX.
This is the main entry point for propagation.

Phase 1: Fixed-point iteration for date propagation
Phase 2: Effort summation (single pass)
Phase 3: Progress computation (single pass)
Phase 4: Progress summation (single pass)
Phase 5: Tag propagation (single pass)"

  ;; Phase 1: Date propagation (iterates until stable)
  (org-gantt-propagate-all-dates ctx)

  ;; Phase 2: Sum efforts upward
  (org-gantt-propagate-summation-up
   ctx
   org-gantt-effort-prop
   #'org-gantt-propagate--effort-sum
   nil)  ; don't prioritize sub-sums

  ;; Phase 3: Compute progress from clocksum/effort
  (org-gantt-propagate-compute-progress ctx)

  ;; Phase 4: Sum progress upward (weighted by effort)
  (let ((calc-progress (org-gantt-context-get-option ctx :calc-progress)))
    (org-gantt-propagate-summation-up
     ctx
     org-gantt-progress-prop
     (lambda (hl) (org-gantt-propagate--progress-sum hl calc-progress t))
     t))  ; prioritize sub-sums

  ;; Phase 5: Propagate tags downward
  (org-gantt-propagate-tags-down ctx))

(defun org-gantt-propagate-all-dates (ctx &optional max-iterations)
  "Run all date propagation phases on CTX until stable.
MAX-ITERATIONS limits the loop (default 100).
Returns the number of iterations performed."
  (let ((iterations 0)
        (max-iter (or max-iterations 100)))
    (while (and (< iterations max-iter)
                (org-gantt-context-changed ctx))
      (org-gantt-context-reset-for-propagation ctx)
      (org-gantt-propagate-ds-from-effort ctx)
      (org-gantt-propagate-order-timestamps ctx)
      (org-gantt-propagate-dates-up ctx)
      (org-gantt-propagate-linked-to ctx)
      (cl-incf iterations))
    (when (>= iterations max-iter)
      (warn "org-gantt: propagation did not converge after %d iterations" max-iter))
    iterations))

;;; Date from Effort Propagation

(defun org-gantt-propagate-ds-from-effort (ctx)
  "Calculate dates from effort for all headlines in CTX.
If a headline has effort and either start or end, calculate the missing one."
  (org-gantt-propagate--ds-from-effort-list
   (org-gantt-context-info-list ctx)
   ctx))

(defun org-gantt-propagate--ds-from-effort-list (headline-list ctx)
  "Propagate dates from effort for HEADLINE-LIST using CTX."
  (let ((hours-per-day (org-gantt-context-hours-per-day ctx))
        (work-free-days (org-gantt-context-work-free-days ctx))
        (is-changed nil))
    (dolist (headline headline-list is-changed)
      (let ((start (gethash org-gantt-start-prop headline))
            (end (gethash org-gantt-end-prop headline))
            (effort (gethash org-gantt-effort-prop headline)))
        (cond
         ;; Have start and end and effort - could add validation here
         ((and start end effort)
          nil) ;; FIXME: Calculate if start, end, effort conflict and warn
         ;; Have start and effort, calculate end
         ((and start effort)
          (puthash org-gantt-end-prop
                   (org-gantt-time-change-worktime
                    start effort
                    #'time-add
                    (lambda (time hpd) (org-gantt-time-day-start time hpd))
                    (lambda (time hpd) (org-gantt-time-day-end time hpd))
                    hours-per-day
                    work-free-days)
                   headline)
          (setq is-changed (or is-changed (gethash org-gantt-end-prop headline))))
         ;; Have end and effort, calculate start
         ((and effort end)
          (puthash org-gantt-start-prop
                   (org-gantt-time-change-worktime
                    end effort
                    #'time-subtract
                    (lambda (time hpd) (org-gantt-time-day-end time hpd))
                    (lambda (time hpd) (org-gantt-time-day-start time hpd))
                    hours-per-day
                    work-free-days)
                   headline)
          (setq is-changed (or is-changed (gethash org-gantt-start-prop headline)))))
        ;; Recurse to children
        (setq is-changed
              (or (org-gantt-propagate--ds-from-effort-list
                   (gethash :subelements headline) ctx)
                  is-changed))))
    (when is-changed
      (org-gantt-context-mark-changed ctx))))

;;; Ordered Dependencies

(defun org-gantt-propagate-order-timestamps (ctx)
  "Propagate timestamps for ordered headlines in CTX."
  (let ((result (org-gantt-propagate--order-timestamps-list
                 (org-gantt-context-info-list ctx)
                 nil nil nil ctx)))
    (when result
      (org-gantt-context-mark-changed ctx))))

(defun org-gantt-propagate--order-timestamps-list
    (headline-list is-ordered parent-start parent-end ctx)
  "Process HEADLINE-LIST for ordered propagation.
IS-ORDERED whether the current subheadlines are ordered.
PARENT-START start time of the parent of the current subheadlines.
PARENT-END end time of the parent of the current subheadlines.
CTX is the org-gantt-context.
Returns non-nil if any changes were made."
  (let ((next-start (or (org-gantt-util-gethash org-gantt-start-prop (car headline-list))
                        parent-start))
        (listitem headline-list)
        (headline nil)
        (is-changed nil)
        (hours-per-day (org-gantt-context-hours-per-day ctx))
        (work-free-days (org-gantt-context-work-free-days ctx)))
    (while listitem
      (setq headline (car listitem))
      (when is-ordered
        (setq is-changed
              (or is-changed
                  (and next-start (not (org-gantt-util-gethash org-gantt-start-prop headline)))))
        (puthash org-gantt-start-prop
                 (or (org-gantt-util-gethash org-gantt-start-prop headline) next-start)
                 headline)
        (setq next-start (org-gantt-time-next-start
                          (gethash org-gantt-end-prop headline)
                          hours-per-day
                          work-free-days))
        (setq is-changed
              (or is-changed
                  (and (if (cdr listitem)
                           (org-gantt-time-prev-end
                            (gethash org-gantt-start-prop (cadr listitem))
                            hours-per-day
                            work-free-days)
                         parent-end)
                       (not (org-gantt-util-gethash org-gantt-end-prop headline)))))
        (puthash org-gantt-end-prop
                 (or (org-gantt-util-gethash org-gantt-end-prop headline)
                     (if (cdr listitem)
                         (org-gantt-time-prev-end
                          (gethash org-gantt-start-prop (cadr listitem))
                          hours-per-day
                          work-free-days)
                       parent-end))
                 headline))
      (setq is-changed
            (or
             (org-gantt-propagate--order-timestamps-list
              (gethash :subelements headline)
              (or is-ordered (gethash :ordered headline))
              (gethash org-gantt-start-prop headline)
              (gethash org-gantt-end-prop headline)
              ctx)
             is-changed))
      (setq listitem (cdr listitem)))
    is-changed))

;;; Linked-to Propagation

(defun org-gantt-propagate--find-by-id (headline-list id)
  "Return the first headline in HEADLINE-LIST with id ID.
Is applied to subheadlines (depth-first)."
  (and
   headline-list
   (let* ((headline (car headline-list))
          (cur-id (gethash org-gantt-id-prop headline))
          (subheadlines (gethash :subelements headline)))
     (if (equal cur-id id)
         headline
       (or (org-gantt-propagate--find-by-id subheadlines id)
           (org-gantt-propagate--find-by-id (cdr headline-list) id))))))

(defun org-gantt-propagate-linked-to (ctx)
  "Propagate linked-to timestamps using context CTX."
  (org-gantt-propagate--linked-to-recurse
   (org-gantt-context-info-list ctx)
   (org-gantt-context-info-list ctx)
   ctx))

(defun org-gantt-propagate--linked-to-recurse (headline-list complete-list ctx)
  "Propagate the end-times for linked-to headlines in HEADLINE-LIST.
Propagates endtime of a headline as start time of its linked-to headlines,
for all that do not already have start times.
COMPLETE-LIST is the full list of headlines for ID lookup.
CTX is the org-gantt-context."
  (let ((hours-per-day (org-gantt-context-hours-per-day ctx))
        (work-free-days (org-gantt-context-work-free-days ctx)))
    (dolist (headline headline-list headline-list)
      (let ((linked-ids (gethash org-gantt-linked-to-prop headline))
            (orig-id (gethash org-gantt-id-prop headline)))
        (when linked-ids
          (org-gantt-util-debug-message "FOUND ids %s" linked-ids))
        (dolist (linked-id linked-ids)
          (let ((found-headline
                 (org-gantt-propagate--find-by-id complete-list linked-id)))
            (org-gantt-util-debug-message "FOUND headline %s" found-headline)
            (when (and found-headline
                       (not (gethash org-gantt-start-prop found-headline))
                       (gethash org-gantt-end-prop headline))
              (org-gantt-context-mark-changed ctx)
              (org-gantt-util-debug-message "PROPAGATING linked-to %s" found-headline)
              (org-gantt-context-add-link ctx orig-id linked-id)
              (puthash
               org-gantt-start-prop
               (org-gantt-time-next-start
                (gethash org-gantt-end-prop headline)
                hours-per-day
                work-free-days)
               found-headline))))
        (org-gantt-propagate--linked-to-recurse
         (gethash :subelements headline) complete-list ctx)))))

;;; Upward Date Propagation

(defun org-gantt-propagate--first-child-start (headline)
  "Gets the start time of the first subelement of HEADLINE (or its subelement)."
  (and headline
       (let ((first-sub (car (gethash :subelements headline))))
         (or (org-gantt-util-gethash org-gantt-start-prop first-sub)
             (org-gantt-propagate--aggregate-start first-sub t)))))

(defun org-gantt-propagate--last-child-end (headline)
  "Gets the end time of the last subelement of HEADLINE (or its subelement)."
  (and headline
       (let ((last-sub (car (last (gethash :subelements headline)))))
         (or (org-gantt-util-gethash org-gantt-end-prop last-sub)
             (org-gantt-propagate--aggregate-end last-sub t)))))

(defun org-gantt-propagate--aggregate-start (headline ordered)
  "Gets the start time of HEADLINE.
The start time is the start property iff it exists.
It is the start of the first subheadline, if ORDERED is true.
Otherwise it is the first start of all the subheadlines or their subheadlines."
  (or (org-gantt-util-gethash org-gantt-start-prop headline)
      (if ordered
          (org-gantt-propagate--first-child-start headline)
        (org-gantt-propagate--extreme-in-children
         headline
         #'org-gantt-util-time-less-p
         #'org-gantt-propagate--aggregate-start
         ordered))))

(defun org-gantt-propagate--aggregate-end (headline ordered)
  "Gets the end time of HEADLINE.
The end time is the end property iff it exists.
It is the end of the last subheadline, if ORDERED is true.
Otherwise it is the last end of all the subheadlines or their subheadlines."
  (or (org-gantt-util-gethash org-gantt-end-prop headline)
      (if ordered
          (org-gantt-propagate--last-child-end headline)
        (org-gantt-propagate--extreme-in-children
         headline
         #'org-gantt-util-time-larger-p
         #'org-gantt-propagate--aggregate-end
         ordered))))


(defun org-gantt-propagate--extreme-in-children (headline comparator time-getter ordered)
  "Find extreme (min/max) time among children of HEADLINE.
COMPARATOR determines min (#\='org-gantt-util-time-less-p) or
max (#\='org-gantt-util-time-larger-p).
TIME-GETTER recursively extracts time from each child.
ORDERED controls whether to use ordered semantics in recursion.
Returns the extreme time value or nil if no children have times."
  (when headline
    (let ((children (gethash :subelements headline)))
      (when children
        (let ((times (delq nil (mapcar (lambda (child)
                                         (funcall time-getter child ordered))
                                       children))))
          (when times
            (car (sort times comparator))))))))

(defun org-gantt-propagate-dates-up (ctx)
  "Propagate start and end time from subelements in CTX."
  (let ((result (org-gantt-propagate--dates-up-list
                 (org-gantt-context-info-list ctx)
                 nil)))
    (when result
      (org-gantt-context-mark-changed ctx))))

(defun org-gantt-propagate--dates-up-list (headline-list &optional ordered)
  "Propagate start and end time from subelements in HEADLINE-LIST.
ORDERED determines whether the current list is ordered in recursive calls.
Returns non-nil if any changes were made."
  (let ((is-changed nil))
    (dolist (headline headline-list is-changed)
      (let* ((cur-ordered (or ordered (gethash :ordered headline)))
             (start (gethash org-gantt-start-prop headline))
             (end (gethash org-gantt-end-prop headline))
             (subheadline-start (org-gantt-propagate--aggregate-start headline cur-ordered))
             (subheadline-end (org-gantt-propagate--aggregate-end headline cur-ordered)))
        (puthash org-gantt-start-prop
                 subheadline-start
                 headline)
        (puthash org-gantt-end-prop
                 subheadline-end
                 headline)
        (setq is-changed
              (or is-changed
                  (not (equal start subheadline-start))
                  (not (equal end subheadline-end))))))))

;;; Effort Summation

(defun org-gantt-propagate--effort-sum (headline)
  "Get the sum of efforts of the subheadlines of HEADLINE."
  (or (org-gantt-util-gethash org-gantt-effort-prop headline)
      (let ((subelements (gethash :subelements headline))
            (effort-sum (seconds-to-time 0)))
        (dolist (ch subelements effort-sum)
          (setq effort-sum
                (time-add effort-sum
                          (org-gantt-propagate--effort-sum ch)))))))

(defun org-gantt-propagate-summation-up (ctx property subsum-getter &optional prioritize-subsums)
  "Propagate summed values from subelements in CTX.
Get the values via PROPERTY.
When the current headline does not have PROPERTY, or
PRIORITIZE-SUBSUMS is non-nil, use SUBSUM-GETTER to get
the summed value from subelements."
  (org-gantt-propagate--summation-up-list
   (org-gantt-context-info-list ctx)
   property
   subsum-getter
   prioritize-subsums))

(defun org-gantt-propagate--summation-up-list (headline-list property subsum-getter prioritize-subsums)
  "Propagate summed values for HEADLINE-LIST.
PROPERTY is the property key to set.
SUBSUM-GETTER is a function that computes the sum from children.
PRIORITIZE-SUBSUMS determines whether to prefer child sums over direct values."
  (dolist (headline headline-list headline-list)
    (let ((value (gethash property headline)))
      (when (or prioritize-subsums (not value))
        (puthash property
                 (funcall subsum-getter headline)
                 headline)))))

;;; Progress Computation

(defun org-gantt-propagate--completion-percent (effort clocksum)
  "Return the percentage of completion of EFFORT as measured by CLOCKSUM."
  (if (and clocksum effort)
      (let ((css (time-to-seconds clocksum))
            (es (time-to-seconds effort)))
        (if (> es 0) (round (* 100 (/ css es))) 0))
    0))

(defun org-gantt-propagate-compute-progress (ctx)
  "Compute the progress (if possible) for all headlines in CTX.
Progress is calculated from clocksum/effort ratio."
  (org-gantt-propagate--compute-progress-list
   (org-gantt-context-info-list ctx)))

(defun org-gantt-propagate--compute-progress-list (headline-list)
  "Compute progress for HEADLINE-LIST recursively."
  (dolist (headline headline-list headline-list)
    (let ((effort (gethash org-gantt-effort-prop headline))
          (clocksum (gethash org-gantt-clocksum-prop headline))
          (subelements (gethash :subelements headline)))
      (when (and effort clocksum)
        (puthash org-gantt-progress-prop
                 (org-gantt-propagate--completion-percent effort clocksum)
                 headline))
      (org-gantt-propagate--compute-progress-list subelements))))

;;; Progress Summation

(defun org-gantt-propagate--progress-sum (headline calc-progress &optional prioritize-subsums)
  "Compute the summation of the progress of the subheadlines of HEADLINE.
The summation is weighted according to the effort of each subheadline.
If CALC-PROGRESS is 'use-larger-100,
subprogresses with an effort > 100 are used completely,
otherwise, a subprogress is used as having a max effort of 100.
If PRIORITIZE-SUBSUMS is non-nil, progress-summations are taken
from subheadlines, even if a headline has a progress."
  (let ((subelements (gethash :subelements headline))
        (progress (gethash org-gantt-progress-prop headline))
        (progress-sum nil)
        (count 0))
    (or (and (not prioritize-subsums)
             (equal calc-progress 'use-larger-100)
             progress)
        (and (not prioritize-subsums)
             progress
             (min 100 progress))
        (dolist (ch subelements (and progress-sum count (round (/ progress-sum count))))
          (let ((subsum (org-gantt-propagate--progress-sum ch calc-progress prioritize-subsums))
                (subeffort (time-to-seconds (gethash :effort ch))))
            (setq count (+ count subeffort))
            (setq progress-sum
                  (cond
                   ((and progress-sum subsum)
                    (+ progress-sum (* subeffort subsum)))
                   (progress-sum progress-sum)
                   (subsum (* subeffort subsum))
                   (t nil)))))
        (and (equal calc-progress 'use-larger-100)
             progress)
        (and progress
             (min 100 progress)))))

;;; Tag Propagation

(defun org-gantt-propagate-tags-down (ctx)
  "Propagate tags downward through the hierarchy in CTX.
Each headline gets :parent-tags set to the combined tags of ancestors."
  (org-gantt-propagate--tags-down-list
   (org-gantt-context-info-list ctx)
   nil))

(defun org-gantt-propagate--tags-down-list (headline-list parent-tags)
  "Propagate PARENT-TAGS to HEADLINE-LIST and recurse."
  (dolist (headline headline-list headline-list)
    (puthash org-gantt-parent-tags-prop parent-tags headline)
    (org-gantt-propagate--tags-down-list
     (gethash :subelements headline)
     (append parent-tags (gethash org-gantt-tags-prop headline)))))

(provide 'org-gantt-propagate)
;;; org-gantt-propagate.el ends here
