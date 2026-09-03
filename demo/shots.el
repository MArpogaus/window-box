;; -*- lexical-binding: t; -*-
;; Draws the README screenshots; see README.org in this directory.
(add-to-list 'load-path (expand-file-name ".." (file-name-directory
                                                load-file-name)))
(require 'window-box)
(setq inhibit-startup-screen t ring-bell-function #'ignore)
;; The fringes stay as they are: the box draws its sides in the
;; margins and leaves the fringes to their indicators.
(menu-bar-mode -1) (tool-bar-mode -1) (scroll-bar-mode -1)
(blink-cursor-mode -1)
;; Window dividers.  Without them Emacs paints `vertical-border' over
;; the first column of a right hand window's left fringe, which is
;; where the box draws its left side: the border wins and the picture
;; shows a box with a side missing.  A divider has a column of its own
;; and leaves the fringe alone.  One pixel keeps the picture tight.
(setq window-divider-default-places 'right-only
      window-divider-default-right-width 1)
(window-divider-mode 1)
(setq-default cursor-type 'bar)
(let ((font (seq-find (lambda (name) (find-font (font-spec :name name)))
                      '("FiraCode Nerd Font" "Source Code Pro"
                        "DejaVu Sans Mono" "Noto Sans Mono"))))
  (when font (set-frame-font (format "%s 13" font) nil t)))


;; The screenshots show where the edges land, so the box is drawn in a
;; color rather than in the grey of the `window-box' face: a one pixel
;; grey line on a grey mode line is honest and invisible.
(setq-default window-box-color "#5e81ac")

(defvar shots-directory
  (expand-file-name "../img" (file-name-directory load-file-name))
  "Where the screenshots land.")

(defun shots--write (name)
  "Export the frame as NAME in `shots-directory'."
  ;; The startup notice sits in the echo area of a fresh Emacs.
  (message nil)
  (redisplay t)
  (let ((coding-system-for-write 'binary))
    (write-region (x-export-frames nil 'png) nil
                  (expand-file-name name shots-directory) nil 'quiet)))

(defun shots--buffer (name top mode-line text &optional tabs)
  "Return a buffer NAME showing TEXT, with the enclose options set.
TOP is `window-box-enclose-top', MODE-LINE is
`window-box-enclose-mode-line', TABS non-nil gives it a tab line of
its own as well."
  (let ((buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (erase-buffer)
      (insert text)
      (goto-char (point-min))
      (setq-local header-line-format " a header line of my own "
                  mode-line-format " a mode line of my own "
                  window-box-enclose-top top
                  window-box-enclose-mode-line mode-line)
      (when tabs (setq-local tab-line-format " a tab line of my own "))
      (window-box-mode 1))
    buffer))

(defconst shots-width 820
  "How wide every picture of these packages is, in pixels.")

(defun shots--frame (height)
  "Ask the frame for `shots-width' pixels across and HEIGHT down.
A frame is whole columns wide, so it is asked for the most columns that
fit; whatever is missing is a few pixels of the frame's own edge, which
`shots.py' pads."
  (let ((fringes (+ (frame-parameter nil 'left-fringe)
                    (frame-parameter nil 'right-fringe))))
    (set-frame-size (selected-frame)
                    (/ (- shots-width fringes) (frame-char-width))
                    (/ height (frame-char-height)))
    (while (> (frame-pixel-width) shots-width)
      (set-frame-width (selected-frame) (1- (frame-width))))))

(defun shots-encloses ()
  "One window per enclose shape, boxed."
  (shots--frame 520)
  (switch-to-buffer
   (shots--buffer "*text*" nil nil
                  "enclose nothing\nthe text alone\n"))
  (delete-other-windows)
  ;; A share of the frame each, taken from the top: splitting in half
  ;; and in half again leaves the last window too small to split.
  (let* ((share (/ (window-total-height (frame-root-window)) 4))
         (first (selected-window))
         (second (split-window first share 'below))
         (third (split-window second share 'below))
         (fourth (split-window third share 'below)))
    (set-window-buffer
     second (shots--buffer "*header*" 'header-line nil
                           "enclose-top 'header-line\n\
the header inside, the mode line out\n"))
    (set-window-buffer
     third (shots--buffer "*header and mode*" 'header-line t
                          "enclose-top 'header-line, mode line in\n\
both inside\n"))
    (set-window-buffer
     fourth (shots--buffer "*everything*" 'tab-line t
                           "enclose-top 'tab-line, mode line in\n\
the whole window, which is the default\n"
                           t))
    (window-box--refresh)
    (force-mode-line-update t)
    (shots--write "encloses-gui.png")
    (dolist (window (list first second third fourth))
      (with-current-buffer (window-buffer window) (window-box-mode -1)))
    (delete-other-windows)))

(defun shots-windows ()
  "One buffer in two windows, boxed in one of them only."
  (shots--frame 320)
  (let ((buffer (get-buffer-create "*notes*")))
    (with-current-buffer buffer
      (erase-buffer)
      ;; Short lines: each window is half of 840 pixels wide, and a
      ;; line that does not fit is truncated in the picture.
      (insert ";; The same buffer, two windows.\n"
              ";;\n"
              ";; A predicate says which windows\n"
              ";; wear the box — here the right.\n")
      (goto-char (point-min))
      (setq-local mode-line-format " *notes* "))
    (switch-to-buffer buffer)
    (delete-other-windows)
    (split-window-right)
    (setq window-box-window-predicate
          ;; the right hand one of the two
          (lambda (window) (window-prev-sibling window)))
    (with-current-buffer buffer (window-box-mode 1))
    (window-box--refresh)
    (force-mode-line-update t)
    (shots--write "windows-gui.png")
    (with-current-buffer buffer (window-box-mode -1))
    (setq window-box-window-predicate nil)
    (delete-other-windows)))

(defun shots-screenshot ()
  "Two side windows boxed, the main window plain."
  (shots--frame 520)
  ;; The resize is an X round trip; drawing before it lands would
  ;; export the frame at the last scene's height.
  (sit-for 0.3)
  (let ((main (get-buffer-create "*main*")))
    (with-current-buffer main
      (erase-buffer)
      (insert "The main window keeps its own dressing.\n")
      (goto-char (point-min))
      (setq-local mode-line-format " *main* "))
    (switch-to-buffer main)
    (delete-other-windows)
    (dolist (spec '(("*top*" top "The top side window is boxed.\n")
                    ("*bottom*" bottom "The bottom side window is boxed.\n")))
      (let ((buffer (get-buffer-create (car spec))))
        (with-current-buffer buffer
          (erase-buffer)
          (insert (nth 2 spec))
          (goto-char (point-min))
          (setq-local header-line-format (format " %s " (car spec))
                      mode-line-format nil)
          (window-box-mode 1))
        (display-buffer-in-side-window
         buffer `((side . ,(nth 1 spec)) (window-height . 6)))))
    (window-box--refresh)
    (force-mode-line-update t)
    (shots--write "screenshot.png")
    (dolist (name '("*top*" "*bottom*"))
      (with-current-buffer name (window-box-mode -1)))
    (delete-other-windows)))

(run-with-timer
 1.0 nil
 (lambda ()
   (condition-case err
       (progn (shots-encloses) (shots-windows) (shots-screenshot)
              (kill-emacs 0))
     (error (write-region (format "shots: %S\n" err) nil
                          "/tmp/window-box-shots-error.txt" nil 'quiet)
            (kill-emacs 1)))))
