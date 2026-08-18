;; -*- lexical-binding: t; -*-
;; The session shots.py captures for the terminal screenshot.
(add-to-list 'load-path (expand-file-name ".." (file-name-directory
                                                load-file-name)))
(require 'window-box)
(setq inhibit-startup-screen t ring-bell-function #'ignore)
(menu-bar-mode -1)
;; The color every picture in the README draws the box in.  A
;; terminal of 256 colors has no #5e81ac; Emacs sends the nearest,
;; #5f87af, which the eye cannot tell from it.
(setq-default window-box-color "#5e81ac")

(defun shots-tty--buffer (name top mode-line text)
  "Return a buffer NAME showing TEXT, with the enclose options set."
  (let ((buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (erase-buffer)
      (insert text)
      (goto-char (point-min))
      (setq-local header-line-format " a header line of my own "
                  mode-line-format " a mode line of my own "
                  window-box-enclose-top top
                  window-box-enclose-mode-line mode-line)
      (window-box-mode 1))
    buffer))

(run-with-timer
 0.5 nil
 (lambda ()
   (switch-to-buffer
    (shots-tty--buffer "*everything*" 'header-line t
                       "enclose-top 'header-line, mode line in\n\
the whole window: the top edge takes the free tab line row,\n\
and the mode line closes the box, a terminal having no row below it\n"))
   (delete-other-windows)
   (let ((below (split-window (frame-root-window) -12 'below)))
     (set-window-buffer
      below (shots-tty--buffer
             "*text*" nil nil
             "enclose nothing\n\
the text alone: the rows the window brought stay outside, and a\n\
terminal has no row to draw an edge between them and the text\n")))
   (window-box--refresh)
   (redisplay t)
   (run-with-timer 1.0 nil (lambda () (kill-emacs 0)))))
