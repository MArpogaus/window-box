;; -*- lexical-binding: t; -*-
;; Drives the demo recording; see README.org in this directory.
(add-to-list 'load-path (expand-file-name ".." (file-name-directory
                                                load-file-name)))
(require 'window-box)
(setq inhibit-startup-screen t ring-bell-function #'ignore)
;; The fringes stay as they are: the box draws its sides in the
;; margins and leaves the fringes to their indicators.
(menu-bar-mode -1) (tool-bar-mode -1) (scroll-bar-mode -1)
(let ((font (seq-find (lambda (name) (find-font (font-spec :name name)))
                      '("FiraCode Nerd Font" "Source Code Pro"
                        "DejaVu Sans Mono" "Noto Sans Mono"))))
  (when font (set-frame-font (format "%s 13" font) nil t)))
(blink-cursor-mode -1)
(setq-default cursor-type 'bar)
;; A one pixel line in the grey of the `window-box' face is what the
;; package draws by default and is next to invisible in a recording;
;; the colour is an option, and the demo uses it.
(setq-default window-box-color "#5e81ac")

(defvar demo--frame 0)
(defun demo--snap ()
  (cl-incf demo--frame)
  (let ((coding-system-for-write 'binary))
    (write-region (x-export-frames nil 'png) nil
                  (format "/tmp/demo-wb/frames/f%04d.png" demo--frame)
                  nil 'quiet)))
(defun demo--hold (seconds)
  (dotimes (_ (round (* 10 seconds)))
    (redisplay t)
    (demo--snap)
    (sit-for 0.02)))

(defun demo--say (text seconds)
  "Put TEXT in the echo area and hold the frame for SECONDS."
  ;; The echo area is the only room for a word of narration in a frame
  ;; that is otherwise all box.
  (let ((message-log-max nil))
    (message "%s" text)
    (demo--hold seconds)))

(defun demo ()
  (make-directory "/tmp/demo-wb/frames" t)
  (switch-to-buffer "*scratch*")
  (delete-other-windows)
  (erase-buffer)
  (insert ";; window-box\n"
          ";;\n"
          ";; A box around a window, drawn from what the window\n"
          ";; already has: its fringes, its margins, and the rows\n"
          ";; it shows above and below the text.\n")
  (goto-char (point-min))
  ;; A header line as well, so the edges have somewhere to move to
  ;; when the demo changes what the box encloses.
  (setq-local header-line-format " a header line of my own ")
  (demo--say "a buffer in one window" 2.0)
  ;; 1. the box, around the whole window
  (window-box-mode 1)
  (demo--say "window-box-mode" 2.5)
  ;; 2. the same buffer in a second window
  (split-window-right)
  (demo--say "the same buffer in a second window: boxed as well" 3.0)
  ;; 3. and only where the predicate says
  (setq window-box-window-predicate
        (lambda (window) (window-prev-sibling window)))
  (window-box--refresh)
  (force-mode-line-update t)
  (demo--say "window-box-window-predicate: which windows wear it" 3.5)
  ;; 4. what the box encloses
  (setq-local window-box-encloses nil)
  (window-box--refresh)
  (force-mode-line-update t)
  (demo--say "window-box-encloses nil: the text alone" 3.0)
  (setq-local window-box-encloses '(mode-line))
  (window-box--refresh)
  (force-mode-line-update t)
  (demo--say "'(mode-line): the mode line inside the box" 3.0)
  (setq-local window-box-encloses '(tab-line header-line mode-line))
  (setq-local window-box-color "#b48ead")
  (window-box-mode 1)
  (force-mode-line-update t)
  (demo--say "and a color of its own, per buffer" 3.0)
  ;; 4b. round corners
  (setq-local window-box-radius 8)
  (window-box--refresh)
  (force-mode-line-update t)
  (demo--say "window-box-radius: round corners" 3.0)
  (setq-local window-box-radius 0)
  ;; 5. off
  (window-box-mode -1)
  (setq window-box-window-predicate nil)
  (window-box--refresh)
  (force-mode-line-update t)
  (demo--say "" 2.0)
  (write-region (format "frames=%d\n" demo--frame) nil "/tmp/demo-wb/done")
  (kill-emacs 0))
(run-with-timer 1.0 nil
                (lambda ()
                  (set-frame-size (selected-frame) 840 400 t)
                  (condition-case err (demo)
                    (error (write-region (format "ERROR %S" err) nil
                                         "/tmp/demo-wb/failed")
                           (kill-emacs 1)))))
