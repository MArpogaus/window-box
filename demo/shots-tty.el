;; -*- lexical-binding: t; -*-
;; The session shots.py captures for the terminal screenshot.
(add-to-list 'load-path (expand-file-name ".." (file-name-directory
                                                load-file-name)))
(require 'window-box)
(setq inhibit-startup-screen t ring-bell-function #'ignore)
(menu-bar-mode -1)

(defun shots-tty--buffer (name encloses text)
  "Return a buffer NAME showing TEXT, with ENCLOSES set in it."
  (let ((buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (erase-buffer)
      (insert text)
      (goto-char (point-min))
      (setq-local header-line-format " a header line of my own "
                  mode-line-format " a mode line of my own "
                  window-box-encloses encloses)
      (window-box-mode 1))
    buffer))

(run-with-timer
 0.5 nil
 (lambda ()
   (switch-to-buffer
    (shots-tty--buffer "*everything*" '(header-line mode-line)
                       "window-box-encloses '(header-line mode-line)\n\
the whole window: the top edge takes the free tab line row,\n\
and the mode line closes the box, a terminal having no row below it\n"))
   (delete-other-windows)
   (let ((below (split-window (frame-root-window) -12 'below)))
     (set-window-buffer
      below (shots-tty--buffer
             "*text*" nil
             "window-box-encloses nil\n\
the text alone: the rows the window brought stay outside, and a\n\
terminal has no row to draw an edge between them and the text\n")))
   (window-box--refresh)
   (redisplay t)
   (run-with-timer 1.0 nil (lambda () (kill-emacs 0)))))
