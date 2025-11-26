;;; org-gantt-context.el --- Context structure for org-gantt -*- lexical-binding: t -*-

;; Copyright (C) 2025

;;; Commentary:
;;
;; This file defines the `org-gantt-context` structure that holds all state
;; for a single Gantt chart generation. By encapsulating state in this struct
;; instead of global variables, we enable:
;;
;; - Multiple charts to be generated concurrently
;; - Easier testing with isolated state
;; - Clearer data flow through the codebase
;;
;; The context is created at the start of chart generation and threaded
;; through all processing functions.

;;; Code:

(require 'cl-lib)
(require 'org-gantt-config)

(cl-defstruct (org-gantt-context
               (:constructor org-gantt-context-create)
               (:copier nil))
  "Context for org-gantt chart generation.

This struct holds all state that was previously stored in global variables.
It is created once per chart generation and passed through all functions."

  ;; Configuration (set at creation, read-only during processing)
  (hours-per-day org-gantt-default-hours-per-day
                 :type integer
                 :documentation "Working hours per day for effort calculations.")

  (work-free-days org-gantt-default-work-free-days
                  :type list
                  :documentation "List of day-of-week numbers that are not workdays.
0 = Sunday, 6 = Saturday.")

  ;; Options plist (set from chart parameters)
  (options nil
           :type list
           :documentation "Property list of chart generation options.
Includes :no-date-headlines, :incomplete-date-headlines, :show-progress, etc.")

  ;; Mutable state during processing
  (changed nil
           :type boolean
           :documentation "Flag indicating if propagation made any changes.
Used to determine when the fixed-point iteration should stop.")

  (id-counter 0
              :type integer
              :documentation "Counter for generating unique element IDs.
Incremented each time a new ID is needed.")

  (link-hash nil
             :documentation "Hash table mapping source IDs to lists of target IDs.
Built during propagation, used during rendering to create \\ganttlink commands.")

  ;; Processed data
  (info-list nil
             :type list
             :documentation "List of parsed headline info hash tables.
Each hash table contains :name, :startdate, :enddate, :effort, :subelements, etc."))

(defun org-gantt-context-init (&optional hours-per-day work-free-days)
  "Create and initialize a new org-gantt context.

HOURS-PER-DAY defaults to `org-gantt-default-hours-per-day'.
WORK-FREE-DAYS defaults to `org-gantt-default-work-free-days'.

Returns an initialized context ready for use."
  (org-gantt-context-create
   :hours-per-day (or hours-per-day org-gantt-default-hours-per-day)
   :work-free-days (or work-free-days org-gantt-default-work-free-days)
   :options nil
   :changed t  ; Start true to enter propagation loop
   :id-counter 0
   :link-hash (make-hash-table :test 'equal)
   :info-list nil))

(defun org-gantt-context-reset-for-propagation (ctx)
  "Reset CTX state for a new propagation iteration.
Sets the changed flag to nil."
  (setf (org-gantt-context-changed ctx) nil))

(defun org-gantt-context-mark-changed (ctx)
  "Mark CTX as having changed during propagation."
  (setf (org-gantt-context-changed ctx) t))

(defun org-gantt-context-next-id (ctx)
  "Generate and return the next unique ID from CTX.
Increments the internal counter."
  (let ((id (org-gantt-context-id-counter ctx)))
    (setf (org-gantt-context-id-counter ctx) (1+ id))
    (format "org-gantt-id-%d" id)))

(defun org-gantt-context-add-link (ctx from-id to-id)
  "Add a link from FROM-ID to TO-ID in CTX's link hash.
Links are stored as FROM-ID -> (list of TO-IDs)."
  (let* ((hash (org-gantt-context-link-hash ctx))
         (existing (gethash from-id hash)))
    (puthash from-id (cons to-id existing) hash)))

(defun org-gantt-context-get-option (ctx key &optional default)
  "Get option KEY from CTX's options plist.
Returns DEFAULT if KEY is not present."
  (let ((options (org-gantt-context-options ctx)))
    (if (plist-member options key)
        (plist-get options key)
      default)))

(provide 'org-gantt-context)
;;; org-gantt-context.el ends here
