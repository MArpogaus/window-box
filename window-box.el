;;; window-box.el --- A rectangular box around a window -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Marcel Arpogaus

;; Author: Marcel Arpogaus <znepry.necbtnhf@tznvy.pbz>
;; Assisted-by: Claude:claude-fable-5
;; Version: 0.1
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience, frames
;; URL: https://github.com/MArpogaus/window-box

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
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `window-box-mode' draws a rectangular box around every window that
;; shows the buffer.  Nothing more: the mode line and the header line
;; stay whatever you made them.
;;
;; The box is built from the window dressing Emacs already has, so it
;; works on graphic displays and in the terminal alike:
;;
;; - The top edge is the window's tab line, set through the window
;;   parameter, so the buffer's own `tab-line-format' is not touched.
;; - The side edges are glyphs in one-column display margins, drawn
;;   through an overlay that carries the `window' property — each
;;   window gets its own, so one buffer in two windows works.
;; - The bottom edge is your mode line.  Only when the window shows no
;;   mode line does the box draw one, again through the window
;;   parameter.
;;
;; The idea of building boxes from the tab line and the margins comes
;; from Nicolas Rougier's buffer-box:
;; https://github.com/rougier/buffer-box
;;
;; Known limits, shared with buffer-box: the side edges run along
;; lines of text, so they stop where the buffer ends; a scroll bar
;; that is not a multiple of the character width can offset the top
;; right corner.

;;; Code:

(require 'seq)

(defgroup window-box nil
  "A rectangular box around a window."
  :group 'convenience
  :prefix "window-box-")

(defface window-box '((t :inherit shadow))
  "Face of the box around unselected windows.")

(defface window-box-selected '((t :inherit default))
  "Face of the box around the selected window.")

(defcustom window-box-characters "┌┐└┘│─"
  "The six characters the box is drawn with.
In order: the four corners, the vertical edge, the horizontal edge.
On a graphic display the horizontal edges are drawn as pixel-exact
lines instead of the sixth character."
  :type 'string)

;;;; Drawing

(defun window-box--face ()
  "Return the face for the window the box is drawn in."
  (if (mode-line-window-selected-p) 'window-box-selected 'window-box))

(defun window-box--edge (left right)
  "Return one horizontal edge, from corner LEFT to corner RIGHT.
Corners name indices into `window-box-characters'.  The fill is a
stretch space with a strike-through line on a graphic display, which
meets the right window edge exactly; in a terminal the columns are
exact anyway, and the fill is the horizontal edge character."
  (let ((face (window-box--face)))
    (concat
     (propertize (string (aref window-box-characters left)) 'face face)
     (if (display-graphic-p)
         ;; An explicit color: `default' specifies every attribute, so
         ;; inheriting from it would put the strike-through back to nil.
         (propertize " "
                     'face (list :strike-through
                                 (face-foreground face nil 'default))
                     'display '(space :align-to (- right 1)))
       (propertize (make-string (max 0 (- (window-total-width) 2))
                                (aref window-box-characters 5))
                   'face face))
     (propertize (string (aref window-box-characters right)) 'face face))))

(defun window-box--top ()
  "Return the top edge of the box."
  (window-box--edge 0 1))

(defun window-box--bottom ()
  "Return the bottom edge of the box."
  (window-box--edge 2 3))

(defun window-box--prefix (window)
  "Return the line prefix that draws the side edges in WINDOW."
  (let* ((face (if (eq window (frame-selected-window (window-frame window)))
                   'window-box-selected
                 'window-box))
         (bar (propertize (string (aref window-box-characters 4))
                          'face face)))
    (concat
     (propertize " " 'display `((margin left-margin) ,bar))
     (propertize " " 'display `((margin right-margin) ,bar)))))

;;;; Boxing and unboxing windows

(defun window-box--overlay (window)
  "Return the side edge overlay of WINDOW, or nil."
  (seq-find (lambda (o) (and (overlay-get o 'window-box)
                             (eq (overlay-get o 'window) window)))
            (overlays-in (point-min) (point-max))))

(defun window-box--apply (window)
  "Draw the box around WINDOW.
Call it with the window's buffer current."
  (set-window-parameter window 'tab-line-format
                        '(:eval (window-box--top)))
  ;; The bottom edge is the user's mode line.  Only a window without
  ;; one gets the drawn edge, and the old parameter comes back when
  ;; the box goes.
  (unless (or mode-line-format
              (equal (window-parameter window 'mode-line-format)
                     '(:eval (window-box--bottom))))
    (set-window-parameter window 'window-box--saved-mode-line
                          (window-parameter window 'mode-line-format))
    (set-window-parameter window 'mode-line-format
                          '(:eval (window-box--bottom))))
  (let ((overlay (or (window-box--overlay window)
                     (let ((o (make-overlay (point-min) (point-max) nil
                                            nil t)))
                       (overlay-put o 'window-box t)
                       (overlay-put o 'window window)
                       o)))
        (prefix (window-box--prefix window)))
    (overlay-put overlay 'line-prefix prefix)
    (overlay-put overlay 'wrap-prefix prefix)))

(defun window-box--clear (window)
  "Remove the box from WINDOW."
  (set-window-parameter window 'tab-line-format nil)
  (when (equal (window-parameter window 'mode-line-format)
               '(:eval (window-box--bottom)))
    (set-window-parameter window 'mode-line-format
                          (window-parameter window
                                            'window-box--saved-mode-line)))
  (with-current-buffer (window-buffer window)
    (when-let* ((overlay (window-box--overlay window)))
      (delete-overlay overlay))))

(defun window-box--refresh (&optional frame)
  "Box and unbox the windows of FRAME to match their buffers."
  (dolist (window (window-list frame 'no-minibuffer))
    (if (buffer-local-value 'window-box-mode (window-buffer window))
        (with-current-buffer (window-buffer window)
          (window-box--apply window))
      ;; Only take away what this package drew.
      (when (equal (window-parameter window 'tab-line-format)
                   '(:eval (window-box--top)))
        (window-box--clear window)))))

(defun window-box--selection-change (frame)
  "Redraw the side edges of FRAME after the selected window changed.
The top and bottom edges follow `mode-line-window-selected-p' on
their own; the side edges are strings and need the new face."
  (dolist (window (window-list frame 'no-minibuffer))
    (when (buffer-local-value 'window-box-mode (window-buffer window))
      (with-current-buffer (window-buffer window)
        (window-box--apply window)))))

;;;; The mode

(defvar-local window-box--saved-margins nil
  "Margin widths (LEFT . RIGHT) from before the mode, as a cons.")

;;;###autoload
(define-minor-mode window-box-mode
  "Draw a rectangular box around every window that shows this buffer.
The mode line and the header line stay untouched: the box only adds
the edges the window does not have.  See the commentary for how the
box is built."
  :lighter ""
  (if window-box-mode
      (progn
        (setq window-box--saved-margins (cons left-margin-width
                                              right-margin-width))
        (setq-local left-margin-width (max 1 left-margin-width)
                    right-margin-width (max 1 right-margin-width))
        (add-hook 'window-buffer-change-functions #'window-box--refresh)
        (add-hook 'window-selection-change-functions
                  #'window-box--selection-change)
        (dolist (window (get-buffer-window-list nil nil t))
          ;; A margin change only shows after the window picked the
          ;; buffer's margins up again.
          (set-window-buffer window (current-buffer))
          (window-box--apply window)))
    (setq-local left-margin-width (car window-box--saved-margins)
                right-margin-width (cdr window-box--saved-margins))
    (kill-local-variable 'window-box--saved-margins)
    (dolist (window (get-buffer-window-list nil nil t))
      (window-box--clear window)
      (set-window-buffer window (current-buffer)))
    (remove-overlays (point-min) (point-max) 'window-box t)))

(provide 'window-box)
;;; window-box.el ends here
