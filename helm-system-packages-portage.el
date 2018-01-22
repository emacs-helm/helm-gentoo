;;; helm-system-packages-portage.el --- Helm UI for Portage. -*- lexical-binding: t -*-

;; Copyright (C) 2012 ~ 2014 Thierry Volpiatto <thierry.volpiatto@gmail.com>
;;               2017        Pierre Neidhardt <ambrevar@gmail.com>

;; Author: Thierry Volpiatto <thierry.volpiatto@gmail.com>
;; Maintainer: Pierre Neidhardt <ambrevar@gmail.com>
;; URL: https://github.com/emacs-helm/helm-system-packages
;; Version: 1.6.9
;; Package-Requires: ((emacs "24.4") (helm "2.8.6"))
;; Keywords: helm, packages

;; This program is free software; you can redistribute it and/or modify
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
;; Helm UI for Portage.

;;; Code:
(require 'helm)
(require 'helm-system-packages)

(defface helm-system-packages-portage-explicit '((t (:inherit font-lock-warning-face)))
  "Face for explicitly installed packages."
  :group 'helm-system-packages)

(defface helm-system-packages-portage-dependencies '((t (:inherit font-lock-comment-face :slant italic)))
  "Face for packages installed as dependencies."
  :group 'helm-system-packages)

;; TODO: Move `all' and `description' to common file?
(defvar helm-system-packages-portage--all nil
  "Cache of all package names.")

(defvar helm-system-packages-portage--descriptions nil
  "Cache of all package names with descriptions.")

(defun helm-system-packages-portage-list-explicit ()
  "List explicitly installed packages."
  (split-string (with-temp-buffer
                  (insert-file-contents-literally "/var/lib/portage/world")
                  (buffer-string))))

(defun helm-system-packages-portage-list-dependencies (&optional explicit)
  "List packages installed as a required dependency.
The caller can pass the list of EXPLICIT packages to avoid re-computing it."
  (unless explicit
    (setq explicit (helm-system-packages-portage-list-explicit)))
  (seq-difference
   (split-string (with-temp-buffer
                   (call-process "qlist" nil t nil "-I")
                   (buffer-string)))
   explicit))

(defun helm-system-packages-portage-cache-names ()
  "Cache all package names."
  (with-temp-buffer
    (call-process "eix" nil t nil "--only-names")
    (buffer-string)))

(defcustom helm-system-packages-portage-column-width 40
  "Column at which descriptions are aligned, excluding a double-space gap."
  :group 'helm-system-packages)

(defun helm-system-packages-portage-cache-descriptions ()
  "Cache all package names with descriptions."
  (with-temp-buffer
    ;; `eix' can format the output while `apt-cache search' cannot.  Thus we
    ;; tell `eix' to use the same formatting as `apt-cache' so that we can
    ;; re-use its code.
    ;; TODO: Can eix pad in the format string just like `expac' does?
    ;; TODO: Or output straight to Elisp?
    (call-process "env" nil '(t nil) nil "EIX_LIMIT=0" "OVERLAYS_LIST=none" "PRINT_COUNT_ALWAYS=never" "eix" "--format" "<category>/<name> - <description>\n")
    (goto-char (point-min))
    (while (search-forward " " nil t)
      (delete-char 1)
      (backward-char)
      (let ((pos (- (point) (line-beginning-position))))
        (when (< pos helm-system-packages-portage-column-width)
          (insert (make-string (- helm-system-packages-portage-column-width pos) ? ))))
      (forward-line))
    ;; (sort-lines nil (point-min) (point-max)) ; TODO: Required? Also see helm-system-packages-portage-cache-names.
    (buffer-string)))

;; TODO: Move this to common source?
(defun helm-system-packages-portage-init ()
  "Cache package lists and create Helm buffer."
  (unless (and helm-system-packages-portage--names helm-system-packages-portage--descriptions)
    (helm-system-packages-portage-refresh))
  (helm-init-candidates-in-buffer
      'global
    (if helm-system-packages-details-flag
        helm-system-packages-portage--descriptions
      helm-system-packages-portage--names)))

(defun helm-system-packages-portage-refresh ()
  "Refresh the package list."
  (interactive)
  (setq helm-system-packages-portage--descriptions (helm-system-packages-portage-cache-descriptions)
        helm-system-packages-portage--names (helm-system-packages-portage-cache-names))
  (let* ((explicit (helm-system-packages-portage-list-explicit))
         (dependencies (helm-system-packages-portage-list-dependencies explicit)))
    (setq helm-system-packages--display-lists nil)
    (dolist (p explicit)
      (push (cons p '(helm-system-packages-portage-explicit)) helm-system-packages--display-lists))
    (dolist (p dependencies)
      (push (cons p '(helm-system-packages-portage-dependencies)) helm-system-packages--display-lists))))

(defvar helm-system-packages-portage-source
  (helm-build-in-buffer-source "Portage source"
    :init 'helm-system-packages-portage-init
    :candidate-transformer 'helm-system-packages-highlight
    :candidate-number-limit helm-system-packages-candidate-limit
    :display-to-real 'helm-system-packages-extract-name
    :action '(("Show package(s)" .
               (lambda (_)
                 (helm-system-packages-print "eix")))
              ("Install (`C-u' to not add to world)" .
               (lambda (_)
                 (helm-system-packages-run-as-root "emerge" "--ask" "--verbose" (when helm-current-prefix-arg "--oneshot"))))
              ("Uninstall (`C-u' to include dependencies)" .
               (lambda (_)
                 (helm-system-packages-run-as-root "emerge" "--ask" "--verbose" (if helm-current-prefix-arg "--depclean" "--unmerge"))))
              ("Emerge-pretend" .
               (lambda (_)
                 (helm-system-packages-print "emerge" "--pretend")))
              ("Find files" .
               (lambda (_)
                 (helm-system-packages-find-files "equery" "--no-color" "files")))
              ("Show dependencies" .
               (lambda (_)
                 (helm-system-packages-print "equery" "--no-color" "depgraph")))
              ("Show reverse dependencies" .
               (lambda (_)
                 (helm-system-packages-print "equery" "--no-color" "depends")))
              ("Show history" .
               (lambda (_)
                 (helm-system-packages-print "genlop" "-qe")))
              ("Show extra info" .
               (lambda (_)
                 (helm-system-packages-print elm "genlop -qi")))
              ("Show USE flags" .
               (lambda (_)
                 (helm-system-packages-print elm "equery" "--no-color" "uses")
                 ;; TODO: Test font-lock.
                 (unless helm-current-prefix-arg
                   (font-lock-add-keywords nil '(("^\+.*" . font-lock-variable-name-face)))
                   (font-lock-mode 1))))
              ("Browse homepage URL" .
               (lambda (_)
                 (helm-system-packages-browse-url (split-string (helm-system-packages-run "eix" "--format" "<homepage>\n") "\n" t)))))))

(defun helm-system-packages-portage-use-init ()
  "Initialize buffer with all USE flags."
  (unless (helm-candidate-buffer)
    (helm-init-candidates-in-buffer
        'global
      (with-temp-buffer
        (call-process "eix" nil t nil "--print-all-useflags")
        (buffer-string)))))

(defvar helm-system-packages-portage-use-source
  (helm-build-in-buffer-source "USE flags"
    :init 'helm-system-packages-portage-use-init
    :candidate-transformer 'helm-system-packages-portage-use-transformer
    :action '(("Description" .
               (lambda (elm)
                 (switch-to-buffer helm-system-packages-buffer)
                 (erase-buffer)
                 (apply #'call-process "euse" nil t nil `("--info" ,elm))
                 (font-lock-add-keywords nil `((,elm . font-lock-variable-name-face)))
                 (font-lock-mode 1)))
              ("Enable" .
               (lambda (_)
                 (helm-system-packages-run-as-root "euse" "--enable")))
              ("Disable" .
               (lambda (_)
                 (helm-system-packages-run-as-root "euse" "--disable")))
              ("Remove" .
               (lambda (_)
                 (helm-system-packages-run-as-root "euse" "--prune")))
              ("Show which dependencies use this flag" .
               (lambda (_)
                 (helm-system-packages-print "equery" "--no-color" "hasuse"))))))

(defun helm-system-packages-portage-use-transformer (use-flags)
  "Highlight enabled USE flags."
  (let ((local-uses (split-string (with-temp-buffer
                                    (call-process "portageq" nil t nil "envvar" "USE")
                                    (buffer-string)))))
    (mapcar (lambda (use-flag)
              (propertize use-flag 'face
                          (when (member use-flag local-uses)
                            'helm-system-packages-explicit)))
            use-flags)))

(defun helm-system-packages-portage ()
  "Preconfigured `helm' for Portage."
  (helm :sources '(helm-system-packages-portage-source
                   helm-system-packages-portage-use-source)
        :buffer "*helm portage*"
        :truncate-lines t
        :input (substring-no-properties (or (thing-at-point 'symbol) ""))))

(provide 'helm-system-packages-portage)

;;; helm-system-packages-portage.el ends here
