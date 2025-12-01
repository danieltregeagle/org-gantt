;;; org-gantt-time.el --- Time calculations for org-gantt -*- lexical-binding: t -*-

;; Copyright (C) 2025

;;; Commentary:
;;
;; Time and date calculation functions for org-gantt. All functions
;; in this module are pure - they accept configuration as explicit
;; parameters rather than reading from global state.
;;
;; Key concepts:
;; - hours-per-day: Working hours in a day (typically 8)
;; - work-free-days: List of day-of-week numbers (0=Sun, 6=Sat)
;; - worktime: Time that accounts for non-working days

;;; Code:

(require 'cl-lib)
(require 'calendar)
(require 'org-gantt-config)
(require 'org-gantt-util)

;;; Time Conversion

(defun org-gantt-time-hours-to-time (hours-per-day)
  "Convert HOURS-PER-DAY to an Emacs time value."
  (seconds-to-time (* 3600 hours-per-day)))

(defun org-gantt-time-from-timestamp (timestamp &optional use-end)
  "Convert org TIMESTAMP to Emacs time.
If USE-END is non-nil, use the end values of a timestamp range."
  (and timestamp
       (if use-end
           (encode-time 0
                        (or (org-element-property :minute-end timestamp) 0)
                        (or (org-element-property :hour-end timestamp) 0)
                        (org-element-property :day-end timestamp)
                        (org-element-property :month-end timestamp)
                        (org-element-property :year-end timestamp))
         (encode-time 0
                      (or (org-element-property :minute-start timestamp) 0)
                      (or (org-element-property :hour-start timestamp) 0)
                      (org-element-property :day-start timestamp)
                      (org-element-property :month-start timestamp)
                      (org-element-property :year-start timestamp)))))

(defun org-gantt-time-from-strings
    (seconds-string minutes-string &optional hours-string
                    days-string weeks-string months-string years-string
                    hours-per-day work-free-days)
  "Convert time component strings to an Emacs time value.
SECONDS-STRING, MINUTES-STRING, HOURS-STRING, DAYS-STRING, WEEKS-STRING,
MONTHS-STRING, and YEARS-STRING are strings converted to numbers.
HOURS-PER-DAY defaults to 8. WORK-FREE-DAYS is list of non-working days.
Returns time value or nil if all components are zero."
  (let* ((hpd (or hours-per-day 8))
         (wfd (or work-free-days '(0 6)))
         (time
          (seconds-to-time
           (+ (org-gantt-util-string-to-number seconds-string)
              (* 60 (org-gantt-util-string-to-number minutes-string))
              (* 3600 (org-gantt-util-string-to-number hours-string))
              (* 3600 hpd (org-gantt-util-string-to-number days-string))
              (* 3600 hpd (- 7 (length wfd)) (org-gantt-util-string-to-number weeks-string))
              (* 3600 hpd 30 (org-gantt-util-string-to-number months-string))
              (* 3600 hpd 30 12 (org-gantt-util-string-to-number years-string))))))
    (if (= 0 (apply '+ time))
        nil
      time)))

(defun org-gantt-time-from-effort (effort &optional hours-per-day work-free-days)
  "Parse EFFORT string and return as Emacs time.
EFFORT is a string like \"2d 4:00\" or \"1w\".
HOURS-PER-DAY defaults to 8. WORK-FREE-DAYS defaults to weekend.
The returned time represents a time difference."
  (and effort
       (let* ((years-string (org-gantt-util-substring-if effort 0 (string-match "y" effort)))
              (msp (if years-string (match-end 0) 0))
              (months-string (org-gantt-util-substring-if effort msp (string-match "m" effort)))
              (wsp (if months-string (match-end 0) msp))
              (weeks-string (org-gantt-util-substring-if effort wsp (string-match "w" effort)))
              (dsp (if weeks-string (match-end 0) wsp))
              (days-string (org-gantt-util-substring-if effort dsp (string-match "d" effort)))
              (hsp (if days-string (match-end 0) dsp))
              (hours-string (org-gantt-util-substring-if effort hsp (string-match ":" effort)))
              (minsp (if hours-string (match-end 0) hsp))
              (minutes-string (org-gantt-util-substring-if effort minsp (length effort))))
         (org-gantt-time-from-strings "0"
                                      minutes-string hours-string
                                      days-string weeks-string
                                      months-string years-string
                                      hours-per-day work-free-days))))

;;; Workday Calculations

(defun org-gantt-time-is-workday (time work-free-days)
  "Return non-nil if TIME is a workday.
WORK-FREE-DAYS is a list of day-of-week numbers (0=Sunday, 6=Saturday).
Does not consider holidays."
  (let ((dow (string-to-number (format-time-string "%w" time))))
    (not (member dow work-free-days))))

(defun org-gantt-time-day-start (time &optional hours-per-day)
  "Return the start of the day containing TIME (midnight).
HOURS-PER-DAY is ignored but accepted for interface consistency."
  (let ((dt (decode-time time)))
    (encode-time 0 0 0 (nth 3 dt) (nth 4 dt) (nth 5 dt))))

(defun org-gantt-time-day-end (time hours-per-day)
  "Return the end of the workday containing TIME.
HOURS-PER-DAY specifies the workday length."
  (let ((dt (decode-time time)))
    (encode-time 0 0 hours-per-day
                 (nth 3 dt) (nth 4 dt) (nth 5 dt))))

(defun org-gantt-time-change-workdays (time ndays change-fn work-free-days)
  "Add or subtract NDAYS workdays to TIME.
CHANGE-FN is `time-add' or `time-subtract'.
WORK-FREE-DAYS defines non-working days.
Returns the resulting time. Does not consider holidays."
  (cl-assert (>= ndays 0) t "Trying to add negative days to timestamp.")
  (let ((oneday (days-to-time 1))
        (curtime time))
    (while (/= 0 ndays)
      (setq curtime (funcall change-fn curtime oneday))
      (when (org-gantt-time-is-workday curtime work-free-days)
        (setq ndays (- ndays 1))))
    curtime))

;;; Complex Time Arithmetic

(defun org-gantt-time-add-worktime (time change-time hours-per-day work-free-days)
  "Add CHANGE-TIME work time to TIME.
Respects HOURS-PER-DAY and WORK-FREE-DAYS.
Returns the new time after adding work time."
  (let* ((dt (decode-time time))
         (day-end (encode-time 0 0 hours-per-day
                               (nth 3 dt) (nth 4 dt) (nth 5 dt)))
         (rest-time (time-subtract day-end time))
         (one-day (days-to-time 1)))
    (if (time-less-p change-time rest-time)
        ;; Change fits in current day
        (time-add time change-time)
      ;; Need to span multiple days
      (let* ((next-day-d (decode-time
                          (org-gantt-time-change-workdays time 1 #'time-add work-free-days)))
             (next-day (encode-time 0 0 0 (nth 3 next-day-d)
                                    (nth 4 next-day-d) (nth 5 next-day-d)))
             (rest-change (time-subtract change-time rest-time))
             (dc (decode-time rest-change))
             (rest-min (+ (nth 1 dc) (* 60 (nth 2 dc)))))
        ;; Consume full working days
        (while (> rest-min (* 60 hours-per-day))
          (setq next-day (org-gantt-time-change-workdays next-day 1 #'time-add work-free-days))
          (setq rest-change (time-subtract rest-change (seconds-to-time (* 3600 hours-per-day))))
          (setq dc (decode-time rest-change))
          (setq rest-min (+ (nth 1 dc) (* 60 (nth 2 dc)))))
        ;; Extra cleanup for any remaining full days
        (while (time-less-p one-day rest-change)
          (setq next-day (org-gantt-time-change-workdays next-day 1 #'time-add work-free-days))
          (setq rest-change (time-subtract rest-change one-day)))
        ;; Add remaining time to final day
        (time-add next-day rest-change)))))

(defun org-gantt-time-change-worktime (time change-time time-changer
                                            day-start-getter day-end-getter
                                            hours-per-day work-free-days)
  "Add or subtract CHANGE-TIME to TIME, accounting for workdays.
TIME-CHANGER is `time-add' or `time-subtract'.
DAY-START-GETTER and DAY-END-GETTER are functions taking (time hours-per-day).
HOURS-PER-DAY and WORK-FREE-DAYS define working time.
Returns the new time."
  (let* ((day-end (funcall day-end-getter time hours-per-day))
         (rest-time (org-gantt-util-time-difference day-end time))
         (one-day (days-to-time 1)))
    (if (time-less-p change-time rest-time)
        ;; Change fits in current day
        (funcall time-changer time change-time)
      ;; Need to span multiple days
      (let* ((next-day (funcall day-start-getter
                                (org-gantt-time-change-workdays time 1 time-changer work-free-days)
                                hours-per-day))
             (rest-change (time-subtract change-time rest-time))
             (rest-sec (round (time-to-seconds rest-change))))
        ;; Consume full working days
        (while (> rest-sec (* 3600 hours-per-day))
          (setq next-day (org-gantt-time-change-workdays next-day 1 time-changer work-free-days))
          (setq rest-change (time-subtract rest-change (seconds-to-time (* 3600 hours-per-day))))
          (setq rest-sec (round (time-to-seconds rest-change))))
        ;; Extra cleanup for any remaining full days
        (while (time-less-p one-day rest-change)
          (setq next-day (org-gantt-time-change-workdays next-day 1 time-changer work-free-days))
          (setq rest-change (time-subtract rest-change one-day)))
        ;; Add/subtract remaining time to final day
        (funcall time-changer next-day rest-change)))))

(defun org-gantt-time-next-start (endtime hours-per-day work-free-days)
  "Get the time where the next task should start.
ENDTIME is the time where the previous task ends.
HOURS-PER-DAY and WORK-FREE-DAYS define working time."
  (let* ((dt (decode-time endtime))
         (hours (nth 2 dt))
         (minutes (nth 1 dt)))
    (if (and (= hours-per-day hours)
             (= 0 minutes))
        ;; At end of workday, advance to start of next workday
        (org-gantt-time-change-worktime
         endtime (seconds-to-time (* 3600 (- 24 hours-per-day)))
         #'time-add
         #'org-gantt-time-day-start #'org-gantt-time-day-end
         hours-per-day work-free-days)
      endtime)))

(defun org-gantt-time-prev-end (starttime hours-per-day work-free-days)
  "Get the time where the previous task should end.
STARTTIME is the time where the next task starts.
HOURS-PER-DAY and WORK-FREE-DAYS define working time."
  (let* ((dt (decode-time starttime))
         (hours (nth 2 dt))
         (minutes (nth 1 dt)))
    (if (and (= hours-per-day hours)
             (= 0 minutes))
        ;; At end of workday, go back to end of previous workday
        (org-gantt-time-change-worktime
         starttime (seconds-to-time (* 3600 (- 24 hours-per-day)))
         #'time-subtract
         #'org-gantt-time-day-end #'org-gantt-time-day-start
         hours-per-day work-free-days)
      starttime)))

;;; Time Normalization

(defun org-gantt-time-downcast-end (endtime hours-per-day work-free-days)
  "Downcast ENDTIME to the previous day if sensible.
If ENDTIME is at midnight, change it to HOURS-PER-DAY of the previous day.
WORK-FREE-DAYS defines non-working days."
  (let* ((dt (decode-time endtime))
         (hours (nth 2 dt))
         (minutes (nth 1 dt)))
    (if (and (= 0 hours)
             (= 0 minutes))
        ;; Midnight - move to end of previous workday
        (time-add (org-gantt-time-change-workdays endtime 1 #'time-subtract work-free-days)
                  (org-gantt-time-hours-to-time hours-per-day))
      endtime)))

(defun org-gantt-time-upcast-start (starttime hours-per-day work-free-days)
  "Upcast STARTTIME to the next day if sensible.
If STARTTIME is at HOURS-PER-DAY, change it to midnight of the next day.
WORK-FREE-DAYS defines non-working days."
  (let* ((dt (decode-time starttime))
         (hours (nth 2 dt))
         (minutes (nth 1 dt)))
    (if (and (= 0 minutes)
             (= hours-per-day hours))
        ;; At end of workday - move to start of next workday
        (time-subtract (org-gantt-time-change-workdays starttime 1 #'time-add work-free-days)
                       (org-gantt-time-hours-to-time hours-per-day))
      starttime)))

;;; Ratio Calculations (for rendering)

(defun org-gantt-time-day-ratio (time hours-per-day)
  "Return the ratio of a workday that is in the hour-minute part of TIME.
HOURS-PER-DAY defines the workday length. Returns 0 if TIME is nil."
  (if time
      (let* ((dt (decode-time time))
             (hours (nth 2 dt))
             (minutes (nth 1 dt))
             (minsum (+ minutes (* 60 hours))))
        (/ (float minsum) (* 60 hours-per-day)))
    0))

(defun org-gantt-time-month-ratio (time)
  "Return the ratio of the month that is passed in TIME.
Returns 0 if TIME is nil."
  (if time
      (let* ((dt (decode-time time))
             (day (nth 3 dt))
             (month (nth 4 dt))
             (year (nth 5 dt))
             (days-in-month (calendar-last-day-of-month month year)))
        (/ (float day) (float days-in-month)))
    0))

(provide 'org-gantt-time)
;;; org-gantt-time.el ends here
