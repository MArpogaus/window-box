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
A batch session is a terminal, so the sides are margins here."
  (window-box-test--with-buffer
    (set-window-margins (selected-window) nil 3)
    (window-box-mode 1)
    (should (equal (window-margins (selected-window)) '(1 . 1)))
    (should (equal (window-parameter (selected-window) 'tab-line-format)
                   '(:eval (window-box--top))))
    (should (window-box--overlay (selected-window)))
    (window-box-mode -1)
    (should (equal (window-margins (selected-window)) '(nil . 3)))
    (should-not (window-parameter (selected-window) 'tab-line-format))
    (should-not (window-parameter (selected-window)
                                  'window-box--saved-margins))
    (should-not (window-box--overlay (selected-window)))
    (set-window-margins (selected-window) nil nil)))

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

(ert-deftest window-box-test-overlay-per-window ()
  "Each window gets its own overlay, found by its window property."
  (window-box-test--with-buffer
    (window-box--apply (selected-window))
    (let ((overlay (window-box--overlay (selected-window))))
      (should overlay)
      (should (eq (overlay-get overlay 'window) (selected-window)))
      ;; applying again reuses it
      (window-box--apply (selected-window))
      (should (eq (window-box--overlay (selected-window)) overlay)))))

(provide 'window-box-test)
;;; window-box-test.el ends here
