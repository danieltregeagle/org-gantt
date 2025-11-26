;;; org-gantt-parse.el --- Org headline parsing for org-gantt -*- lexical-binding: t -*-

;; Copyright (C) 2025

;;; Commentary:
;;
;; Functions for parsing org-mode headlines into gantt-info structures.
;;
;; A gantt-info is a hash table containing:
;; - :name - headline text
;; - :startdate - start time (Emacs time or nil)
;; - :enddate - end time (Emacs time or nil)
;; - :effort - effort as Emacs time
;; - :clocksum - clocked time as Emacs time
;; - :progress - completion percentage
;; - :stats-cookie - raw statistics cookie string
;; - :tags - list of tags
;; - :parent-tags - tags inherited from parents
;; - :id - unique identifier
;; - :linked-to - list of linked element IDs
;; - :ordered - whether children are ordered
;; - :subelements - list of child gantt-info structures

;;; Code:

(require 'cl-lib)
(require 'org-element)
(require 'org-gantt-config)
(require 'org-gantt-context)
(require 'org-gantt-util)
(require 'org-gantt-time)

;;; Planning Time Extraction

(defun org-gantt-parse-planning-time (element timestamp-type hours-per-day)
  "Get planning time from ELEMENT.
TIMESTAMP-TYPE is :scheduled or :deadline.
HOURS-PER-DAY is used to adjust deadline times that are at midnight."
  (let* ((timestamp
          (org-element-map
              element '(planning headline)
            (lambda (subelement) (org-element-property timestamp-type subelement))
            nil t 'headline))
         (time (org-gantt-time-from-timestamp timestamp))
         (dt (decode-time time))
         (hours (nth 2 dt))
         (minutes (nth 1 dt)))
    (if (and (equal timestamp-type :deadline)
             (= 0 hours)
             (= 0 minutes))
        (time-add time (seconds-to-time (* 3600 hours-per-day)))
      time)))

;;; Headline Traversal

(defun org-gantt-parse-subheadlines (element)
  "Get all direct child headlines of ELEMENT."
  (org-element-map element 'headline
    (lambda (subelement) subelement)
    nil nil 'headline))

;;; Recursive Time Extraction

(defun org-gantt-parse-subheadline-extreme (element comparator time-getter subheadline-getter)
  "Return smallest/largest timestamp of the subheadlines of ELEMENT.
Smallest or largest depends on COMPARATOR.
TIME-GETTER is the recursive function that needs to be called if
the subheadlines have no timestamp.
SUBHEADLINE-GETTER is the function that is used to get subheadlines."
  (and
   element
   (let ((subheadlines (funcall subheadline-getter element)))
     (funcall
      time-getter
      (car
       (sort
        subheadlines
        (lambda (hl1 hl2)
          (funcall comparator
                   (funcall time-getter hl1)
                   (funcall time-getter hl2)))))))))

(defun org-gantt-parse-start-time (element hours-per-day)
  "Get start time of ELEMENT.
Returns scheduled time if present, otherwise earliest child start.
HOURS-PER-DAY is passed through for time calculations."
  (or
   (org-gantt-parse-planning-time element :scheduled hours-per-day)
   (org-gantt-parse-subheadline-extreme
    (cdr element)
    #'org-gantt-util-time-less-p
    (lambda (el) (org-gantt-parse-start-time el hours-per-day))
    #'org-gantt-parse-subheadlines)))

(defun org-gantt-parse-end-time (element hours-per-day)
  "Get end time of ELEMENT.
Returns deadline time if present, otherwise latest child end.
HOURS-PER-DAY is passed through for time calculations."
  (or
   (org-gantt-parse-planning-time element :deadline hours-per-day)
   (org-gantt-parse-subheadline-extreme
    (cdr element)
    #'org-gantt-util-time-larger-p
    (lambda (el) (org-gantt-parse-end-time el hours-per-day))
    #'org-gantt-parse-subheadlines)))

;;; Effort Extraction

(defun org-gantt-parse-subheadlines-effort (element effort-getter element-org-gantt-effort-prop)
  "Return the sum of the efforts of the subheadlines of ELEMENT.
EFFORT-GETTER is the recursive function that needs to be called if
the subheadlines have no effort.
ELEMENT-ORG-GANTT-EFFORT-PROP The property that stores the effort in the headline element."
  (and
   element
   (let ((subheadlines (org-gantt-parse-subheadlines element))
         (time-sum (seconds-to-time 0)))
     (dolist (sh subheadlines (if (= 0 (apply '+ time-sum)) nil time-sum))
       (let ((subtime (funcall effort-getter sh element-org-gantt-effort-prop)))
         (when subtime
           (setq time-sum (time-add time-sum subtime))))))))

(defun org-gantt-parse-effort (element element-org-gantt-effort-prop work-free-days &optional use-subheadlines-effort)
  "Get the effort of the current ELEMENT.
If use-subheadlines-effort is non-nil and element has no effort,
use sum of the efforts of the subelements.
ELEMENT-ORG-GANTT-EFFORT-PROP is the property that stores the effort
in the headline element.
WORK-FREE-DAYS is passed to time conversion functions.
If USE-SUBHEADLINES-EFFORT is non-nil and element does not have a direct effort,
the combined effort of subheadlines is used."
  (let ((effort-time (org-gantt-time-from-effort
                      (org-element-property element-org-gantt-effort-prop element)
                      nil
                      work-free-days)))
    (or effort-time
        (and use-subheadlines-effort
             (org-gantt-parse-subheadlines-effort
              (cdr element)
              (lambda (el prop) (org-gantt-parse-effort el prop work-free-days nil))
              element-org-gantt-effort-prop)))))

;;; Property Extraction

(defun org-gantt-parse-statistics-value (title)
  "Return the statistics value from TITLE if it contains one, else nil."
  (org-element-map (org-element-contents title) 'statistics-cookie
    (lambda (element) (org-element-property :value element))
    nil t t))

(defun org-gantt-parse-flattened-properties (element property-key-list)
  "Return the properties in ELEMENT flattened into one list.
Return properties as defined by any key in PROPERTY-KEY-LIST."
  (let ((property-list nil))
    (dolist (key property-key-list property-list)
      (when (org-element-property key element)
        (setq property-list
              (append (split-string (org-element-property key element) "," t)
                      property-list))))))

;;; Gantt-Info Creation

(defun org-gantt-parse-create-info (element ctx)
  "Create gantt-info hash table from ELEMENT.
CTX is the org-gantt-context providing options and ID generation."
  (let ((gantt-info-hash (make-hash-table))
        (hours-per-day (org-gantt-context-hours-per-day ctx))
        (work-free-days (org-gantt-context-work-free-days ctx)))
    (puthash
     :name (org-element-property :raw-value element)
     gantt-info-hash)
    (puthash :ordered (org-element-property :ORDERED element) gantt-info-hash)
    (puthash org-gantt-start-prop
             (org-gantt-parse-start-time element hours-per-day)
             gantt-info-hash)
    (puthash org-gantt-end-prop
             (org-gantt-parse-end-time element hours-per-day)
             gantt-info-hash)
    (puthash org-gantt-effort-prop
             (or (org-gantt-parse-effort element :EFFORT work-free-days)
                 (and (org-gantt-util-is-in-tags
                       (org-element-property :tags element)
                       (org-gantt-context-get-option ctx :milestone-tags))
                      (seconds-to-time 0)))
             gantt-info-hash)
    (puthash org-gantt-stats-cookie-prop
             (org-gantt-parse-statistics-value
              (org-element-property :title element))
             gantt-info-hash)
    ;; clocksum is computed automatically with 24 hours per day, therefore we use 24.
    (puthash org-gantt-clocksum-prop
             (org-gantt-time-from-effort
              (org-element-property :CLOCKSUM element)
              24
              work-free-days)
             gantt-info-hash)
    (puthash org-gantt-tags-prop (org-element-property :tags element) gantt-info-hash)
    (puthash org-gantt-id-prop
             (or (org-element-property :ID element)
                 (org-gantt-context-next-id ctx))
             gantt-info-hash)
    (puthash org-gantt-linked-to-prop
             (org-gantt-parse-flattened-properties
              element (org-gantt-context-get-option ctx :linked-to-property-keys))
             gantt-info-hash)
    (puthash org-gantt-trigger-prop (org-element-property :TRIGGER element) gantt-info-hash)
    (puthash org-gantt-blocker-prop (org-element-property :BLOCKER element) gantt-info-hash)
    (puthash :subelements (org-gantt-parse-crawl-headlines (cdr element) ctx) gantt-info-hash)
    gantt-info-hash))

(defun org-gantt-parse-crawl-headlines (data ctx)
  "Parse headline tree in DATA, returning list of gantt-info.
CTX is the org-gantt-context."
  (org-element-map data 'headline
    (lambda (hl) (org-gantt-parse-create-info hl ctx))
    nil nil 'headline))

;;; Extrema Finding in Info Lists

(defun org-gantt-parse-extreme-date (info-list time-getter time-comparer)
  "Get the first or last date in INFO-LIST.
TIME-GETTER is used to get the time in an info object.
TIME-COMPARER is used to compare times, i.e. determine first or last.
Returns the first element of the list `sort'ed according to TIME-COMPARER."
  (let ((reslist nil))
    (dolist (info info-list)
      (setq
       reslist
       (cons (funcall time-getter info)
             (cons
              (org-gantt-parse-extreme-date
               (gethash :subelements info) time-getter time-comparer)
              reslist))))
    (car (sort reslist time-comparer))))

(provide 'org-gantt-parse)
;;; org-gantt-parse.el ends here
