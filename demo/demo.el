;; -*- lexical-binding: t; -*-
;; Drives the demo recording; see README.org in this directory.
(add-to-list 'load-path "/home/marcel/.emacs.d/packages/window-box")
(require 'window-box)
(setq inhibit-startup-screen t ring-bell-function #'ignore)
;; One pixel fringes from the start: the box narrows the fringes to
;; its own width, and with the default eight the text would shift by
;; seven pixels the moment a box appears.
(fringe-mode 1)
(menu-bar-mode -1) (tool-bar-mode -1) (scroll-bar-mode -1)
(set-frame-font "Source Code Pro 13" nil t)
(blink-cursor-mode -1)
(setq-default cursor-type 'bar)

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

(defun demo ()
  (make-directory "/tmp/demo-wb/frames" t)
  (switch-to-buffer "*scratch*")
  (delete-other-windows)
  (erase-buffer)
  (insert ";; window-box\n"
          ";;\n"
          ";; A rectangular box around a window, nothing more.\n"
          ";; The mode line and the header line stay yours.\n")
  (goto-char (point-min))
  (let ((top (split-window nil 8 'above))
        (right (split-window nil 42 'right)))
    (set-window-buffer top (get-buffer-create "*warning*"))
    (with-current-buffer "*warning*"
      (insert "A side window without a mode line:\nthe box closes the bottom itself.\n")
      (setq-local mode-line-format nil
                  ;; the row closes its own ends: a colored chip left,
                  ;; a one pixel glyph right — the package leaves the
                  ;; header line alone
                  header-line-format
                  '(:eval
                    (list (propertize " ⚠ " 'face '(:inverse-video t))
                          " my own header line, untouched"
                          (propertize " " 'display
                                      '(space :align-to (- right (1))))
                          ;; The box's sides belong to the body, so the
                          ;; header closes its own end — while there is
                          ;; a box to close it against.
                          (if window-box-mode
                              (propertize " " 'face '(:inverse-video t)
                                          'display '(space :width (1)))
                            ""))))
      nil)
    (set-window-buffer right (get-buffer-create "*notes*"))
    (with-current-buffer "*notes*"
      (insert "Boxed, and the normal\nmode line closes the box.\n"))
    (demo--hold 2.5)
    ;; 1. boxes on
    (with-current-buffer "*warning*" (window-box-mode 1))
    (demo--hold 2.5)
    (with-current-buffer "*notes*" (window-box-mode 1))
    (demo--hold 2.5)
    ;; 3. a box color per buffer
    (with-current-buffer "*warning*"
      (setq-local window-box-color "#b48ead")
      (window-box-mode 1))
    (force-mode-line-update t)
    (demo--hold 3.0)
    ;; 4. boxes off
    (with-current-buffer "*warning*" (window-box-mode -1))
    (with-current-buffer "*notes*" (window-box-mode -1))
    (demo--hold 2.5))
  (write-region (format "frames=%d\n" demo--frame) nil "/tmp/demo-wb/done")
  (kill-emacs 0))
(run-with-timer 1.0 nil
                (lambda ()
                  (set-frame-size (selected-frame) 840 500 t)
                  (condition-case err (demo)
                    (error (write-region (format "ERROR %S" err) nil
                                         "/tmp/demo-wb/failed")
                           (kill-emacs 1)))))
