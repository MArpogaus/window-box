;;; gui-test.el --- Graphic display session for the pixel test -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded by `make gui' inside a graphic Emacs.  It boxes two side
;; windows, exports the frame and exits; gui-check.py reads the pixels
;; back.
;;
;; The header line here measures itself with `string-pixel-width', the
;; way a header with right aligned buttons has to.  That measurement
;; re-enters redisplay, and it is what turned a face `:height' below
;; one in a side window's mode line into a stack overflow.  Keep it.

;;; Code:

(require 'window-box)

;; Only a build with X has it, and only such a build runs this test.
(declare-function x-export-frames "xfns.c" (&optional frames type))

;; A scroll bar sits outside the fringe, so the box's right edge would
;; land inside it.  Off, as a configuration that wants boxes has it.
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

(defconst gui-test-file "/tmp/window-box-gui.png"
  "Where the exported frame lands.")

(defconst gui-test-geometry "/tmp/window-box-gui.txt"
  "Where the pixel edges of the boxed windows land.
The checker needs them: a frame holds more grey lines than this
package draws, the mode line's own shadow among them.")

(defvar gui-test-header
  '(:eval
    (let* ((chip (propertize " ! " 'face '(:background "#d08770"
                                           :foreground "white")))
           (buttons (concat (propertize "─" 'mouse-face 'highlight)
                            " "
                            (propertize "✕" 'mouse-face 'highlight))))
      (list chip " " (format-mode-line "%b")
            (propertize " " 'display
                        `(space :align-to
                                (- right (,(string-pixel-width
                                            (propertize buttons 'face
                                                        'header-line))))))
            buttons)))
  "A header line that measures itself, as a real one does.")

(defun gui-test--run ()
  "Box two side windows, export the frame and exit."
  (set-frame-size (selected-frame) 700 520 t)
  (switch-to-buffer (get-buffer-create "*main*"))
  (delete-other-windows)
  (insert "The main window keeps its own dressing.\n")
  (dolist (side '(top bottom))
    (let ((buffer (get-buffer-create (format "*%s*" side))))
      (with-current-buffer buffer
        (erase-buffer)
        (insert (format "The %s side window is boxed.\n" side))
        (setq-local header-line-format gui-test-header
                    mode-line-format nil))
      (display-buffer-in-side-window buffer `((side . ,side)
                                              (window-height . 6)))
      (with-current-buffer buffer (window-box-mode 1))))
  (force-mode-line-update t)
  (redisplay t)
  (write-region
   (mapconcat (lambda (window)
                (format "%s\n" (string-join
                                (mapcar #'number-to-string
                                        (window-edges window nil nil t))
                                " ")))
              (seq-filter (lambda (window)
                            (buffer-local-value 'window-box-mode
                                                (window-buffer window)))
                          (window-list nil 'no-minibuffer))
              "")
   nil gui-test-geometry nil 'quiet)
  (let ((coding-system-for-write 'binary))
    (write-region (x-export-frames nil 'png) nil gui-test-file nil 'quiet))
  (kill-emacs 0))

;; Wait for the frame: the test measures pixels, so redisplay has to
;; have brought it up.
(run-with-timer 0.5 nil
                (lambda ()
                  (condition-case err (gui-test--run)
                    (error (message "gui-test: %S" err)
                           (kill-emacs 1)))))

(provide 'gui-test)
;;; gui-test.el ends here
