;;; in4sit.el --- Access and retrieve data from IN4SIT -*- lexical-binding: t; -*-

;; SDPX-FileCopyrightText: 2025 Rifa Achrinza <public-foss-in4sit.el@achrinza.com>
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Version: 0.1.0
;; Author: Rifa Achrinza
;; Maintianer: Rifa Achrinza
;; URL: https://git.sr.ht/~achrinza/in4sit.el

;; Commentary:
;; This package is designed to allow users (not administrators)
;; to extract info from their organisation's PeopleSoft instance.
;;
;; Loosely-inspired by https://github.com/ekiost/SIT-Timetable-Grabber-Extension
;;
;; Currently, it only extracts basic class schedule
;; details.
;;
;; To interactively extract, call (in4sit-class-schedule).
;;
;; This package can be broken down into two parts:
;; 1. ADFS form authentication handling
;; 2. PeopleSoft retrieval and extraction
;;
;; Currently it's not generic enough to be used on other
;; ADFS or PeoplSoft systems as-is, but it should be
;; straightforward to tweak to plug in your own auth
;; redirect handler and replace the PeopleSoft URLs
;; 
;; I may eventually plan to separate these two things
;; so that they can get better use in future projects.
;;
;; For now, the codebase is hardcoded to assume some things:
;; 1. ADFS auth redirect URL of fs.singaporetech.edu.sg
;; 2. PeopleSoft URL (server, site name, portal name, node name)
;;    see: https://docs.oracle.com/cd/E92519_02/pt856pbr3/eng/pt/tprt/concept_PortalURLFormats-c071f6.html?pli=ul_d44e41_tprt
;;    see: http://www.codeandfoo.com/blog/anatomy-of-a-peoplesoft-url
;;
;;
;; It also has some stuff I want to change soon-ish:
;; 1. Allow extraction of more class details via the "Components" hyperlink
;; 2. Optional schedule-event simplification logic for use in iCal recurring events, etc.

(defcustom in4sit-class-schedule-url
  "https://in4sit.singaporetech.edu.sg/psc/CSSISSTD/EMPLOYEE/SA/c/SA_LEARNER_SERVICES.SSR_SSENRL_LIST.GBL"
  "Class schedule URL")

;; Some other data to implement in the future:
;;
;; Class Details:
;;	https://in4sit.singaporetech.edu.sg/psc/CSSISSTD/EMPLOYEE/SA/c/SA_LEARNER_SERVICES.SSR_SSENRL_LIST.GBL?ICAction=MTG_SECTION$0
;; Course Details:
;;	https://in4sit.singaporetech.edu.sg/psc/CSSISSTD/EMPLOYEE/SA/c/SA_LEARNER_SERVICES.SAA_SS_DPR_ADB.GBL?ICAction=CRSE_DESCR$0
;; Academic Requirements:
;;	https://in4sit.singaporetech.edu.sg/psc/CSSISSTD/EMPLOYEE/SA/c/SA_LEARNER_SERVICES.SAA_SS_DPR_ADB.GBL

