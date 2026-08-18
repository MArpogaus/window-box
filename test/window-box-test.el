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
  (skip-unless (not (display-graphic-p)))
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
    (should (equal (window-parameter (selected-window) 'header-line-format)
                   '(:eval (window-box--top))))
    (should (overlayp window-box--prefix-overlay))
    (should (stringp (overlay-get window-box--prefix-overlay 'line-prefix)))
    (should (local-variable-p 'line-prefix))
    (window-box-mode -1)
    (should (equal (window-margins (selected-window)) '(nil . 1)))
    (should-not (window-parameter (selected-window) 'header-line-format))
    (should-not (window-parameter (selected-window)
                                  'window-box--saved-margins))
    (should-not window-box--prefix-overlay)
    (should-not (local-variable-p 'line-prefix))
    (set-window-margins (selected-window) nil nil)))

(ert-deftest window-box-test-a-prefix-of-your-own-comes-back ()
  "A buffer that had a line prefix gets it back once the box is gone.
The sides ride the variable — for the rows below the last line — and
a buffer-spanning overlay, which outranks the prefix a single line
brings as a text property, where the variable loses."
  (window-box-test--with-buffer
    (setq-local line-prefix "> " wrap-prefix "| ")
    (window-box-mode 1)
    (should-not (equal line-prefix "> "))
    (should (overlayp window-box--prefix-overlay))
    (should (= (overlay-start window-box--prefix-overlay) (point-min)))
    (should (= (overlay-end window-box--prefix-overlay) (point-max)))
    ;; Text added at the end wears the sides too.
    (save-excursion (goto-char (point-max)) (insert "three\n"))
    (should (= (overlay-end window-box--prefix-overlay) (point-max)))
    (window-box-mode -1)
    (should-not window-box--prefix-overlay)
    (should (equal line-prefix "> "))
    (should (equal wrap-prefix "| "))))

(ert-deftest window-box-test-mode-line-stays ()
  "A window with a mode line keeps it; one without gets the edge back.
A batch session is a terminal, where a shown mode line closes the box
whatever `window-box-enclose-mode-line\=' says — there is no row
between it and the text for an edge — so the box puts its ends on the
row and the row keeps what it showed between them."
  (window-box-test--with-buffer
    (setq-local mode-line-format "mine")
    (let ((window-box-enclose-top nil) (window-box-enclose-mode-line nil))
      (window-box--apply (selected-window))
      (should (equal (window-parameter (selected-window) 'mode-line-format)
                     window-box--mode-row-format))
      (should (equal (window-box--content (selected-window)
                                         'mode-line-format)
                     "mine"))
      (window-box--clear (selected-window))
      (should (equal mode-line-format "mine"))
      (should-not (window-parameter (selected-window) 'mode-line-format)))
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
box draws a row of its own — above the header where the window shows
one, and in the header row itself where it shows none, which is the
row closest to the text the window leaves free."
  (window-box-test--with-buffer
    (setq-local header-line-format " mine ")
    (window-box--apply (selected-window))
    (should (equal (window-parameter (selected-window) 'tab-line-format)
                   '(:eval (window-box--top))))
    (window-box--clear (selected-window))
    (setq-local header-line-format nil)
    (window-box--apply (selected-window))
    (should (equal (window-parameter (selected-window) 'header-line-format)
                   '(:eval (window-box--top))))))

(ert-deftest window-box-test-the-box-puts-itself-back ()
  "A window dressed again over the box gets the box back.
Displaying a buffer in a side window sets that window's parameters
anew, and the box's top edge went with them."
  (window-box-test--with-buffer
    (window-box-mode 1)
    (set-window-parameter (selected-window) 'header-line-format 'none)
    (set-window-margins (selected-window) nil nil)
    (window-box--refresh)
    (should (equal (window-parameter (selected-window) 'header-line-format)
                   window-box--top-format))
    (should (equal (window-margins (selected-window)) '(1 . 1)))
    (window-box-mode -1)))

(ert-deftest window-box-test-a-tab-line-of-your-own-stays ()
  "A window that shows tabs keeps them, whatever the box does with the row.
Left outside the box the row is not touched at all; taken
in, the box puts its ends on it and the tabs show between them."
  (window-box-test--with-buffer
    (setq-local tab-line-format " tabs ")
    (let ((window-box-enclose-top nil) (window-box-enclose-mode-line nil))
      (window-box--apply (selected-window))
      (should-not (window-parameter (selected-window) 'tab-line-format))
      (window-box--clear (selected-window)))
    (let ((window-box-enclose-top 'tab-line)
          (window-box-enclose-mode-line nil))
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
  "A terminal window with margins of its own keeps them, without sides.
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
          (should-not window-box--prefix-overlay)
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
          (should (overlayp window-box--prefix-overlay))
          (set-window-margins (selected-window) 1 30)
          (window-box--refresh)
          (should (equal (window-margins (selected-window)) '(1 . 30)))
          (should-not window-box--prefix-overlay))
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
            (should (overlayp window-box--prefix-overlay))
            ;; one of the two is no longer a window to box
            (let ((window-box-window-predicate
                   (lambda (window) (not (eq window other)))))
              (window-box--refresh)
              (should-not (window-parameter other 'window-box))
              (should (window-parameter (selected-window) 'window-box))
              (should (overlayp window-box--prefix-overlay)))
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
          (should (overlayp window-box--prefix-overlay))
          ;; the buffer asks for two columns of its own
          (setq left-margin-width 2)
          (window-box--refresh)
          (should-not window-box--prefix-overlay)
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
          (should (overlayp window-box--prefix-overlay))
          (emacs-lisp-mode)
          ;; the mode survives the change
          (should window-box-mode)
          (should (window-parameter (selected-window) 'window-box))
          ;; the overlay that carries the sides lives in the buffer,
          ;; and its variable is permanent-local, so nothing is lost
          (should (overlayp window-box--prefix-overlay)))
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
            ;; the box's own width rides along with the save
            (should (equal (window-parameter other 'window-box--saved-margins)
                           (list left-margin-width right-margin-width
                                 (window-box--width))))
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

(ert-deftest window-box-test-a-hidden-row-stays-hidden ()
  "A window that had hidden a row has it hidden again after the box.
The top edge goes in a row parameter, so it has to hand back what it
found there, the same as the bottom edge does with the mode line.  A
hidden row the box does not need is not touched at all: the box takes
the row closest to the text, and a tab line hidden above it stays as
it was."
  (window-box-test--with-buffer
    (set-window-parameter (selected-window) 'tab-line-format 'none)
    (set-window-parameter (selected-window) 'header-line-format 'none)
    (window-box--apply (selected-window))
    (should (equal (window-parameter (selected-window) 'header-line-format)
                   window-box--top-format))
    (should (eq (window-parameter (selected-window) 'tab-line-format) 'none))
    (window-box--clear (selected-window))
    (should (eq (window-parameter (selected-window) 'header-line-format)
                'none))
    (should (eq (window-parameter (selected-window) 'tab-line-format) 'none))
    (set-window-parameter (selected-window) 'tab-line-format nil)
    (set-window-parameter (selected-window) 'header-line-format nil)))

(ert-deftest window-box-test-encloses-moves-the-edges ()
  "The enclose options say which rows are inside the box.
A batch session is a terminal, where an edge needs a row of its own:
the free tab line row above the text, and none at all below the mode
line.  So a terminal draws the top edge where the tab line row is
free and leaves the closing to the row that ends the box."
  (window-box-test--with-buffer
    (setq-local header-line-format " header "
                mode-line-format " mode ")
    (let ((window (selected-window)))
      ;; the text alone: neither row is inside, and a terminal has no
      ;; row to draw an edge in between them and the text — so the
      ;; rows it shows carry the corners instead, and the box closes
      (let ((window-box-enclose-top nil) (window-box-enclose-mode-line nil))
        (should-not (window-box--top-edge window))
        (should-not (window-box--bottom-edge window))
        (should (equal (window-box--dressed-rows window)
                       '(header-line-format mode-line-format)))
        (should (equal (window-box--corners window 'header-line-format)
                       '(0 1)))
        (should (equal (window-box--corners window 'mode-line-format)
                       '(2 3))))
      ;; both rows inside: the top edge goes in the free tab line row,
      ;; and the mode line closes the box at the bottom
      (let ((window-box-enclose-top 'header-line)
            (window-box-enclose-mode-line t))
        (should (equal (window-box--top-edge window)
                       '(own . tab-line-format)))
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
      (let ((window-box-enclose-top 'tab-line)
            (window-box-enclose-mode-line t))
        (should-not (window-box--top-edge window))
        (should (equal (window-box--corners window 'tab-line-format)
                       '(0 1)))))))

(ert-deftest window-box-test-a-row-the-box-names-appears ()
  "A row `window-box-enclose-top\=' names appears where the window has none.
The box writes its own edge row into it — the row closest to the text
that the window leaves free, below every row the box leaves outside
and above every row it takes in — so the box closes itself with its
own glyphs instead of an underline it cannot bend."
  (window-box-test--with-buffer
    (setq-local tab-line-format " tabs ")
    (let ((window (selected-window))
          (window-box-enclose-top 'header-line)
          (window-box-enclose-mode-line nil))
      ;; The tabs stay outside, above; the box takes the header row.
      (should (equal (window-box--free-slot window) 'header-line-format))
      (should (equal (window-box--top-edge window)
                     '(own . header-line-format)))
      (window-box--apply window)
      (should (equal (window-parameter window 'header-line-format)
                     window-box--top-format))
      ;; and the row is given back when the box goes
      (window-box--clear window)
      (should-not (window-parameter window 'header-line-format)))
    (set-window-parameter (selected-window) 'tab-line-format nil)))

(ert-deftest window-box-test-a-free-row-must-lie-between ()
  "The box takes a free row below what it leaves out, above what it takes in.
A row above one the box leaves outside would draw that row inside the
box; a row below one the box takes in would draw that row outside."
  (window-box-test--with-buffer
    (let ((window (selected-window)))
      ;; nothing shown: the innermost row, closest to the text
      (let ((window-box-enclose-top 'tab-line))
        (should (eq (window-box--free-slot window) 'header-line-format)))
      ;; a header inside: only the row above it is free
      (setq-local header-line-format " header ")
      (let ((window-box-enclose-top 'header-line))
        (should (eq (window-box--free-slot window) 'tab-line-format)))
      ;; a header outside: no row below it, so none is free
      (let ((window-box-enclose-top nil))
        (should-not (window-box--free-slot window)))
      ;; tabs shown and left outside: the header row is free below them
      (setq-local header-line-format nil
                  tab-line-format " tabs ")
      (let ((window-box-enclose-top 'header-line))
        (should (eq (window-box--free-slot window) 'header-line-format)))
      ;; tabs shown and taken in: nothing above them is free
      (let ((window-box-enclose-top 'tab-line))
        (should-not (window-box--free-slot window)))
      (setq-local tab-line-format nil))))

(ert-deftest window-box-test-the-drawing-never-asks-a-row-its-height ()
  "The drawing of a row must not ask that row how tall it is.
Emacs works a row\='s height out by laying the row out, and the layout
runs the `:eval\=' the box put there: asking is a recursion Emacs does
not come back from — it died of a stack overflow with a tab line
inside the box on a graphic display.  The box draws with what it knows
instead: a bar of one pixel fills a row of any height, and an arc goes
only in a row the box sizes itself."
  (window-box-test--with-buffer
    (setq-local tab-line-format " tabs "
                mode-line-format " mode "
                window-box-radius 8)
    (cl-letf (((symbol-function 'window-tab-line-height)
               (lambda (&rest _) (error "the drawing asked the tab line")))
              ((symbol-function 'window-header-line-height)
               (lambda (&rest _) (error "the drawing asked the header")))
              ((symbol-function 'window-mode-line-height)
               (lambda (&rest _) (error "the drawing asked the mode line"))))
      (dolist (parameter '(tab-line-format header-line-format
                                           mode-line-format))
        (should (window-box--row parameter)))
      (should (window-box--top))
      (should (window-box--bottom)))))

(ert-deftest window-box-test-a-row-keeps-what-it-showed ()
  "A row the box draws its ends on shows the window\='s own row between them."
  (window-box-test--with-buffer
    (setq-local header-line-format " header ")
    (let ((window-box-enclose-top 'header-line)
          (window-box-enclose-mode-line nil)
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
    (let ((window-box-enclose-top 'header-line)
          (window-box-enclose-mode-line nil)
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

(ert-deftest window-box-test-the-remaps-go-back-with-the-mode ()
  "Turning the mode off gives back every remap it made.
A remap that stays behind is invisible: the box filters its specs on
a window parameter that the mode takes off, so the colour goes and
the entry remains.  The next round adds another one on top."
  (window-box-test--with-buffer
    (let ((before (length face-remapping-alist)))
      (dotimes (_ 5)
        (window-box-mode 1)
        (window-box-mode -1))
      (should (= (length face-remapping-alist) before))
      (should-not window-box--cookies))))

(ert-deftest window-box-test-a-theme-change-renews-the-color ()
  "The box takes the color of the theme that is on now.
The horizontal edges live in face remaps, and a remap is made when a
window is dressed.  A theme change dresses no window, so the box
would keep the color of the old theme until something else did.  The
sides read the `window-box\=' face where they are drawn, so they follow
a theme by themselves."
  (window-box-test--with-buffer
    (window-box-mode 1)
    (should (member #'window-box--refresh-frames enable-theme-functions))
    (window-box-mode -1))
  ;; each frame, since a theme change reaches them all
  (let (seen)
    (cl-letf (((symbol-function 'frame-list) (lambda () '(one two)))
              ((symbol-function 'window-box--refresh)
               (lambda (&optional frame) (push frame seen))))
      (window-box--refresh-frames 'a-theme)
      (should (memq 'one seen))
      (should (memq 'two seen)))))

(ert-deftest window-box-test-a-row-inside-keeps-its-look ()
  "A row inside the box looks the same wherever the edge is.
The underline and the border a theme draws sit where the box draws,
and the box hides them.  It used to hide them only while the row
carried the edge: a tab line that took the edge over gave the theme
its underline back, under a header inside the box."
  (window-box-test--with-buffer
    (setq-local header-line-format " header ")
    (let ((window (selected-window)))
      (window-box--apply window)
      (let ((spec (nth 2 (assq 'header-line window-box--cookies))))
        (should spec)
        (should (equal (plist-get spec :underline) nil))
        (should (equal (plist-get spec :box) nil)))
      ;; tabs, which take the edge of the box over
      (setq-local tab-line-format " tabs ")
      (window-box--apply window)
      (let ((spec (nth 2 (assq 'header-line window-box--cookies))))
        (should spec)
        (should (equal (plist-get spec :underline) nil))
        (should (equal (plist-get spec :box) nil)))
      ;; A graphic display leaves such a row alone; a terminal has to
      ;; close the box on it, so it is dressed and gives up the lines
      ;; a theme drew, the same as any row inside the box.
      (let ((window-box-enclose-top nil) (window-box-enclose-mode-line nil))
        (window-box--apply window)
        (should (memq 'header-line-format
                      (window-box--dressed-rows window)))
        (should (assq 'header-line window-box--cookies)))
      (window-box--clear window))))

(ert-deftest window-box-test-the-box-has-the-last-word-on-a-row ()
  "A rule that writes the row parameter does not undress the box.
A display rule can write the same window parameters, and whoever runs
last wins.  The box listens for the state change that the redisplay
runs, after everything in the cycle has had its say."
  (window-box-test--with-buffer
    (setq-local header-line-format " header ")
    (let ((window-box-enclose-top 'header-line)
          (window-box-enclose-mode-line nil)
          (window (selected-window)))
      (window-box-mode 1)
      (should (member #'window-box--refresh window-state-change-functions))
      (should (equal (window-parameter window 'header-line-format)
                     window-box--header-row-format))
      ;; a display rule sets its own header, as `auto-side-windows' does
      (set-window-parameter window 'header-line-format " from a rule ")
      (window-box--refresh)
      (should (equal (window-parameter window 'header-line-format)
                     window-box--header-row-format))
      (should (equal (window-box--content window 'header-line-format)
                     " from a rule "))
      (window-box-mode -1)
      (should (equal (window-parameter window 'header-line-format)
                     " from a rule "))
      (set-window-parameter window 'header-line-format nil))))

(ert-deftest window-box-test-the-sides-take-a-margin-and-the-padding ()
  "The box takes one column for a side and `window-box-padding\=' more.
The side goes in the outermost column, so the box ends where the
window does, and the padding is the columns between it and the text."
  (window-box-test--with-buffer
    (let ((window-box-padding 0))
      (should (= (window-box--width) 1))
      (window-box-mode 1)
      (should (equal (window-margins (selected-window)) '(1 . 1)))
      (window-box-mode -1))
    (let ((window-box-padding 3))
      (should (= (window-box--width) 4))
      (window-box-mode 1)
      (should (equal (window-margins (selected-window)) '(4 . 4)))
      ;; the side first on the left and last on the right
      (let ((prefix (window-box--prefix)))
        (should (string-match-p "\\`│   "
                                (cadr (get-text-property 0 'display prefix))))
        (should (string-match-p "   │\\'"
                                (cadr (get-text-property 1 'display prefix)))))
      (window-box-mode -1))))

(ert-deftest window-box-test-the-row-end-reaches-past-margin-and-fringe ()
  "A dressed row\='s stretch counts the fringe as well as the margin.
`right\=' in a row\='s display spec is the right edge of the text area,
and both the margin and the fringe lie between it and the row\='s end.
A stretch that counts only the margin parks the box\='s end a fringe
short of the side below it — the header\='s right edge sat seven pixels
left of the side.  The reach is less the end\='s own pixel: a glyph
aligned to the row\='s very last pixel boundary would start outside the
row and be clipped away."
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
            ((symbol-function 'window-margins) (lambda (&rest _) '(1 . 1)))
            ((symbol-function 'window-fringes) (lambda (&rest _) '(8 8 nil t)))
            ((symbol-function 'frame-char-width) (lambda (&rest _) 10))
            ((symbol-function 'window-box--content) (lambda (&rest _) ""))
            ((symbol-function 'window-box--fitted) (lambda (content) content)))
    (let* ((row (window-box--row 'header-line-format))
           (stretch (nth 2 row))
           (spec (get-text-property 0 'display stretch)))
      ;; 10 of margin + 8 of fringe - 1 of the end itself.
      (should (equal spec '(space :align-to (+ right (17))))))))

(ert-deftest window-box-test-a-list-shaped-stretch-is-moved-in-too ()
  "A display property that is a LIST of specs is indented like a bare one.
A mode line that aligns its own tail to `right\=' with
\((space :align-to (- right ...))) fills the row to its very end when
the spec slips through unmoved, and the box\='s end lands past the row,
where it is clipped — in a terminal, into the separator column."
  (let* ((drawn (concat (propertize " " 'display
                                    '((space :align-to
                                             (- right (- 0 right-margin) 13))))
                        "tail"))
         (row (cl-letf (((symbol-function 'format-mode-line)
                         (lambda (&rest _) drawn)))
                (window-box--fitted "irrelevant")))
         (pos (text-property-not-all 0 (length row) 'display nil row))
         (spec (get-text-property pos 'display row)))
    (should (equal spec
                   (if (display-graphic-p)
                       '((space :align-to (- (- right (1)) (- 0 right-margin) 13)))
                     '((space :align-to (- (- right 2) (- 0 right-margin) 13))))))))

(ert-deftest window-box-test-a-row-too-wide-is-cut-for-the-end ()
  "A drawn row wider than its window is cut, so the end survives.
The default mode line fills the window, and a row that reaches the
edge pushes the stretch and the end of the box past it, where they
are clipped away — the box had a one row hole at its right edge.
Stock redisplay clips such a row at the window\='s edge, so the cut
loses nothing that was shown."
  (should (equal (window-box--trimmed (make-string 50 ?x) 40)
                 (make-string 40 ?x)))
  (should (equal (window-box--trimmed "short" 40) "short"))
  (let ((content '("not" "a" "string")))
    (should (eq (window-box--trimmed content 40) content))))

(ert-deftest window-box-test-an-arc-is-a-quarter-circle-and-a-column ()
  "An arc image bends one corner and carries the side through the row.
Radius three, a row five pixels tall: the top right corner starts on
the top edge, bends to the outermost column, and that column runs on
to the row\='s bottom, where the fringe bitmap takes over.  The other
corners are its mirror images."
  (let ((window-box-radius 3))
    (should (equal (plist-get (cdr (window-box--arc-image 1 5)) :data)
                   "P1\n3 5\n110001001001001"))
    (should (equal (plist-get (cdr (window-box--arc-image 0 5)) :data)
                   "P1\n3 5\n011100100100100"))
    (should (equal (plist-get (cdr (window-box--arc-image 3 5)) :data)
                   "P1\n3 5\n001001001001110"))
    (should (equal (plist-get (cdr (window-box--arc-image 2 5)) :data)
                   "P1\n3 5\n100100100100011"))))

(ert-deftest window-box-test-a-radius-rounds-the-default-characters ()
  "A radius above zero draws the default terminal corners rounded.
An explicit `window-box-characters\=' is the user\='s and stays as it
is, radius or none."
  (let ((window-box-radius 4))
    (should (equal (window-box--characters) "╭╮╰╯│─"))
    (let ((window-box-characters "++++|-"))
      (should (equal (window-box--characters) "++++|-"))))
  (let ((window-box-radius 0))
    (should (equal (window-box--characters) "┌┐└┘│─"))))

(ert-deftest window-box-test-only-edge-rows-get-the-corners ()
  "On a graphic display the corners go where the row carries the edge.
A row whose overline is the box\='s top edge gets the top corners, the
mode line whose underline is the bottom edge the bottom ones, and any
other row is passed through by the sides."
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
            ((symbol-function 'window-box--top-edge)
             (lambda (&rest _) '(overline . header-line-format)))
            ((symbol-function 'window-box--bottom-edge)
             (lambda (&rest _) '(underline . mode-line-format))))
    (should (equal (window-box--corners nil 'header-line-format) '(0 1)))
    (should (equal (window-box--corners nil 'mode-line-format) '(2 3)))
    (should (equal (window-box--corners nil 'tab-line-format) '(4 4)))))

(ert-deftest window-box-test-graphic-sides-ride-the-fringes ()
  "The graphic sides are periodic fringe bitmaps, one pixel each.
A bitmap repeats over every line's full height, however tall the
line; a margin image is one default line tall and dashed on taller
ones, and one taller than the line grows every line to its height."
  (let ((prefix (window-box--fringe-prefix)))
    (should (equal (get-text-property 0 'display prefix)
                   '(left-fringe window-box--left-side window-box)))
    (should (equal (get-text-property 1 'display prefix)
                   '(right-fringe window-box--right-side window-box)))))

(provide 'window-box-test)
;;; window-box-test.el ends here
