;;; org-gantt-parse-test.el --- Tests for org-gantt-parse -*- lexical-binding: t -*-

;;; Code:

(require 'ert)
(require 'org-gantt-parse)
(require 'org-gantt-context)
(require 'org-gantt-config)

(defun org-gantt-test-make-context ()
  "Create a test context."
  (let ((ctx (org-gantt-context-init 8 '(0 6))))
    (setf (org-gantt-context-options ctx)
          '(:milestone-tags ("milestone")
            :linked-to-property-keys (:LINKED-TO)))
    ctx))

(defun org-gantt-test-parse-string (org-string)
  "Parse ORG-STRING and return the parsed buffer."
  (with-temp-buffer
    (insert org-string)
    (org-mode)
    (org-element-parse-buffer)))

;;; Subheadline Tests

(ert-deftest org-gantt-parse-test-subheadlines ()
  "Test getting subheadlines."
  (let* ((org-string "* Parent\n** Child 1\n** Child 2\n** Child 3\n")
         (parsed (org-gantt-test-parse-string org-string))
         (parent (car (org-element-map parsed 'headline #'identity)))
         (children (org-gantt-parse-subheadlines (cdr parent))))
    (should (= 3 (length children)))))

(ert-deftest org-gantt-parse-test-subheadlines-empty ()
  "Test getting subheadlines when there are none."
  (let* ((org-string "* Leaf\n")
         (parsed (org-gantt-test-parse-string org-string))
         (headline (car (org-element-map parsed 'headline #'identity)))
         (children (org-gantt-parse-subheadlines (cdr headline))))
    (should (= 0 (length children)))))

;;; Time Extraction Tests

(ert-deftest org-gantt-parse-test-start-time-scheduled ()
  "Test extracting scheduled time."
  (let* ((org-string "* Task\nSCHEDULED: <2025-01-06 Mon>\n")
         (parsed (org-gantt-test-parse-string org-string))
         (headline (car (org-element-map parsed 'headline #'identity)))
         (start-time (org-gantt-parse-start-time headline 8)))
    (should start-time)
    (let ((decoded (decode-time start-time)))
      (should (= 6 (nth 3 decoded)))   ; day
      (should (= 1 (nth 4 decoded)))   ; month
      (should (= 2025 (nth 5 decoded)))))) ; year

(ert-deftest org-gantt-parse-test-end-time-deadline ()
  "Test extracting deadline time."
  (let* ((org-string "* Task\nDEADLINE: <2025-01-10 Fri>\n")
         (parsed (org-gantt-test-parse-string org-string))
         (headline (car (org-element-map parsed 'headline #'identity)))
         (end-time (org-gantt-parse-end-time headline 8)))
    (should end-time)
    (let ((decoded (decode-time end-time)))
      (should (= 10 (nth 3 decoded)))
      ;; Note: deadline at midnight gets hours-per-day added
      (should (= 8 (nth 2 decoded))))))

(ert-deftest org-gantt-parse-test-time-from-children ()
  "Test time extraction falling back to children."
  (let* ((org-string "* Parent\n** Child\nSCHEDULED: <2025-01-06 Mon>\n")
         (parsed (org-gantt-test-parse-string org-string))
         (parent (car (org-element-map parsed 'headline #'identity)))
         (start-time (org-gantt-parse-start-time parent 8)))
    ;; Should get time from child since parent has none
    (should start-time)))

;;; Statistics Cookie Tests

(ert-deftest org-gantt-parse-test-statistics-percent ()
  "Test parsing percentage statistics cookie."
  (let* ((org-string "* Task [75%]\n")
         (parsed (org-gantt-test-parse-string org-string))
         (headline (car (org-element-map parsed 'headline #'identity)))
         (title (org-element-property :title headline))
         (cookie (org-gantt-parse-statistics-value title)))
    (should (string= "[75%]" cookie))))

(ert-deftest org-gantt-parse-test-statistics-fraction ()
  "Test parsing fraction statistics cookie."
  (let* ((org-string "* Task [3/4]\n")
         (parsed (org-gantt-test-parse-string org-string))
         (headline (car (org-element-map parsed 'headline #'identity)))
         (title (org-element-property :title headline))
         (cookie (org-gantt-parse-statistics-value title)))
    (should (string= "[3/4]" cookie))))

;;; Gantt-Info Creation Tests

(ert-deftest org-gantt-parse-test-create-info-basic ()
  "Test basic gantt-info creation."
  (let* ((ctx (org-gantt-test-make-context))
         (org-string "* My Task\nSCHEDULED: <2025-01-06 Mon> DEADLINE: <2025-01-10 Fri>\n")
         (parsed (org-gantt-test-parse-string org-string))
         (headline (car (org-element-map parsed 'headline #'identity)))
         (info (org-gantt-parse-create-info headline ctx)))
    (should (hash-table-p info))
    (should (string= "My Task" (gethash :name info)))
    (should (gethash org-gantt-start-prop info))
    (should (gethash org-gantt-end-prop info))
    (should (gethash org-gantt-id-prop info))))

(ert-deftest org-gantt-parse-test-create-info-with-effort ()
  "Test gantt-info creation with effort."
  (let* ((ctx (org-gantt-test-make-context))
         (org-string "* Task\n:PROPERTIES:\n:EFFORT: 2d\n:END:\n")
         (parsed (org-gantt-test-parse-string org-string))
         (headline (car (org-element-map parsed 'headline #'identity)))
         (info (org-gantt-parse-create-info headline ctx)))
    (should (gethash org-gantt-effort-prop info))))

(ert-deftest org-gantt-parse-test-create-info-with-tags ()
  "Test gantt-info creation preserves tags."
  (let* ((ctx (org-gantt-test-make-context))
         (org-string "* Task :important:urgent:\n")
         (parsed (org-gantt-test-parse-string org-string))
         (headline (car (org-element-map parsed 'headline #'identity)))
         (info (org-gantt-parse-create-info headline ctx)))
    (should (member "important" (gethash org-gantt-tags-prop info)))
    (should (member "urgent" (gethash org-gantt-tags-prop info)))))

(ert-deftest org-gantt-parse-test-create-info-id-generation ()
  "Test that IDs are generated correctly."
  (let* ((ctx (org-gantt-test-make-context))
         (org-string "* Task 1\n* Task 2\n* Task 3\n")
         (parsed (org-gantt-test-parse-string org-string))
         (headlines (org-element-map parsed 'headline #'identity))
         (ids (mapcar (lambda (hl)
                       (gethash org-gantt-id-prop
                               (org-gantt-parse-create-info hl ctx)))
                     headlines)))
    ;; All IDs should be unique
    (should (= 3 (length (delete-dups (copy-sequence ids)))))))

(ert-deftest org-gantt-parse-test-create-info-preserves-org-id ()
  "Test that explicit :ID property is preserved."
  (let* ((ctx (org-gantt-test-make-context))
         (org-string "* Task\n:PROPERTIES:\n:ID: my-custom-id\n:END:\n")
         (parsed (org-gantt-test-parse-string org-string))
         (headline (car (org-element-map parsed 'headline #'identity)))
         (info (org-gantt-parse-create-info headline ctx)))
    (should (string= "my-custom-id" (gethash org-gantt-id-prop info)))))

;;; Crawl Headlines Tests

(ert-deftest org-gantt-parse-test-crawl-simple ()
  "Test crawling simple headline structure."
  (let* ((ctx (org-gantt-test-make-context))
         (org-string "* Task 1\n* Task 2\n* Task 3\n")
         (parsed (org-gantt-test-parse-string org-string))
         (info-list (org-gantt-parse-crawl-headlines parsed ctx)))
    (should (= 3 (length info-list)))
    (should (hash-table-p (car info-list)))))

(ert-deftest org-gantt-parse-test-crawl-nested ()
  "Test crawling nested headlines."
  (let* ((ctx (org-gantt-test-make-context))
         (org-string "* Parent\n** Child 1\n** Child 2\n* Sibling\n")
         (parsed (org-gantt-test-parse-string org-string))
         (info-list (org-gantt-parse-crawl-headlines parsed ctx)))
    ;; Should have 2 top-level entries
    (should (= 2 (length info-list)))
    ;; First entry should have 2 subelements
    (let ((parent-info (car info-list)))
      (should (= 2 (length (gethash :subelements parent-info)))))))

;;; Extreme Date Tests

(ert-deftest org-gantt-parse-test-extreme-date-earliest ()
  "Test finding earliest date in info list."
  (let* ((ctx (org-gantt-test-make-context))
         (org-string (concat "* Task 1\nSCHEDULED: <2025-01-10 Fri>\n"
                            "* Task 2\nSCHEDULED: <2025-01-05 Sun>\n"
                            "* Task 3\nSCHEDULED: <2025-01-15 Wed>\n"))
         (parsed (org-gantt-test-parse-string org-string))
         (info-list (org-gantt-parse-crawl-headlines parsed ctx))
         (earliest (org-gantt-parse-extreme-date
                    info-list
                    (lambda (info) (gethash org-gantt-start-prop info))
                    #'org-gantt-util-time-less-p)))
    (should earliest)
    (let ((decoded (decode-time earliest)))
      (should (= 5 (nth 3 decoded))))))  ; Jan 5 is earliest

(provide 'org-gantt-parse-test)
;;; org-gantt-parse-test.el ends here
