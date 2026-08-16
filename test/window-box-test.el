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
    (let ((window-box-encloses nil))
      (window-box--apply (selected-window))
      (should-not (window-parameter (selected-window) 'mode-line-format))
      (window-box--clear (selected-window)))
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
  "A window that shows tabs keeps them, whatever the box does with the row.
Left out of `window-box-encloses\=' the row is not touched at all; taken
in, the box puts its ends on it and the tabs show between them."
  (window-box-test--with-buffer
    (setq-local tab-line-format " tabs ")
    (let ((window-box-encloses nil))
      (window-box--apply (selected-window))
      (should-not (window-parameter (selected-window) 'tab-line-format))
      (window-box--clear (selected-window)))
    (let ((window-box-encloses '(tab-line)))
      (window-box--apply (selected-window))
      (should (equal (window-parameter (selected-window) 'tab-line-format)
                     window-box--tab-row-format))
      (should (equal (window-box--content (selected-window) 'tab-line-format)
                     " tabs "))
      (window-box--clear (selected-window))
      (should-not (window-parameter (selected-window) 'tab-line-format)))))

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
    (should (window-box--line-visible-p (selected-window) 'mode-line-format))
    (set-window-parameter (selected-window) 'mode-line-format 'none)
    (should-not (window-box--line-visible-p (selected-window)
                                            'mode-line-format))
    ;; a header handed down by the window, as side window rules do
    (setq-local header-line-format nil)
    (set-window-parameter (selected-window) 'header-line-format "param")
    (should (window-box--line-visible-p (selected-window)
                                        'header-line-format))
    ;; a row the box put its ends on is the window's own row still
    (window-box--dress (selected-window) 'header-line-format
                       window-box--header-row-format)
    (should (window-box--line-visible-p (selected-window)
                                        'header-line-format))
    (window-box--undress (selected-window) 'header-line-format)
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
  (skip-unless (not (display-graphic-p)))
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
  (skip-unless (not (display-graphic-p)))
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

(ert-deftest window-box-test-predicate-picks-the-windows ()
  "A box can be a window's, not only a buffer's.
The mode is the buffer's, and a help buffer is shown in a panel and
in an ordinary window at once; the predicate says which of them is
framed."
  (let ((buffer (generate-new-buffer "*window-box test*")))
    (unwind-protect
        (with-current-buffer buffer
          (insert "one\ntwo\n")
          (set-window-buffer (selected-window) buffer)
          (window-box-mode 1)
          (window-box--refresh)
          (should (window-parameter (selected-window) 'window-box))
          ;; a predicate that says no takes the box off again
          (let ((window-box-window-predicate #'ignore))
            (window-box--refresh)
            (should-not (window-parameter (selected-window) 'window-box)))
          ;; and one that says yes puts it back
          (let ((window-box-window-predicate (lambda (_window) t)))
            (window-box--refresh)
            (should (window-parameter (selected-window) 'window-box))))
      (set-window-margins (selected-window) nil nil)
      (kill-buffer buffer))))

(ert-deftest window-box-test-two-windows-share-the-prefix ()
  "Unboxing one window leaves the other window's sides alone.
In a terminal the sides hang on the buffer's own prefix, which serves
every boxed window of that buffer at once."
  (skip-unless (not (display-graphic-p)))
  (let ((buffer (generate-new-buffer "*window-box test*")))
    (unwind-protect
        (with-current-buffer buffer
          (insert "one\ntwo\n")
          (set-window-buffer (selected-window) buffer)
          (let ((other (split-window)))
            (set-window-buffer other buffer)
            (window-box-mode 1)
            (window-box--refresh)
            (should (local-variable-p 'line-prefix))
            ;; one of the two is no longer a window to box
            (let ((window-box-window-predicate
                   (lambda (window) (not (eq window other)))))
              (window-box--refresh)
              (should-not (window-parameter other 'window-box))
              (should (window-parameter (selected-window) 'window-box))
              (should (local-variable-p 'line-prefix)))
            (delete-window other)))
      (set-window-margins (selected-window) nil nil)
      (kill-buffer buffer))))

(ert-deftest window-box-test-gives-way-to-a-buffer-margin ()
  "A buffer that asks for a margin after the box went up gets it.
Emacs applies `left-margin-width' when a buffer is displayed, so a
mode that asks for a margin later — outline drawing its buttons there
— would never be seen: the box has written its own width into the
window by then, and its side glyph would land in the column the
buttons use."
  (skip-unless (not (display-graphic-p)))
  (let ((buffer (generate-new-buffer "*window-box test*")))
    (unwind-protect
        (with-current-buffer buffer
          (insert "one\ntwo\n")
          (set-window-buffer (selected-window) buffer)
          (window-box-mode 1)
          (window-box--refresh)
          (should (equal (window-margins (selected-window)) '(1 . 1)))
          (should (local-variable-p 'line-prefix))
          ;; the buffer asks for two columns of its own
          (setq left-margin-width 2)
          (window-box--refresh)
          (should-not (local-variable-p 'line-prefix))
          ;; and the window shows the buffer's width, not the box's
          (should (equal (window-margins (selected-window)) '(2))))
      (set-window-margins (selected-window) nil nil)
      (kill-buffer buffer))))

(ert-deftest window-box-test-survives-a-major-mode-change ()
  "The box is still there after a major mode change.
`kill-all-local-variables' clears a buffer local minor mode like any
other local variable, and an org source block gets its major mode
after the buffer is displayed, so every such panel came up bare."
  (let ((buffer (generate-new-buffer "*window-box test*")))
    (unwind-protect
        (with-current-buffer buffer
          (insert "one\n")
          (set-window-buffer (selected-window) buffer)
          (window-box-mode 1)
          (window-box--refresh)
          (should (window-parameter (selected-window) 'window-box))
          (should (local-variable-p 'line-prefix))
          (emacs-lisp-mode)
          ;; the mode survives the change
          (should window-box-mode)
          (should (window-parameter (selected-window) 'window-box))
          ;; and what the change cleared is drawn again, from the hook
          ;; the mode installs: the prefix that carries the sides is
          ;; no more permanent-local than the face remaps are
          (should (local-variable-p 'line-prefix)))
      (set-window-margins (selected-window) nil nil)
      (kill-buffer buffer))))

(ert-deftest window-box-test-mode-is-autoloaded ()
  "The mode carries its own autoload cookie.
A configuration turns it on from a hook, in a buffer that was just
displayed, before anything has loaded the package.  A cookie that
slips onto the form above describes that form instead, and the mode
gets none — which is what happened when the permanent-local put was
added."
  (skip-unless (fboundp 'loaddefs-generate))
  (let* ((library (locate-library "window-box"))
         (source (and library
                      (if (string-suffix-p ".elc" library)
                          (substring library 0 -1)
                        library)))
         (directory (make-temp-file "window-box-autoloads" t))
         ;; not `make-temp-file': `loaddefs-generate' writes nothing
         ;; when its output is newer than the sources, and a file
         ;; created a moment ago always is
         (file (expand-file-name "autoloads.el" directory)))
    (skip-unless (and source (file-exists-p source)))
    (unwind-protect
        (progn
          (loaddefs-generate (file-name-directory source) file)
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (should (re-search-forward "(autoload 'window-box-mode" nil t))))
      (delete-directory directory t))))

(ert-deftest window-box-test-split-keeps-its-own-margins ()
  "A window split off while the box is on gets its own margins back.
Emacs gives a new window what the one it was split from had, so it
arrives wearing the box's one column, and saving that would give it
back as the width the window is supposed to have."
  (skip-unless (not (display-graphic-p)))
  (let ((buffer (generate-new-buffer "*window-box test*")))
    (unwind-protect
        (with-current-buffer buffer
          (insert "one\ntwo\n")
          (set-window-buffer (selected-window) buffer)
          (window-box-mode 1)
          (window-box--refresh)
          (should (equal (window-margins (selected-window)) '(1 . 1)))
          (let ((other (split-window)))
            (window-box--refresh)
            (should (equal (window-parameter other 'window-box--saved-margins)
                           (list left-margin-width right-margin-width)))
            (window-box-mode -1)
            (window-box--refresh)
            (should (equal (window-margins other) '(nil)))
            (should (equal (window-margins (selected-window)) '(nil)))
            (delete-window other)))
      (set-window-margins (selected-window) nil nil)
      (kill-buffer buffer))))

(ert-deftest window-box-test-remaps-name-the-windows-they-apply-to ()
  "A remap says which windows it is for, since it is the buffer\='s.
Without that, a window `window-box-window-predicate\=' spares wears
the box\='s colours: measured on a graphic frame, its fringes in the
box colour at their full eight pixel width and the box\='s overline on
its mode line."
  (with-temp-buffer
    (window-box--remap 'fringe (list :background "red"))
    (let ((spec (cadr (assq 'fringe face-remapping-alist))))
      (should (eq (car-safe spec) :filtered))
      (should (equal (nth 1 spec) '(:window window-box t)))
      (should (equal (nth 2 spec) '(:background "red"))))))

(ert-deftest window-box-test-a-hidden-tab-line-stays-hidden ()
  "A window that had hidden its tab line has it hidden again after.
The top edge goes in the tab line parameter, so it has to hand back
what it found there, the same as the bottom edge does with the mode
line."
  (window-box-test--with-buffer
    (set-window-parameter (selected-window) 'tab-line-format 'none)
    (window-box--apply (selected-window))
    (should (equal (window-parameter (selected-window) 'tab-line-format)
                   window-box--top-format))
    (window-box--clear (selected-window))
    (should (eq (window-parameter (selected-window) 'tab-line-format)
                'none))
    (set-window-parameter (selected-window) 'tab-line-format nil)))

(ert-deftest window-box-test-encloses-moves-the-edges ()
  "`window-box-encloses\=' says which rows are inside the box.
A batch session is a terminal, where an edge needs a row of its own:
the free tab line row above the text, and none at all below the mode
line.  So a terminal draws the top edge where the tab line row is
free and leaves the closing to the row that ends the box."
  (window-box-test--with-buffer
    (setq-local header-line-format " header "
                mode-line-format " mode ")
    (let ((window (selected-window)))
      ;; the text alone: neither row is inside, and a terminal has
      ;; nowhere to draw an edge between them and the text
      (let ((window-box-encloses nil))
        (should-not (window-box--top-edge window))
        (should-not (window-box--bottom-edge window))
        (should-not (window-box--dressed-rows window)))
      ;; both rows inside: the top edge goes in the free tab line row,
      ;; and the mode line closes the box at the bottom
      (let ((window-box-encloses '(header-line mode-line)))
        (should (eq (window-box--top-edge window) 'own))
        (should-not (window-box--bottom-edge window))
        (should (equal (window-box--dressed-rows window)
                       '(header-line-format mode-line-format)))
        ;; the ends: a vertical edge where the box goes on, corners
        ;; where the row is the one that closes it
        (should (equal (window-box--corners window 'header-line-format)
                       '(4 4)))
        (should (equal (window-box--corners window 'mode-line-format)
                       '(2 3))))
      ;; tabs, which take the row the top edge would have used
      (setq-local tab-line-format " tabs ")
      (let ((window-box-encloses '(tab-line header-line mode-line)))
        (should-not (window-box--top-edge window))
        (should (equal (window-box--corners window 'tab-line-format)
                       '(0 1)))))))

(ert-deftest window-box-test-a-row-keeps-what-it-showed ()
  "A row the box draws its ends on shows the window\='s own row between them."
  (window-box-test--with-buffer
    (setq-local header-line-format " header ")
    (let ((window-box-encloses '(header-line))
          (window (selected-window)))
      (window-box--apply window)
      (should (equal (window-parameter window 'header-line-format)
                     window-box--header-row-format))
      (let ((row (window-box--row 'header-line-format)))
        (should (equal (nth 1 row) " header "))
        (should (equal (nth 0 row) (window-box--cap 4)))
        (should (equal (nth 3 row) (window-box--cap 4))))
      (window-box--clear window)
      (should-not (window-parameter window 'header-line-format)))))

(ert-deftest window-box-test-a-row-of-the-window-s-own-comes-back ()
  "A header the window itself carried is given back, not the buffer\='s.
Side window rules hand a window its own header line, and the box has
to put that one back rather than the one the buffer would show."
  (window-box-test--with-buffer
    (setq-local header-line-format " buffer ")
    (let ((window-box-encloses '(header-line))
          (window (selected-window)))
      (set-window-parameter window 'header-line-format " window ")
      (window-box--apply window)
      (should (equal (nth 1 (window-box--row 'header-line-format)) " window "))
      (window-box--clear window)
      (should (equal (window-parameter window 'header-line-format) " window "))
      (set-window-parameter window 'header-line-format nil))))

(ert-deftest window-box-test-a-saved-window-comes-back-marked ()
  "A window put away with the box on knows it is boxed when it returns.
`window-state-get\=' saves the margins and the fringes, so the box\='s
widths travel with a window that is hidden — a side window toggled
away.  Without the mark travelling too, a mode turned off in the
meantime would leave those widths on a window nothing knows to
undress."
  (window-box-test--with-buffer
    (window-box-mode 1)
    (should (equal (window-margins (selected-window)) '(1 . 1)))
    (let ((state (window-state-get (selected-window))))
      (window-box-mode -1)
      (window-state-put state (selected-window))
      (should (window-parameter (selected-window) 'window-box))
      (should (equal (window-margins (selected-window)) '(1 . 1)))
      ;; the buffer is not boxed anymore, so the refresh takes the
      ;; widths back off
      (window-box--refresh)
      (should-not (window-parameter (selected-window) 'window-box))
      (should (equal (window-margins (selected-window)) '(nil . nil))))))

(provide 'window-box-test)
;;; window-box-test.el ends here
