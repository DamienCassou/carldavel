;;; carldavel.el --- Integrate external tools to manage your contacts and calendars

;; Copyright (C) 2015 Damien Cassou

;; Author: Damien Cassou <damien.cassou@inria.fr>
;; Version: 0.1
;; GIT: https://github.com/DamienCassou/carldavel
;; Package-Requires: ((helm "1.7.0") (emacs "24.0"))
;; Created: 12 Nov 2015
;; Keywords: helm pyccarddav vdirsyncer khard carddav caldav vdir contact addressbook calendar

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Integrate external tools to manage your contacts and calendars

;;; Code:

(require 'eieio)
(require 'helm)

(defconst carldavel--buffer "*carldavel-contacts*")

(defgroup carldavel nil
  "Integrate external tools to manage your contacts and calendars"
  :group 'external)

(defcustom carldavel-contacts-fill-function
  #'carldavel-khard-fill-buffer
  "Function to get contacts from an external command."
  :group 'carldavel
  ;; TODO Improve the type by proposing existing commands
  :type 'function)

(defcustom carldavel-server-sync-function
  #'carldavel-vdirsyncer-sync-server
  "Function to sync local database with server."
  :group 'carldavel
  ;; TODO Improve the type by proposing existing commands
  :type 'function)


(defun carldavel--debug-info (string &rest objects)
  "Log STRING with OBJECTS as if using `format`."
  (apply #'message (concat "[carldavel] info: " string) objects))

(defun carldavel--fill-buffer (buffer command &rest arguments)
  "Fill BUFFER with contacts from COMMAND and ARGUMENTS.
If BUFFER already contains something, erase it before executing COMMAND.
Executing COMMAND with ARGUMENTS should print contacts in the mutt format
to standard output.  The mutt format looks like:
    some@email.com	Some Name
    some2@mail.com	Some Other Name"
  (carldavel--debug-info "Executing %s" (mapconcat #'identity (cons command arguments) " "))
  (with-current-buffer buffer
    (erase-buffer)
    (apply
     #'call-process
     command
     nil                                ; input file
     (list buffer nil)                  ; output to buffer, discard error
     nil                                ; don't redisplay
     arguments)
    ;; Remove first line as it is only informative
    (goto-char (point-min))
    (delete-region (point-min) (1+ (line-end-position)))))

(defun carldavel-khard-fill-buffer (buffer)
  "Call `carldavel--fill-buffer' on BUFFER.  Use khard."
  (carldavel--fill-buffer buffer "khard" "mutt"))

(defun carldavel-pycarddav-fill-buffer (buffer)
  "Call `carldavel--fill-buffer' on BUFFER.  Use pc_query."
  (carldavel--fill-buffer buffer "pc_query" "-m"))

(defun carldavel--get-contacts-buffer ()
  "Return a buffer with one carddav contact per line."
  (let ((buffer (get-buffer-create carldavel--buffer)))
    (when (with-current-buffer (get-buffer-create carldavel--buffer)
            (equal (point-min) (point-max)))
      (funcall carldavel-contacts-fill-function buffer))
    buffer))

(defun carldavel--reset-buffer ()
  "Make sure carldavel buffer is empty to force update on next use."
  (with-current-buffer (get-buffer-create carldavel--buffer)
    (erase-buffer)))

(defun carldavel--get-contact-from-line (line)
  "Return a carddav contact read from LINE.

The line must start with something like:
some@email.com	Some Name

The returned contact is of the form
 (:name \"Some Name\" :mail \"some@email.com\")"
  (when (string-match "\\(.*?\\)\t\\(.*?\\)\t" line)
    (list :name (match-string 2 line) :mail (match-string 1 line))))

(defun carldavel-sync-from-server (command &rest arguments)
  "Use COMMAND with ARGUMENTS to sync local database with server."
  (interactive)
  (carldavel--debug-info "Executing %s" (mapconcat #'identity (cons command arguments) " "))
  (apply
   #'call-process
   command
   nil
   (get-buffer-create "*carldavel-server-sync*")
   nil
   arguments))

(defun carldavel-vdirsyncer-sync-server ()
  "Ask vdirsyncer to sync with the server."
  (carldavel-sync-from-server "vdirsyncer" "sync"))

(defun carldavel-pycarddav-sync-server ()
  "Ask pycardsyncer to sync contacts with the server."
  (carldavel-sync-from-server "pycardsyncer"))

(defun carldavel--helm-source-init ()
  "Initialize helm candidate buffer."
  (helm-candidate-buffer (carldavel--get-contacts-buffer)))

(defun carldavel--helm-source-select-action (candidate)
  "Print selected contacts as comma-separated text.
CANDIDATE is ignored."
  (ignore candidate)
  (insert (mapconcat (lambda (contact)
                       (let ((contact (carldavel--get-contact-from-line contact)))
                         (format "\"%s\" <%s>"
                                 (plist-get contact :name)
                                 (plist-get contact :mail))))
                     (helm-marked-candidates)
                     ", ")))

(defclass carldavel--helm-source (helm-source-in-buffer)
  ((init :initform #'carldavel--helm-source-init)
   (nohighlight :initform t)
   (action :initform (helm-make-actions
                      "Select" #'carldavel--helm-source-select-action))
   (requires-pattern :initform 0)))

;;;###autoload
(defun carldavel-search-with-helm (refresh)
  "Start helm to select your contacts from a list.
If REFRESH is not-nil, make sure to ask pycarrdav to refresh the contacts
list.  Otherwise, use the contacts previously fetched from pycarddav."
  (interactive "P")
  (when (and (consp refresh) (eq 16 (car refresh)))
    (funcall carldavel-server-sync-function))
  (when refresh
    (carldavel--reset-buffer))
  (helm
   :prompt "contacts: "
   :sources (helm-make-source "Contacts" 'carldavel--helm-source)))

(provide 'carldavel)

;;; carldavel.el ends here
