;;; org-gantt-config.el --- Configuration for org-gantt -*- lexical-binding: t -*-

;; Copyright (C) 2025

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
;; This file contains all user-facing configuration options and internal
;; constants for org-gantt. It should be loaded before any other org-gantt
;; modules.

;;; Code:

(defgroup org-gantt nil "Customization of org-gantt."
  :group 'org)

;;; User Configuration

(defcustom org-gantt-default-hours-per-day 8
  "The default hours in a workday.
Use :hours-per-day to overwrite this value for individual gantt charts."
  :type '(integer)
  :group 'org-gantt)

(defcustom org-gantt-default-work-free-days '(0 6)
  "The default days on which no work is done.
Stored in a list of day-of-week numbers,
starting with sunday = 0, ending with saturday = 6.
Use :work-free-days to overwrite this value for individual gantt charts."
  :type '(repeat integer)
  :group 'org-gantt)

(defcustom org-gantt-default-weekend-style "{black}"
  "The default style for the weekend lines.
Use :weekend-style to overwrite this value for individual gantt charts."
  :type '(string)
  :group 'org-gantt)

(defcustom org-gantt-default-workday-style "{dashed}"
  "The default style for the workday lines.
Use :workday-style to overwrite this value for individual gantt charts."
  :type '(string)
  :group 'org-gantt)

(defcustom org-gantt-default-title-calendar "year, month=name, day"
  "The default style for the title calendar.
Use :title-calendar to overwrite this value for individual gantt charts."
  :type '(string)
  :group 'org-gantt)

(defcustom org-gantt-default-compressed-title-calendar "year, month"
  "The default style for the title calendar, if the chart is compressed.
Use :compressed-title-calendar to overwrite this value for individual gantt charts."
  :type '(string)
  :group 'org-gantt)

(defcustom org-gantt-default-show-progress nil
  "The default for showing a progress.
nil means progress is not shown.
always means progress is always shown (0, if no value exists).
if-exists means progress is only shown if a value exists."
  :type '(symbol)
  :options '(nil if-exists always)
  :group 'org-gantt)

(defcustom org-gantt-default-progress-source 'cookie-clocksum
  "The default source of the progress.
Determines how the progress is calculated.
clocksum means use clocksum values only.
cookie means use progress-cookies only
clocksum-cookie means prioritize clocksums,
but use progress cookie, if no clocksum exists.
cookie-clocksum means prioritize cookie,
but use clocksum value, if no progress cookie exists."
  :type '(symbol)
  :options '(clocksum cookie clocksum-cookie cookie-clocksum))

(defcustom org-gantt-default-incomplete-date-headlines 'inactive
  "The default treatment for headlines that have either deadline or schedule
\(also computed\), but not both.
'keep will place the headline normally, with a length of 0.
'inactive will place the headline, but distinguish it via inactive-style.
'ignore will not place the headline onto the chart."
  :type '(symbol)
  :options '(keep inactive ignore)
  :group 'org-gantt)

(defcustom org-gantt-default-no-date-headlines 'inactive
  "The default treatment for headlines that have neither deadline nor schedule.
'keep will place the headline at the first day, with a length of 0.
'inactive will place the headline, but distinguish it via
inactive-bar-style and inactive-group-style.
'ignore will not place the headline onto the chart."
  :type '(symbol)
  :options '(keep inactive ignore)
  :group 'org-gantt)

(defcustom org-gantt-default-inactive-bar-style "bar label font=\\color{black!50}"
  "The default styles for bars that are considered inactive by incomplete-date-headlines
or no-date-headlines."
  :type '(string)
  :group 'org-gantt)

(defcustom org-gantt-default-inactive-group-style "group label font=\\color{black!50}"
  "The default styles for groups that are considered inactive by incomplete-date-headlines
or no-date-headlines."
  :type '(string)
  :group 'org-gantt)

(defcustom org-gantt-default-tags-bar-style nil
  "An alist that associates tags to styles for bars in the form (tag . style)."
  :type '(alist :key-type string :value-type string)
  :group 'org-gantt)

(defcustom org-gantt-default-tags-group-style nil
  "An alist that associates tags to styles for groups in the form (tag . style)."
  :type '(alist :key-type string :value-type string)
  :group 'org-gantt)

(defcustom org-gantt-default-tag-style-effect 'subheadlines
  "The effect of tag styles.
If value is 'current, a tag style is only applied to headlines
with the appropriate tag.
If value is 'subheadlines, it applies to the headline and
all its subheadlines."
  :type '(symbol)
  :options '(subheadlines 'current)
  :group 'org-gantt)

(defcustom org-gantt-default-use-tags nil
  "A list of tags for which the bars/groups should be printed.
All headlines without those tags will not be printed.
nil means print all."
  :type '(repeat string)
  :group 'org-gantt)

(defcustom org-gantt-default-ignore-tags nil
  "A list of tags for which the bars/groups should not be printed.
All headlines with those tags will not be printed.
Can not be (sensibly) used in combination with org-gantt-default-use-tags.
nil means print all."
  :type '(repeat string)
  :group 'org-gantt)

(defcustom org-gantt-default-milestone-tags '("milestone")
  "A list of tags, for which a headline is printed as a milestone."
  :type '(repeat string)
  :group 'org-gantt)

(defcustom org-gantt-default-linked-to-property-keys '(:LINKED-TO)
  "A list of strings that are accepted as property keys for linked elements."
  :type '(repeat string)
  :group 'org-gantt)

(defcustom org-gantt-default-maxlevel nil
  "The default maximum levels used for org-gantt charts.
nil means the complete tree is used."
  :type '(choice integer (const nil))
  :group 'org-gantt)

(defcustom org-gantt-output-debug-dates nil
  "Decides whether to put out some extra information about the computed dates
as a latex comment after each gantt bar."
  :type '(boolean)
  :group 'org-gantt)

(defcustom org-gantt-default-hgrid nil
  "The option :hgrid decides whether hgrid lines are shown.
This is the default setting for :hgrid."
  :type '(boolean)
  :group 'org-gantt)

;;; Internal Constants

(defconst org-gantt-start-prop :startdate
  "What is used as the start property in the constructed property list.")

(defconst org-gantt-end-prop :enddate
  "What is used as the end property in the constructed property list.")

(defconst org-gantt-effort-prop :effort
  "What is used as the effort property in the constructed property list.")

(defconst org-gantt-clocksum-prop :clocksum
  "What is used as the effort property in the constructed property list.")

(defconst org-gantt-progress-prop :progress
  "What is used as the progress property in the constructed property list.")

(defconst org-gantt-stats-cookie-prop :stats-cookie
  "What is used as the statistics cooke, i.e. [X%], [X/Y]")

(defconst org-gantt-tags-prop :tags
  "What is used as the tags property in the constructed property list.")

(defconst org-gantt-parent-tags-prop :parent-tags
  "What is used as the property for propagated parent tags.")

(defconst org-gantt-id-prop :id
  "What is used as the the property for storing ids.")

(defconst org-gantt-blocker-prop :blocker
  "What is used as the property for the blocker property.")

(defconst org-gantt-trigger-prop :trigger
  "What is used as the property for the trigger property.")

(defconst org-gantt-linked-to-prop :linked-to
  "What is used as the property for the linked-to elements")

(provide 'org-gantt-config)
;;; org-gantt-config.el ends here
