;;; org-gantt-util-test.el --- Tests for org-gantt-util -*- lexical-binding: t -*-

;;; Code:

(require 'ert)
(require 'org-gantt-util)

;;; String Utilities

(ert-deftest org-gantt-util-test-chomp ()
  "Test whitespace trimming."
  (should (string= "hello" (org-gantt-util-chomp "  hello  ")))
  (should (string= "hello" (org-gantt-util-chomp "\n\thello\n")))
  (should (string= "hello world" (org-gantt-util-chomp "  hello world  ")))
  (should (string= "hello" (org-gantt-util-chomp "hello")))
  (should (string= "" (org-gantt-util-chomp "")))
  (should (string= "" (org-gantt-util-chomp "   "))))

;;; Hash Table Utilities

(ert-deftest org-gantt-util-test-gethash-normal ()
  "Test normal hash table lookup."
  (let ((ht (make-hash-table :test 'equal)))
    (puthash "key1" "value1" ht)
    (puthash "key2" 42 ht)
    (should (string= "value1" (org-gantt-util-gethash "key1" ht)))
    (should (= 42 (org-gantt-util-gethash "key2" ht)))
    (should (eq nil (org-gantt-util-gethash "missing" ht)))
    (should (eq 'default (org-gantt-util-gethash "missing" ht 'default)))))

(ert-deftest org-gantt-util-test-gethash-nil-table ()
  "Test hash lookup with nil table."
  (should (eq nil (org-gantt-util-gethash "key" nil)))
  (should (eq 'default (org-gantt-util-gethash "key" nil 'default))))

(ert-deftest org-gantt-util-test-hashtable-equal ()
  "Test hash table comparison."
  (let ((ht1 (make-hash-table :test 'equal))
        (ht2 (make-hash-table :test 'equal))
        (ht3 (make-hash-table :test 'equal)))
    (puthash "a" 1 ht1)
    (puthash "b" 2 ht1)
    (puthash "a" 1 ht2)
    (puthash "b" 2 ht2)
    (puthash "a" 1 ht3)
    (puthash "b" 999 ht3)
    (should (org-gantt-util-hashtable-equal ht1 ht2))
    (should-not (org-gantt-util-hashtable-equal ht1 ht3))))

(ert-deftest org-gantt-util-test-equal-primitives ()
  "Test equal function with primitive types."
  (should (org-gantt-util-equal 42 42))
  (should (org-gantt-util-equal "hello" "hello"))
  (should-not (org-gantt-util-equal 42 43))
  (should-not (org-gantt-util-equal "hello" "world")))

(ert-deftest org-gantt-util-test-equal-hash-tables ()
  "Test equal function with hash tables."
  (let ((ht1 (make-hash-table :test 'equal))
        (ht2 (make-hash-table :test 'equal)))
    (puthash "a" 1 ht1)
    (puthash "a" 1 ht2)
    (should (org-gantt-util-equal ht1 ht2))))

(ert-deftest org-gantt-util-test-info-list-equal ()
  "Test info list comparison."
  (let ((ht1 (make-hash-table :test 'equal))
        (ht2 (make-hash-table :test 'equal))
        (ht3 (make-hash-table :test 'equal)))
    (puthash "name" "Task 1" ht1)
    (puthash "name" "Task 1" ht2)
    (puthash "name" "Task 2" ht3)
    (should (org-gantt-util-info-list-equal (list ht1) (list ht2)))
    (should-not (org-gantt-util-info-list-equal (list ht1) (list ht3)))
    (should (org-gantt-util-info-list-equal nil nil))
    (should-not (org-gantt-util-info-list-equal (list ht1) nil))))

;;; Safe Conversion Utilities

(ert-deftest org-gantt-util-test-substring-if ()
  "Test safe substring extraction."
  (should (string= "ell" (org-gantt-util-substring-if "hello" 1 4)))
  (should (eq nil (org-gantt-util-substring-if nil 1 4)))
  (should (eq nil (org-gantt-util-substring-if "hello" nil 4)))
  (should (eq nil (org-gantt-util-substring-if "hello" 1 nil)))
  (should (eq nil (org-gantt-util-substring-if "hello" 4 1))))

(ert-deftest org-gantt-util-test-string-to-number ()
  "Test safe string to number conversion."
  (should (= 42 (org-gantt-util-string-to-number "42")))
  (should (= 0 (org-gantt-util-string-to-number nil)))
  (should (= 3.14 (org-gantt-util-string-to-number "3.14"))))

;;; Time Comparison Utilities

(ert-deftest org-gantt-util-test-time-less-p ()
  "Test nil-safe time comparison (less than)."
  (let ((t1 (encode-time 0 0 12 1 1 2025))
        (t2 (encode-time 0 0 12 2 1 2025)))
    ;; Normal comparisons
    (should (org-gantt-util-time-less-p t1 t2))
    (should-not (org-gantt-util-time-less-p t2 t1))
    (should-not (org-gantt-util-time-less-p t1 t1))
    ;; Nil handling: any time is less than nil
    (should (org-gantt-util-time-less-p t1 nil))
    (should-not (org-gantt-util-time-less-p nil t1))
    (should-not (org-gantt-util-time-less-p nil nil))))

(ert-deftest org-gantt-util-test-time-larger-p ()
  "Test nil-safe time comparison (larger than)."
  (let ((t1 (encode-time 0 0 12 1 1 2025))
        (t2 (encode-time 0 0 12 2 1 2025)))
    (should (org-gantt-util-time-larger-p t2 t1))
    (should-not (org-gantt-util-time-larger-p t1 t2))
    (should-not (org-gantt-util-time-larger-p t1 t1))
    ;; Nil handling: any time is larger than nil
    (should (org-gantt-util-time-larger-p t1 nil))
    (should-not (org-gantt-util-time-larger-p nil t1))
    (should-not (org-gantt-util-time-larger-p nil nil))))

(ert-deftest org-gantt-util-test-time-difference ()
  "Test absolute time difference."
  (let ((t1 (encode-time 0 0 10 1 1 2025))
        (t2 (encode-time 0 0 14 1 1 2025)))  ; 4 hours later
    ;; Should be same regardless of order
    (should (= (time-to-seconds (org-gantt-util-time-difference t1 t2))
               (time-to-seconds (org-gantt-util-time-difference t2 t1))))
    ;; Should be 4 hours = 14400 seconds
    (should (= 14400 (time-to-seconds (org-gantt-util-time-difference t1 t2))))))

;;; Tag Utilities

(ert-deftest org-gantt-util-test-is-in-tags ()
  "Test tag membership check."
  (should (org-gantt-util-is-in-tags '("foo" "bar") '("bar")))
  (should (org-gantt-util-is-in-tags '("foo" "bar") '("baz" "foo")))
  (should-not (org-gantt-util-is-in-tags '("foo" "bar") '("baz" "qux")))
  (should-not (org-gantt-util-is-in-tags nil '("foo")))
  (should-not (org-gantt-util-is-in-tags '("foo") nil))
  (should-not (org-gantt-util-is-in-tags '("foo" "bar") '())))

(ert-deftest org-gantt-util-test-get-tags-style ()
  "Test getting style for tags."
  (let ((styles '(("urgent" . "bar label font=\\color{red}")
                  ("done" . "bar label font=\\color{green}")
                  ("blocked" . "bar label font=\\color{gray}"))))
    (should (string= "bar label font=\\color{red}"
                     (org-gantt-util-get-tags-style '("urgent" "todo") styles)))
    (should (string= "bar label font=\\color{green}"
                     (org-gantt-util-get-tags-style '("done") styles)))
    (should (eq nil (org-gantt-util-get-tags-style '("normal") styles)))
    (should (eq nil (org-gantt-util-get-tags-style nil styles)))
    (should (eq nil (org-gantt-util-get-tags-style '("foo") nil)))))

(ert-deftest org-gantt-util-test-stats-cookie-to-progress ()
  "Test statistics cookie parsing."
  ;; Percentage format
  (should (string= "75" (org-gantt-util-stats-cookie-to-progress "[75%]")))
  (should (string= "0" (org-gantt-util-stats-cookie-to-progress "[0%]")))
  (should (string= "100" (org-gantt-util-stats-cookie-to-progress "[100%]")))
  ;; Fraction format
  (should (string= "50.0" (org-gantt-util-stats-cookie-to-progress "[2/4]")))
  (should (string= "75.0" (org-gantt-util-stats-cookie-to-progress "[3/4]")))
  (should (string= "0.0" (org-gantt-util-stats-cookie-to-progress "[0/5]")))
  ;; Invalid formats
  (should (eq nil (org-gantt-util-stats-cookie-to-progress "[invalid]"))))

;;; Data Conversion

(ert-deftest org-gantt-util-test-plist-to-alist ()
  "Test plist to alist conversion."
  (should (equal '((:a . 1) (:b . 2) (:c . 3))
                 (org-gantt-util-plist-to-alist '(:a 1 :b 2 :c 3))))
  (should (equal nil (org-gantt-util-plist-to-alist nil)))
  (should (equal '((:only . "one"))
                 (org-gantt-util-plist-to-alist '(:only "one")))))

;;; Debug Support

(ert-deftest org-gantt-util-test-debug-message ()
  "Test debug message function."
  ;; Should not error when debug is off
  (let ((org-gantt-util-debug nil))
    (should (eq nil (org-gantt-util-debug-message "test %s" "message"))))
  ;; Should produce message when debug is on
  (let ((org-gantt-util-debug t))
    ;; Just verify it doesn't error
    (org-gantt-util-debug-message "test %s" "message")))

;;; org-gantt-util-test.el ends here