(defcustom in4sit-url-authenticated-retrieve-delay-duration nil
  "Delay authenticated retrieved by x seconds. Useful when testing for authentication loops."
  :type 'integer)

(defcustom in4sit-debug nil
  "Enable debugging to \"*IN4SIT - DEBUG*\" buffer."
  :type 'boolean)

(defun in4sit--debug (tag msg)
  (if (bound-and-true-p in4sit-debug)
      (with-current-buffer (get-buffer-create "*IN4SIT - DEBUG*")
        (insert (format "%s [%s] %s\n"
                        (format-time-string "%FT%T%z" (current-time))
                        (upcase tag)
                        (or msg ""))))))


;; Start of Org Agenda code
(defun in4sit-lisp-time-to-org-time (lisp-time)
  (format-time-string "%Y-%m-%d %a %H:%M" lisp-time))

(defun in4sit-class-schedule-to-org-agenda (schedule)
  "EXPERIMENTAL: The function is highly-experimental and is subject to change.

Generates an org-mode buffer based on class schedule data.

Returned value is the name of the generated buffer."
  (with-current-buffer (generate-new-buffer (generate-new-buffer-name "in4sit-org-agenda-generated"))
    (org-mode)
    (let-alist schedule
      (goto-char (point-max))
      (insert (format "\n* %s %s %s" .institution .career .term))
      (org-set-property "IN4SIT_INSTITUTION" .institution)
      (org-set-property "IN4SIT_CAREER" .career)
      (org-set-property "IN4SIT_TERM" .term)
      (dolist (course .courses)
        (let-alist (cdr course)
          (goto-char (point-max))
          (insert (format "\n** %s %s" (car course) .title))
          (org-set-property "IN4SIT_COURSE_" .title)
          (org-set-property "IN4SIT_SUBJECT_AREA" .subject-area)
          (org-set-property "IN4SIT_CATALOG_NUMBER" (number-to-string .catalog-number))
          (org-set-property "IN4SIT_STATUS" .status)
          (org-set-property "IN4SIT_UNITS" (number-to-string .units))
          (org-set-property "IN4SIT_GRADING" .grading)
          (dolist (component .components)
            (let-alist (cdr component)
              (goto-char (point-max))
              (insert (format "\n*** %s" (car component)))
              (org-set-property "IN4SIT_COMPONENT" (car component))
              (org-set-property "IN4SIT_CLASS_NUMBER" (number-to-string .class-number))
              (org-set-property "IN4SIT_SECTION" .section)
              (dolist (meeting-pattern .schedules)
                (let-alist meeting-pattern
                  (goto-char (point-max))
                  (insert (format "\n**** %s" .dates))
                  (org-set-property "IN4SIT_SCHEDULE" .schedule)
                  (org-set-property "IN4SIT_DATES" .dates)
                  (org-set-property "IN4SIT_LOCATION" .location)
                  (org-set-property "IN4SIT_INSTRUCTOR" (mapconcat (apply-partially 'format "\"%s\"")
                                                                   .instructors
                                                                   " "))
                  (let ((events (in4sit-meeting-pattern-to-events .schedule .dates)))
                    (dolist (event events)
                      (let-alist event
                        (goto-char (point-max))
                        (insert (format "\n***** %s"
                                        (format-time-string "%Y-%m-%d" .start-time)))
                        (org-deadline nil (in4sit-lisp-time-to-org-time .end-time))
                        (org-schedule nil (in4sit-lisp-time-to-org-time .start-time))
                        (goto-char (point-max))
                        (insert "\n")))))))))))
    (current-buffer)))

;; Start of iCal code
;; ...#TODO :-)

;; Start of IN4SIT / PeopleSoft code
(defun in4sit--class-schedule-term-selector-p (dom)
  (equal "Select a term then select Continue."
         (dom-text (dom-by-id dom "^win[0-9]+divSSR_DUMMY_RECV1GP$0$"))))

(defun in4sit-meeting-pattern-to-events (schedule dates)
  "Converts a PeopleSoft schedule and date range (aka. Meeting Pattern)
into concrete events.

The following format is expected:
	schedule: \"Mo 10:00AM - 11:00AM\"
	dates: 	\"22/09/2025 - 22/09/2025\"

dd/MM/YYYY is assumed for date format"
  ;; Docs used as modelling reference: https://docs.oracle.com/cd/E56917_01/cs9pbr4/eng/cs/lssr/task_SchedulingNewClasses-ab465b.html#ua3db4793-6d73-4dc2-8f4b-ef823aea9f2c_s"
  ;;
  ;; Assumptions I wasn't able to confirm personally:
  ;; - Meeting patterns with multiple day-of-week selected are shown separately
  ;;   (i.e. this function does not need to handle that)
  ;; - Meeting patterns that span overnight are in the form "Mo 11:00AM - Tu 01:00AM"
  ;;   (Extract code is in place, but the main loop doesn't handle that right now...)
  (if (equal "TBA" schedule)
      nil ;; Return empty list if there's no schedule.
    (let* ((daycode-to-number-map '(("Su" . 0)
                                    ("Mo" . 1)
                                    ("Tu" . 2)
                                    ("We" . 3)
                                    ("Th" . 4)
                                    ("Fr" . 5)
                                    ("Sa" . 6)))
           (sched-start--end (split-string schedule " - "))
           (sched-start (split-string (pop sched-start--end)))
           (sched-start-day (cdr (assq (pop sched-start) daycode-to-number-map)))
           (sched-start-time (split-string (pop sched-start) ":"))
           (sched-start-hour (string-to-number (pop sched-start-time)))
           (sched-start-minute (pop sched-start-time))
           (sched-start-period (substring sched-start-minute 2 4))
           (sched-start-minute (string-to-number (substring sched-start-minute 0 2)))
           (sched-start-hour (if (equal sched-start-period "PM") (+ 12 sched-start-hour) sched-start-hour))
           (sched-end (split-string (pop sched-start--end)))
           ;; This is an assumption; Does sched-end-day actually exist?
           ;; We don't currently use this variable.
           (sched-end-day (if (= 2 (length sched-end))
                              (cdr (assq (pop sched-end) daycode-to-number-map))
                            sched-start-day))
           (sched-end-time (split-string (pop sched-end) ":"))
           (sched-end-hour (string-to-number (pop sched-end-time)))
           (sched-end-minute (pop sched-end-time))
           (sched-end-period (substring sched-end-minute 2 4))
           (sched-end-minute (string-to-number (substring sched-end-minute 0 2)))
           (sched-end-hour (if (equal sched-end-period "PM") (+ 12 sched-end-hour) sched-end-hour))
           (date-start--end (split-string dates " - "))
           ;; encoded-time-(start/end) are used as schedule boundaries
           (encoded-time-start (split-string (pop date-start--end) "/"))
           (encoded-time-start (encode-time
                                (make-decoded-time :second 0
                                                   :minute sched-start-minute
                                                   :hour sched-start-hour
                                                   :day (string-to-number (pop encoded-time-start))
                                                   :month (string-to-number (pop encoded-time-start))
                                                   :year (string-to-number (pop encoded-time-start)))))
           (encoded-time-end (split-string (pop date-start--end) "/"))
           (encoded-time-end (encode-time
                              (make-decoded-time :second 0
                                                 :minute 0
                                                 :hour 0
                                                 ;; Add one day as PeopleSoft schedules revolve around that.
                                                 ;; This also means we don't have to play with timezones.
                                                 :day (+ 1 (string-to-number (pop encoded-time-end)))
                                                 :month (string-to-number (pop encoded-time-end))
                                                 :year (string-to-number (pop encoded-time-end)))))
           (events nil)
           (encoded-time-working (copy-tree encoded-time-start)))
      (while (time-less-p encoded-time-working encoded-time-end)
        ;;(debug (format "%s || %s" (decode-time encoded-time-working) (decode-time encoded-time-end)))
        (if (= (string-to-number (format-time-string "%u" encoded-time-working)))
            (push `((start-time . ,encoded-time-working)
                    ;; We currently assume that there's no such thing as overnight classes.
                    (end-time . ,(time-add encoded-time-working
                                           (+ (* 3600 (- sched-end-hour sched-start-hour))
                                              (* 60 (- sched-end-minute sched-start-minute))))))
                  events))
        ;; Increment by 1 day
        (setq encoded-time-working (time-add encoded-time-working 86400)))
      events)))

(defun in4sit--class-schedule-terms (dom)
  "Extract the terms (aka. semesters) listed by IN4SIT from the DOM

This function assumes that the parsed DOM is from the correct webpage.
Hence, `(in4sit--class-schedule-term-selector-p)` should be called first to ensure that the HTML document is actually a selection screen."
  (thread-last
    (dom-by-id dom "^trSSR_DUMMY_RECV1$[0-9]+_row1$")
    (mapcar
     (lambda (dom-tr)
       `((term . ,(dom-text (dom-by-id dom "^TERM_CAR$[0-9]+$")))
         (career . ,(dom-text (dom-by-id dom "^CAREER$[0-9]+$")))
         (institution . ,(dom-text (dom-by-id dom "^INSTITUTION$[0-9]+$")))
         (selection-id . ,(dom-attr (dom-by-id dom "^SSR_DUMMY_RECV1$sels$[0-9]+$$0$") 'value)))))))

(defun in4sit--extract-class-schedule-course-components (dom &optional generate-events)
  (setf (symbol-function 'ps-row-cell) (lambda (subdom prefix id &optional extract-dom-text)
                                         (let* ((id-re (concat "^" prefix id "$[0-9]+$"))
                                                (nodes (dom-by-id subdom id-re)))
                                           (if extract-dom-text
                                               (let ((node-text (dom-text nodes)))
                                                 (if (equal " " node-text)
                                                     nil
                                                   node-text))
                                             nodes))))
  (let* ((prefix-derived "DERIVED_CLS_DTL_")
         (prefix-mtg "MTG_")
         (rows-dom (dom-by-id dom "^trCLASS_MTG_VW$[0-9]+_row[0-9]+$"))
         (course-components nil)
         (component-schedule nil))
    (dolist (row-dom rows-dom)
      (let* ((class-number (ps-row-cell row-dom prefix-derived "CLASS_NBR" t))
             (ps-ic-action (dom-attr (ps-row-cell row-dom prefix-mtg "SECTION") 'id))
             (section (ps-row-cell row-dom prefix-mtg "SECTION" t))
             (name (ps-row-cell row-dom prefix-mtg "COMP" t))
             (schedule (ps-row-cell row-dom prefix-mtg "SCHED" t))
             (location (ps-row-cell row-dom prefix-mtg "LOC" t))
             (instructors (ps-row-cell row-dom prefix-derived "SSR_INSTR_LONG" t))
             (dates (ps-row-cell row-dom prefix-mtg "DATES" t)))
        (when (and name
                   (not (assoc 'name course-components)))
          (when (> (length component-schedule) 0)
            ;; Push the previous, now-built component schedule to the course definition.
            ;; (cdar) is used instead of (assoc) as `name is already updated to the
            ;; next component's name.
            (setcdr (assoc 'schedules (cdar course-components)) (copy-tree component-schedule))
            (setq component-schedule nil))
          ;; Start buiding the current component
          ;; Important: this push must come after pushing the previous component's schedule
          ;;            due to position-based (cdar)
          (push (copy-tree `(,name . ((class-number . ,(string-to-number class-number))
                                      (section . ,section)
                                      ;; TODO: Do we want to expose this?
                                      ;; (ps-ic-action . ,ps-ic-action)
                                      (schedules))))
                  course-components)
              component-schedule)
        (push (copy-tree `((schedule . ,schedule)
                           (location . ,location)
                           (instructors . ,(split-string instructors ",  "))
                           (dates . ,dates)))
              component-schedule)
        ;; Add generated events based on schedule if requested.
        (if generate-events
            (push `(events-calculated . ,(in4sit-meeting-pattern-to-events
                                          schedule
                                          dates))
                  (car component-schedule)))))
    ; Push final component's schedule once there's no more components
    (setcdr (assoc 'schedules (cdar course-components)) (copy-tree component-schedule))
    (copy-tree course-components)))

(defun in4sit--extract-class-schedule-callback (status callback)
  (let* ((class-schedule-buffer (current-buffer))
         (dom (libxml-parse-html-region (point)))
         (term--career--inst (split-string (dom-text (dom-by-id dom "^DERIVED_REGFRM1_SSR_STDNTKEY_DESCR$11$$")) " | " ))
         (term (pop term--career--inst))
         (career (pop term--career--inst))
         (inst (pop term--career--inst))
         (courses (thread-last
                    ;; Known values:
                    ;; ^win0divDERIVED_REGFRM1_DESCR20$[0-9]+$
                    ;; ^win14divDERIVED_REGFRM1_DESCR20$[0-9]+$
                    (dom-by-id dom "^win[0-9]+divDERIVED_REGFRM1_DESCR20$[0-9]+$")
                    (mapcar (lambda (x)
                              (let* ((sa-nbr-title (dom-text (dom-by-class x "PAGROUPDIVIDER")))
                                     (sa-nbr--title (split-string sa-nbr-title " - "))
                                     (sa-nbr (pop sa-nbr--title))
                                     (sa--nbr (split-string sa-nbr " "))
                                     (sa (pop sa--nbr))
                                     (nbr (pop sa--nbr))
                                     (title (pop sa-nbr--title))
                                     (x `(,(concat sa nbr) .
                                          ((subject-area . ,sa)
                                           (catalog-number . ,(string-to-number nbr))
                                           (title . ,title)
                                           (status . ,(dom-text (dom-by-id x "^STATUS$[0-9]+$")))
                                           (units . ,(string-to-number (dom-text (dom-by-id x "^DERIVED_REGFRM1_UNT_TAKEN$[0-9]+$"))))
                                           (grading . ,(dom-text (dom-by-id x "^GB_DESCR$[0-9]+$")))
                                           ;; TODO: Bubble up machanism for `generate-events' argument.
                                           ;;       Otherwise, keep it disabled for now.
                                           (components . ,(in4sit--extract-class-schedule-course-components x))))))
                                x)))))
         (term `((term . ,term)
                 (career . ,career)
                 (institution . ,inst)
                 (courses . ,courses))))
    (kill-buffer class-schedule-buffer)
    (apply callback `(,term))))

(defun in4sit-class-schedule (callback &optional term)
  (in4sit--url-authenticated-retrieve in4sit-class-schedule-url
                                      #'in4sit--class-schedule-callback
                                      `(,callback ,term)))

(defun in4sit--class-schedule-callback (status callback &optional term)
  (let ((term-selection-buffer (current-buffer))
        (dom (libxml-parse-html-region (point))))
    (kill-buffer term-selection-buffer)
    (if (in4sit--class-schedule-term-selector-p dom)
        (progn
          (let ((terms-available (in4sit--class-schedule-terms dom)))
            (when (and (> 1 (length terms-available)) (not term))
              (let ((term-details (mapcar (lambda (term-detail)
                                            `(,(concat (cdr (assoc 'institution term-detail)) " "
                                                       (cdr (assoc 'career term-detail)) " "
                                                       (cdr (assoc 'term term-detail))) .
                                                       (cdr (assoc 'selection-id term-detail))))
                                          terms-available)))
                (setq term (cdr (assoc (completing-read "Select a term: " term-details)
                                       term-details))))))
          (let ((term (or term "0"))) ; If there's only one term, select that.
            (in4sit--url-authenticated-retrieve
             (concat in4sit-class-schedule-url "?"
                     (in4sit--alist-to-urlencoded `(("ICAction" . "DERIVED_SSS_SCT_SSR_PB_GO")
                                                    ("SSR_DUMMY_RECV1$sels$0$$0" . ,term))))
             #'in4sit--extract-class-schedule-callback `(,callback))))
      (in4sit--extract-class-schedule-callback status callback))))

;; Start of ADFS-specific-ish code

(defun in4sit--url-authenticated-retrieve (url callback &optional cbargs)
  (let* ((duration in4sit-url-authenticated-retrieve-delay-duration))
    (when in4sit-url-authenticated-retrieve-delay-duration
    (dotimes (number duration)
      (sleep-for 1)
      (message "%s Authenticated retrieve called for URL %s" (- duration number) url))))
  ;; Use async url-retrieve as we need to detect redirects
  (url-retrieve url
                #'in4sit--url-authenticated-retrieve-callback
                `(,url ,callback ,cbargs)))

;;; #TODO: Consider moving this into in4sit--url-authenticated-retrieve
;;;        as this function depends the state of current-buffer
;;;        Counterpoint: Separation may be useful for testing (examples?)
(defun in4sit--url-authenticated-retrieve-callback (status url callback &optional cbargs)
  (let* ((redirect-url (plist-get status :redirect)))
    (if (and (stringp redirect-url)
             (string-match "^https://fs.singaporetech.edu.sg/adfs/ls/idpinitiatedsignon.asmx" redirect-url))
        ;; Handle authentication redirects
        (let ((dom (libxml-parse-html-region (point))))
          (when (not (in4sit--handle-adfs-saml-callback-redirect-if-needed dom))
            (let* ((adfs-login-page (current-buffer))
                   (auth-source-creation-prompts
                    ;; TODO: Make username/login lingo consistent; use "login"
                    '((login . "SIT login: ")
                      (secret . "SIT password: ")))
                   (found-credentials (or (car (auth-source-search :max 1
                                                                   :host "fs.singaporetech.edu.sg"
                                                                   :port "adfs"
                                                                   :require '(:user :secret)))
                                          (user-error "SIT credentials not found by auth-source")))
                   (username (plist-get found-credentials :user))
                   (password (plist-get found-credentials :secret))
                   (password (if (functionp password) (funcall password) password))
                   (login-request (in4sit--generate-login-request dom username password)))
              (kill-buffer adfs-login-page) ; Removes adfs login page buffer as it's only required by in4sit--generate-login-request
              (in4sit--validate-login-credentials username password)
              (in4sit--submit-login-request login-request)))
          (url-retrieve url callback cbargs)) ; After auth cookies stored by `url`, redo the original url-retrieve.)
      
      ;; Simply run callback when the first url-retrieve did not
      ;; redirect for authentication.
      (apply callback `(,status . ,cbargs)))))

(defun in4sit--validate-login-credentials (username password)
  "Perform the same client-side validation as the ADFS signon form, and restrict to student accounts."
  (let* ((password-length (length password)))
    ;; Only SIT student accounts have been tested.
    (if (not (and (stringp username)
                  (string-match "@sit.singaporetech.edu.sg$" username)))
        (user-error "Malformed SIT username. Must end in \"@sit.singaporetech.edu.sg\""))
    (if (not (and (stringp password)
                  (> password-length 0)
                  (<= password-length 128)))
        (user-error "Malformed SIT password. Must be 1 <= x <= 128 characters."))))

(defun in4sit--generate-login-request (dom username password &optional kmsi)
  "Parse HTML response from current buffer from current cursor position until end of buffer, and generate plist of login POST data."
  (let* ((submit-path (dom-attr (dom-by-id dom "loginForm") 'action)))
    (if (not (stringp submit-path))
        (error "Failed IN4SIT login via ADFS. No valid login form returned by server.")
      `(:body (("UserName" . ,username)
               ("Password" . ,password)
               ("AuthMethod" . "FormsAuthentication"))
        :url ,(concat "https://fs.singaporetech.edu.sg" submit-path)))))

(defun in4sit--submit-login-request (request)
  (let* ((url-request-method "POST")
         (url-request-extra-headers '(("Content-Type" . "application/x-www-form-urlencoded")))
         (url-request-data (in4sit--alist-to-urlencoded (plist-get request :body)))
         ;; Submit login details to ADFS:
         (postlogin-response ((lambda ()
                                (in4sit--debug "DEBUG" "Logging into SIT ADFS..")
                                (url-retrieve-synchronously (plist-get request :url)))))
         (dom (with-current-buffer postlogin-response
                ;; Cursor is pointed at last char instead of between headers and body as usually done by url-retrieve.
                ;; Hence, we need to reposition it manually. (is this a -synchronously quirk?)
                (goto-char (point-min))
                (re-search-forward "^$")
                (libxml-parse-html-region (point))))
         (adfs-error (dom-text (dom-by-id dom "errorText"))))
    (in4sit--debug "DEBUG" (format "ADFS SAML callback redirect buffer: %s" postlogin-response))
    (kill-buffer postlogin-response) ; Remove the SAML callback page buffer
    (cond ((and (stringp adfs-error)
                (not (eq "" adfs-error)))
           (error "ADFS error: %s" adfs-error))
          ((in4sit--handle-adfs-saml-callback-redirect-if-needed dom) nil)
          (t (with-current-buffer postlogin-response
               (error "IN4SIT login via ADFS failed. No ADFS error nor valid SAML response redirect returned by server."))))))

(defun in4sit--handle-adfs-saml-callback-redirect-if-needed (dom)
  (let* ((adfs-callback-url (dom-attr (dom-by-tag dom 'form) 'action))
         (adfs-callback-saml-response (dom-attr (dom-elements dom 'name "SAMLResponse") 'value)))
    (when (and (stringp adfs-callback-url)
               (not (eq "" adfs-callback-url))
               (stringp adfs-callback-saml-response)
               (not (eq "" adfs-callback-saml-response)))
      (let* ((url-request-method "POST")
             (url-request-extra-headers '(("Content-Type" . "application/x-www-form-urlencoded")))
             (url-request-data (in4sit--alist-to-urlencoded `(("SAMLResponse" . ,adfs-callback-saml-response))))
             (saml-sp-callback-response ((lambda ()
                                          (in4sit--debug "DEBUG" "Executing SIT ADFS SAML callback to IN4SIT...")
                                          (url-retrieve-synchronously adfs-callback-url)))))
        (in4sit--debug "DEBUG" (format "SAML SP callback response buffer: %s" saml-sp-callback-response))
        ;; url-retrieve buffer cleanup
        (kill-buffer saml-sp-callback-response)
        t))))
 
(defun in4sit--alist-to-urlencoded (form-data)
  (mapconcat (lambda (cons-cell)
               (let* ((name (car cons-cell))
                      (name (if (symbolp name) (symbol-name name) name))
                      (value (cdr cons-cell)))
                 (concat (url-hexify-string name)
                         "="
                         (url-hexify-string value))))
             form-data "&"))
