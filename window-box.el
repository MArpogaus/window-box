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
;; On a graphic display the box is made of one pixel lines: the side
;; edges are one pixel fringes, which run the full window height, and
;; the top and bottom edges are one pixel rows, or an overline on a
;; line the window already has.  One pixel throughout, because an
;; overline is always one pixel and the rest matches it.  In a terminal the box is
;; made of box-drawing characters, with the sides in one-column
;; margins along the lines of text.
;;
;; Either way, only window dressing is used:
;;
;; - The top edge lives in the window's tab line, set through the
;;   window parameter, so the buffer's own `tab-line-format' is not
;;   touched.
;; - The bottom edge is your mode line.  Only when the window shows no
;;   mode line does the box draw one, again through the window
;;   parameter.
;; - The terminal side edges are glyphs in one column margins, hung on
;;   the buffer's `line-prefix'.  They show only where there are
;;   margins to show them in, which is where the box put them.
;;
;; The idea of building boxes from the tab line and the margins comes
;; from Nicolas Rougier's buffer-box:
;; https://github.com/rougier/buffer-box

;;; Code:

(require 'face-remap)
(require 'seq)

(defgroup window-box nil
  "A rectangular box around a window."
  :group 'convenience
  :prefix "window-box-")

(defface window-box '((t :inherit shadow))
  "Face of the box.
The foreground is the line color.  Remap it buffer-locally for a box
color per buffer.")

(defcustom window-box-characters "┌┐└┘│─"
  "The six characters the box is drawn with in a terminal.
In order: the four corners, the vertical edge, the horizontal edge.
A graphic display draws one pixel lines instead."
  :type 'string)

(defcustom window-box-color nil
  "Color of the box, or nil for the foreground of the `window-box' face.
Set it buffer-locally for a box color per buffer; turning the mode on
again applies it."
  :type '(choice (const :tag "Face foreground" nil) color)
  :local t)

(defcustom window-box-attached-edges t
  "Where the horizontal edges go on a graphic display.
Non-nil attaches them to the lines the window already has: the top
edge becomes an overline on the header line, the bottom edge an
overline on the mode line.  Nil, and wherever those lines are
missing, the edge is a thin bar row of its own.  A terminal always
draws its own rows, from `window-box-characters'."
  :type 'boolean)

;;;; Drawing

(defun window-box--color ()
  "Return the color the box is drawn in.
Never nil: a face with no foreground of its own — a terminal leaves
the default face without one — would give `:overline nil', which is
no overline at all, and an invalid `:background nil'."
  (or window-box-color
      (face-foreground 'window-box nil 'default)
      (frame-parameter nil 'foreground-color)
      "grey50"))

(defun window-box--edge (left right)
  "Return one horizontal edge of the box.
On a graphic display that is a thin bar across the whole row, and
LEFT and RIGHT are unused.  In a terminal it runs from corner LEFT to
corner RIGHT, indices into `window-box-characters', and the columns
are exact."
  (if (display-graphic-p)
      ;; The row's height comes from the display spec alone.  A face
      ;; `:height' below one in a side window's mode line sends Emacs
      ;; into an endless measuring recursion and it dies of a stack
      ;; overflow; the display spec has no such effect.
      (propertize " "
                  ;; Background and overline both: a one pixel row of
                  ;; the box's own takes the background in a tab line
                  ;; but not in a mode line, where the line's own face
                  ;; wins — the overline paints that pixel either way.
                  'face (let ((color (window-box--color)))
                          (list :background color :overline color))
                  ;; Larger than any row is long: the fill stops at the
                  ;; row's end, fringes and margins included, which is
                  ;; where the side edges are.
                  'display '(space :align-to 10000 :height (1)))
    ;; The body and the margins, not `window-total-width': that counts
    ;; the column a terminal puts between two windows side by side, and
    ;; an edge one column too long loses its last corner off the end.
    (let* ((margins (window-margins))
           (width (+ (window-body-width)
                     (or (car margins) 0)
                     (or (cdr margins) 0))))
      (propertize
       (concat (string (aref window-box-characters left))
               (make-string (max 0 (- width 2))
                            (aref window-box-characters 5))
               (string (aref window-box-characters right)))
       'face 'window-box))))

(defun window-box--top ()
  "Return the top edge of the box."
  (window-box--edge 0 1))

(defun window-box--bottom ()
  "Return the bottom edge of the box."
  (window-box--edge 2 3))

(defun window-box--prefix ()
  "Return the line prefix that draws the terminal side edges."
  (let ((bar (propertize (string (aref window-box-characters 4))
                         'face 'window-box)))
    (concat
     (propertize " " 'display `((margin left-margin) ,bar))
     (propertize " " 'display `((margin right-margin) ,bar)))))

;;;; Boxing and unboxing windows

(defvar-local window-box--cookies nil
  "Face remap cookies this buffer holds, as an alist of face and cookie.")

(defvar-local window-box--cookie-color nil
  "Color the cookies were made with, so a change renews them.")

(defun window-box--remap (face &rest spec)
  "Remap FACE in the current buffer with SPEC, once."
  (unless (assq face window-box--cookies)
    (push (cons face (apply #'face-remap-add-relative face spec))
          window-box--cookies)))

(defconst window-box--top-format '(:eval (window-box--top))
  "The tab line format the box draws its own top edge with.")

(defconst window-box--bottom-format '(:eval (window-box--bottom))
  "The mode line format the box draws its own bottom edge with.")

(defun window-box--line-visible-p (window parameter format)
  "Return non-nil when WINDOW shows the line PARAMETER names.
FORMAT is the matching buffer-local format value.  The window
parameter wins: `none' hides the line, any other non-nil value is a
format of its own — unless it is one of the box's own, which is not
a line the window brought along."
  (let ((param (window-parameter window parameter)))
    (cond ((eq param 'none) nil)
          ((member param (list window-box--top-format
                               window-box--bottom-format))
           nil)
          (param t)
          (t format))))

(defvar-local window-box--saved-prefix nil
  "What the buffer's line and wrap prefix were before the box.
A list (LINE WRAP LOCAL), where LOCAL says the buffer had a prefix of
its own, so it goes back as a buffer-local value; without it the
variables are killed again.")

(defun window-box--restore-prefix ()
  "Give the current buffer back the line prefix it had before the box."
  (when-let* ((saved window-box--saved-prefix))
    (if (nth 2 saved)
        (setq-local line-prefix (nth 0 saved)
                    wrap-prefix (nth 1 saved))
      (kill-local-variable 'line-prefix)
      (kill-local-variable 'wrap-prefix))
    (setq window-box--saved-prefix nil)))

(defun window-box--apply (window)
  "Draw the box around WINDOW.
Call it with the window's buffer current."
  (set-window-parameter window 'window-box t)
  (let* ((graphic (display-graphic-p (window-frame window)))
         (attach (and graphic window-box-attached-edges))
         (color (window-box--color)))
    (unless (equal color window-box--cookie-color)
      (dolist (cookie window-box--cookies)
        (face-remap-remove-relative (cdr cookie)))
      (setq window-box--cookies nil
            window-box--cookie-color color))
    ;; The top edge goes in the tab line, which the box draws itself —
    ;; unless the window is using that row for tabs.  Then the tabs are
    ;; the top boundary, and on a graphic display the box marks them
    ;; with an overline: the line's own underline and box give way,
    ;; while content, fonts and colors stay.  A header line can carry
    ;; that overline as well, but only where there is one to draw — a
    ;; terminal has none, and takes the free tab line instead.
    ;;
    ;; Closing the ends of a row the window already has is that row's
    ;; own business: neither margins nor fringes reach it, and a box
    ;; border after a stretch glyph is drawn or clipped at the display
    ;; engine's whim.  A header that wants closed ends draws a glyph at
    ;; each end, as the demo does.
    (cond
     ((window-box--line-visible-p window 'tab-line-format tab-line-format)
      (when attach
        (window-box--remap 'tab-line
                           (list :overline color :underline nil :box nil))))
     ((and attach
           (window-box--line-visible-p window 'header-line-format
                                       header-line-format))
      (window-box--remap 'header-line
                         (list :overline color :underline nil :box nil)))
     ((not (equal (window-parameter window 'tab-line-format)
                  window-box--top-format))
      (set-window-parameter window 'tab-line-format
                            window-box--top-format)))
    ;; The bottom edge: the mode line when there is one, a thin row
    ;; where the window shows none.
    (cond
     ((window-box--line-visible-p window 'mode-line-format mode-line-format)
      (when attach
        (dolist (face '(mode-line-active mode-line-inactive))
          (window-box--remap face
                             (list :overline color :underline nil
                                   :box nil)))))
     ((not (equal (window-parameter window 'mode-line-format)
                  window-box--bottom-format))
      (set-window-parameter window 'window-box--saved-mode-line
                            (window-parameter window 'mode-line-format))
      (set-window-parameter window 'mode-line-format
                            window-box--bottom-format)))
    (if graphic
        ;; Fringes run the full window height, so they make better
        ;; side edges than glyphs along the lines of text.
        (progn
          (unless (window-parameter window 'window-box--saved-fringes)
            (let ((fringes (window-fringes window)))
              (set-window-parameter window 'window-box--saved-fringes
                                    (list (nth 0 fringes) (nth 1 fringes)))))
          (unless (equal (seq-take (window-fringes window) 2) '(1 1))
            (set-window-fringes window 1 1 t))
          (window-box--remap 'fringe (list :background color)))
      ;; A terminal has no fringes; the sides are glyphs in one column
      ;; margins.  They hang on the buffer's `line-prefix' and not on
      ;; an overlay, because an overlay ends where the buffer does and
      ;; the box would end with it, leaving the rows below the last
      ;; line open.  Buffer-wide is no loss of precision: the mode is
      ;; buffer-local, so every window showing the buffer is boxed, and
      ;; a glyph bound for a margin stays invisible in a window that
      ;; has none.
      (unless (window-parameter window 'window-box--saved-margins)
        (let ((margins (window-margins window)))
          (set-window-parameter window 'window-box--saved-margins
                                (list (car margins) (cdr margins)))))
      (unless (equal (window-margins window) '(1 . 1))
        (set-window-margins window 1 1))
      (unless window-box--saved-prefix
        (setq window-box--saved-prefix
              (list line-prefix wrap-prefix (local-variable-p 'line-prefix))))
      (let ((prefix (window-box--prefix)))
        (setq-local line-prefix prefix
                    wrap-prefix prefix)))))

(defun window-box--restore (window parameter setter)
  "Give WINDOW the dressing it had before the box.
The old widths sit in the window PARAMETER as a list (LEFT RIGHT),
where nil stands for the default; SETTER applies them."
  (when-let* ((saved (window-parameter window parameter)))
    (funcall setter window (nth 0 saved) (nth 1 saved))
    (set-window-parameter window parameter nil)))

(defun window-box--clear (window)
  "Remove the box from WINDOW.
The face remaps are the buffer's and go when the mode turns off."
  (set-window-parameter window 'window-box nil)
  (when (equal (window-parameter window 'tab-line-format)
               window-box--top-format)
    (set-window-parameter window 'tab-line-format nil))
  (when (equal (window-parameter window 'mode-line-format)
               window-box--bottom-format)
    (set-window-parameter window 'mode-line-format
                          (window-parameter window
                                            'window-box--saved-mode-line))
    (set-window-parameter window 'window-box--saved-mode-line nil))
  (window-box--restore window 'window-box--saved-fringes
                       #'set-window-fringes)
  (window-box--restore window 'window-box--saved-margins
                       #'set-window-margins)
  (with-current-buffer (window-buffer window)
    (window-box--restore-prefix)))

(defun window-box--refresh (&optional frame)
  "Box and unbox the windows of FRAME to match their buffers.
Showing a buffer resets the window's fringes and margins, so boxed
windows also get theirs back here."
  (dolist (window (window-list frame 'no-minibuffer))
    (if (buffer-local-value 'window-box-mode (window-buffer window))
        (with-current-buffer (window-buffer window)
          (window-box--apply window))
      ;; Only take away what this package drew.
      (when (window-parameter window 'window-box)
        (window-box--clear window)))))

;;;; The mode

;;;###autoload
(define-minor-mode window-box-mode
  "Draw a rectangular box around every window that shows this buffer.
The mode line and the header line stay untouched: the box only adds
the edges the window does not have.  See the commentary for how the
box is built."
  :lighter ""
  (if window-box-mode
      (progn
        ;; Displaying a buffer resets the window's fringes, margins and
        ;; parameters, and a package that dresses windows — side window
        ;; rules, for one — sets its own over the box's every time it
        ;; displays.  So the box puts itself back on both events, and
        ;; only ever changes what differs, or setting the margins here
        ;; would call this back forever.  The hooks stay for the
        ;; session: they walk the windows of one frame and read a
        ;; buffer-local variable, and knowing when the last box went
        ;; would cost more than it saves.
        (add-hook 'window-buffer-change-functions #'window-box--refresh)
        (add-hook 'window-configuration-change-hook #'window-box--refresh)
        (dolist (window (get-buffer-window-list nil nil t))
          (window-box--apply window)))
    (dolist (window (get-buffer-window-list nil nil t))
      (window-box--clear window))
    (dolist (cookie window-box--cookies)
      (face-remap-remove-relative (cdr cookie)))
    (setq window-box--cookies nil
          window-box--cookie-color nil)
    (window-box--restore-prefix)))

(provide 'window-box)
;;; window-box.el ends here
