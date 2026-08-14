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
   (let ((top (split-window nil 6 'above)))
     (set-window-buffer top (get-buffer-create "*boxed*"))
     (with-current-buffer "*boxed*"
       (insert "boxed in the terminal\nsecond line\n")
       (setq-local mode-line-format nil)
       (window-box-mode 1)))
   (redisplay t)
   (run-with-timer 1.0 nil (lambda () (kill-emacs 0)))))
;;; tty-test.el ends here
