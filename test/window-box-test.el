;;; window-box-test.el --- Tests for window-box -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Marcel Arpogaus

;; Author: Marcel Arpogaus <znepry.necbtnhf@tznvy.pbz>
;; Assisted-by: Claude:claude-fable-5
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

;; Run with: make test
;;
;; A batch session has a frame and windows, just no display, so the
;; box building and the window bookkeeping are testable here.  What
;; the box looks like is checked by eye and by the terminal test in
;; demo/.

;;; Code:

(require 'ert)
(require 'window-box)

(defmacro window-box-test--with-buffer (&rest body)
  "Evaluate BODY in a buffer shown in the selected window."
  (declare (indent 0))
  `(let ((buffer (generate-new-buffer "*window-box test*")))
     (unwind-protect
         (progn
           (set-window-buffer (selected-window) buffer)
           (with-current-buffer buffer
             (insert "one\ntwo\n")
             ,@body))
       (window-box--clear (selected-window))
       (kill-buffer buffer))))

;;;; The edge strings

(ert-deftest window-box-test-edge-terminal ()
  "In a terminal the edge is corner, fill characters, corner."
  (skip-unless (not (display-graphic-p)))
  (let ((top (window-box--top))
        (bottom (window-box--bottom)))
    (should (string-prefix-p "┌" top))
    (should (string-suffix-p "┐" top))
    (should (string-match-p "─" top))
    (should (string-prefix-p "└" bottom))
    (should (string-suffix-p "┘" bottom))
    ;; corner + fill + corner spans the whole window
    (should (= (string-width top) (window-total-width)))))

(ert-deftest window-box-test-edge-width-beside-a-neighbour ()
  "The edge spans the window, not the column that separates two.
A terminal puts that column inside `window-total-width', and an edge
one column too long loses its last corner off the end."
  (skip-unless (not (display-graphic-p)))
  (let ((buffer (generate-new-buffer "*window-box test*")))
    (unwind-protect
        (progn
          (delete-other-windows)
          (set-window-buffer (selected-window) buffer)
          (split-window-right 30)
          (with-current-buffer buffer
            (set-window-margins (selected-window) 1 1)
            (let ((margins (window-margins)))
              (should (= (string-width (window-box--top))
                         (+ (window-body-width)
                            (or (car margins) 0)
                            (or (cdr margins) 0))))
              (should (< (string-width (window-box--top))
                         (window-total-width))))
            (set-window-margins (selected-window) nil nil)))
      (delete-other-windows)
      (kill-buffer buffer))))

(ert-deftest window-box-test-prefix ()
  "The line prefix puts one vertical edge into each margin."
  (let ((prefix (window-box--prefix)))
    (should (equal (car (get-text-property 0 'display prefix))
                   '(margin left-margin)))
    (should (equal (car (get-text-property 1 'display prefix))
                   '(margin right-margin)))
    (should (string-match-p "│" (cadr (get-text-property 0 'display prefix))))))

;;;; Boxing windows

(ert-deftest window-box-test-mode-round-trip ()
  "The mode dresses the window and takes the dressing back.
A batch session is a terminal, so the sides are margins here.  One
column is a margin the box may take; wider is the buffer's own, and
`window-box-test-keeps-margins-a-buffer-uses' covers that."
  (window-box-test--with-buffer
    (set-window-margins (selected-window) nil 1)
    (window-box-mode 1)
    (should (equal (window-margins (selected-window)) '(1 . 1)))
    (should (equal (window-parameter (selected-window) 'tab-line-format)
                   '(:eval (window-box--top))))
    (should (stringp line-prefix))
    (should (local-variable-p 'line-prefix))
    (window-box-mode -1)
    (should (equal (window-margins (selected-window)) '(nil . 1)))
    (should-not (window-parameter (selected-window) 'tab-line-format))
    (should-not (window-parameter (selected-window)
                                  'window-box--saved-margins))
    (should-not (local-variable-p 'line-prefix))
    (set-window-margins (selected-window) nil nil)))

(ert-deftest window-box-test-a-prefix-of-your-own-comes-back ()
  "A buffer that had a line prefix keeps it once the box is gone.
The sides live in the prefix, so the box has to hand it back."
  (window-box-test--with-buffer
    (setq-local line-prefix "> " wrap-prefix "| ")
    (window-box-mode 1)
    (should-not (equal line-prefix "> "))
    (window-box-mode -1)
    (should (equal line-prefix "> "))
    (should (equal wrap-prefix "| "))))

(ert-deftest window-box-test-mode-line-stays ()
  "A window with a mode line keeps it; one without gets the edge back."
  (window-box-test--with-buffer
    (setq-local mode-line-format "mine")
    (window-box--apply (selected-window))
    (should-not (window-parameter (selected-window) 'mode-line-format))
    (window-box--clear (selected-window))
    (setq-local mode-line-format nil)
    (set-window-parameter (selected-window) 'mode-line-format 'none)
    (window-box--apply (selected-window))
    (should (equal (window-parameter (selected-window) 'mode-line-format)
                   '(:eval (window-box--bottom))))
    (window-box--clear (selected-window))
    (should (eq (window-parameter (selected-window) 'mode-line-format)
                'none))))

(ert-deftest window-box-test-a-terminal-draws-its-own-top-edge ()
  "A header line carries the top edge only where an overline can be drawn.
A batch session is a terminal, and a terminal has no overline, so the
box draws a row of its own above the header instead of nothing."
  (window-box-test--with-buffer
    (setq-local header-line-format " mine ")
    (window-box--apply (selected-window))
    (should (equal (window-parameter (selected-window) 'tab-line-format)
                   '(:eval (window-box--top))))
    (window-box--clear (selected-window))
    (setq-local header-line-format nil)
    (window-box--apply (selected-window))
    (should (equal (window-parameter (selected-window) 'tab-line-format)
                   '(:eval (window-box--top))))))

(ert-deftest window-box-test-the-box-puts-itself-back ()
  "A window dressed again over the box gets the box back.
Displaying a buffer in a side window sets that window's parameters
anew, and the box's top edge went with them."
  (window-box-test--with-buffer
    (window-box-mode 1)
    (set-window-parameter (selected-window) 'tab-line-format 'none)
    (set-window-margins (selected-window) nil nil)
    (window-box--refresh)
    (should (equal (window-parameter (selected-window) 'tab-line-format)
                   window-box--top-format))
    (should (equal (window-margins (selected-window)) '(1 . 1)))
    (window-box-mode -1)))

(ert-deftest window-box-test-a-tab-line-of-your-own-stays ()
  "A window that shows tabs keeps them; the box does not take the row."
  (window-box-test--with-buffer
    (setq-local tab-line-format " tabs ")
    (window-box--apply (selected-window))
    (should-not (window-parameter (selected-window) 'tab-line-format))
    (window-box--clear (selected-window))))

(ert-deftest window-box-test-refresh-leaves-foreign-parameters ()
  "Unboxing only removes what the package drew."
  (window-box-test--with-buffer
    (set-window-parameter (selected-window) 'tab-line-format "foreign")
    (window-box--refresh)
    (should (equal (window-parameter (selected-window) 'tab-line-format)
                   "foreign"))
    (set-window-parameter (selected-window) 'tab-line-format nil)))

(ert-deftest window-box-test-line-visible ()
  "The window parameter wins over the buffer's format."
  (window-box-test--with-buffer
    (setq-local mode-line-format "mine")
    (should (window-box--line-visible-p (selected-window)
                                        'mode-line-format
                                        mode-line-format))
    (set-window-parameter (selected-window) 'mode-line-format 'none)
    (should-not (window-box--line-visible-p (selected-window)
                                            'mode-line-format
                                            mode-line-format))
    ;; a header handed down by the window, as side window rules do
    (setq-local header-line-format nil)
    (set-window-parameter (selected-window) 'header-line-format "param")
    (should (window-box--line-visible-p (selected-window)
                                        'header-line-format
                                        header-line-format))
    (set-window-parameter (selected-window) 'mode-line-format nil)
    (set-window-parameter (selected-window) 'header-line-format nil)))

(ert-deftest window-box-test-boxing-twice-saves-the-prefix-once ()
  "A second box does not save the first one's prefix as the buffer's."
  (window-box-test--with-buffer
    (setq-local line-prefix "> ")
    (window-box--apply (selected-window))
    (window-box--apply (selected-window))
    (window-box--clear (selected-window))
    (should (equal line-prefix "> "))))

(ert-deftest window-box-test-characters-of-the-wrong-length ()
  "A value that is not six characters is dropped for the default.
The box is drawn from a `:eval' during redisplay, so reading past the
end of the string would repaint every boxed window as an error
instead of naming the option behind it."
  (let ((default (eval (car (get 'window-box-characters 'standard-value)) t)))
    (dolist (value (list "┌┐└┘│" "+-|" "" nil 42))
      (let ((window-box-characters value))
        (should (equal (window-box--characters) default))
        ;; and the drawing gets through with it
        (should (stringp (window-box--edge 0 1)))
        (should (stringp (window-box--prefix)))))
    ;; six of them, whatever they are, are the user's business
    (let ((window-box-characters "++++|-"))
      (should (equal (window-box--characters) "++++|-"))
      (should (string-prefix-p "+" (window-box--edge 0 1))))))

(ert-deftest window-box-test-keeps-margins-a-buffer-uses ()
  "A window with margins of its own keeps them and loses the sides.
Magit's log writes the author and the date into a wide right margin,
and one column is all a side glyph needs, so anything wider was put
there by the buffer."
  (skip-when (display-graphic-p))
  (let ((buffer (generate-new-buffer "*window-box test*")))
    (unwind-protect
        (with-current-buffer buffer
          (insert "one\ntwo\n")
          (set-window-buffer (selected-window) buffer)
          (set-window-margins (selected-window) 1 30)
          (window-box-mode 1)
          (window-box--refresh)
          (should (equal (window-margins (selected-window)) '(1 . 30)))
          (should-not (local-variable-p 'line-prefix))
          ;; and unboxing gives the buffer's own margins back untouched
          (window-box-mode -1)
          (window-box--refresh)
          (should (equal (window-margins (selected-window)) '(1 . 30))))
      ;; leave the window as it was for whatever runs next
      (set-window-margins (selected-window) nil nil)
      (kill-buffer buffer))))

(ert-deftest window-box-test-gives-way-to-a-late-margin ()
  "A buffer that sets its margins after the box went up gets them."
  (skip-when (display-graphic-p))
  (let ((buffer (generate-new-buffer "*window-box test*")))
    (unwind-protect
        (with-current-buffer buffer
          (insert "one\ntwo\n")
          (set-window-buffer (selected-window) buffer)
          (window-box-mode 1)
          (window-box--refresh)
          (should (equal (window-margins (selected-window)) '(1 . 1)))
          (should (local-variable-p 'line-prefix))
          (set-window-margins (selected-window) 1 30)
          (window-box--refresh)
          (should (equal (window-margins (selected-window)) '(1 . 30)))
          (should-not (local-variable-p 'line-prefix)))
      (set-window-margins (selected-window) nil nil)
      (kill-buffer buffer))))

(provide 'window-box-test)
;;; window-box-test.el ends here
