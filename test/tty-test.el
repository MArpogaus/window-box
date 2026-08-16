;;; tty-test.el --- Terminal session for the tty test -*- lexical-binding: t; -*-
;;; Commentary:
;; Loaded by tty-test.py inside `emacs -nw'.  It boxes one window and
;; exits; the Python side reads the screen.
;;; Code:
(add-to-list 'load-path (expand-file-name ".." (file-name-directory load-file-name)))
(require 'window-box)
(setq inhibit-startup-screen t ring-bell-function #'ignore)
(menu-bar-mode -1)
(run-with-timer 0.5 nil
 (lambda ()
   (switch-to-buffer "*main*") (delete-other-windows)
   (insert "main window\n")
   (let ((top (split-window nil -6 'above)))
     (set-window-buffer top (get-buffer-create "*boxed*"))
     (with-current-buffer "*boxed*"
       (insert "boxed in the terminal\nsecond line\n")
       (setq-local mode-line-format nil)
       (window-box-mode 1)))
   ;; A second box beside the first: a terminal spends one column of
   ;; the window on the separator, and an edge that counts it loses a
   ;; corner off the end.
   (let ((right (split-window-right 40)))
     (set-window-buffer right (get-buffer-create "*beside*"))
     (with-current-buffer "*beside*"
       (insert "boxed beside it\n")
       (setq-local mode-line-format nil)
       (window-box-mode 1)))
   ;; A window with rows of its own, and the box drawn around them:
   ;; the top edge takes the free tab line row, and the mode line
   ;; closes the box, since a terminal has no row below it.
   (let* ((below (split-window (frame-root-window) -8 'below))
          ;; and one beside it, left of the divider: a terminal spends
          ;; a column of that window on the separator, and an end
          ;; placed by the row's own right edge lands in it.
          (beside (with-selected-window below (split-window-right 40))))
     (set-window-buffer below (get-buffer-create "*rows*"))
     (set-window-buffer beside (get-buffer-create "*more rows*"))
     (dolist (name '("*rows*" "*more rows*"))
       (with-current-buffer (get-buffer-create name)
         (erase-buffer)
         (insert (format "%s\n" (if (equal name "*rows*")
                                    "boxed around its own rows"
                                  "and beside it")))
         (setq-local header-line-format
                     (format " a header line in %s " name)
                     mode-line-format (format " a mode line in %s " name))
         (window-box-mode 1))))
   (redisplay t)
   (run-with-timer 1.0 nil (lambda () (kill-emacs 0)))))
;;; tty-test.el ends here
