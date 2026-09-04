;;; window-box.el --- A rectangular box around a window -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Marcel Arpogaus

;; Author: Marcel Arpogaus <znepry.necbtnhf@tznvy.pbz>
;; Assisted-by: Claude:claude-fable-5
;; Version: 1.0
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
;; shows the buffer.  Nothing more: what your header line and your
;; mode line say stays yours, and `window-box-enclose-top' and
;; `window-box-enclose-mode-line' say whether they are inside the box
;; or outside it.  The inside is always one unbroken stack of rows
;; around the text.
;;
;; The sides are one pixel at the window's very edge: on a graphic
;; display a periodic bitmap at the outermost pixel of each fringe,
;; which repeats over every line's full height, and in a terminal a
;; character in the outermost column of each margin.  The horizontal
;; edges go on the rows the window has: a row of the box's own where
;; there is a free one, an overline above a row that is inside the
;; box, an underline below one that is not.  The fringes keep their
;; width, so their indicators stay legible, `window-box-padding' buys
;; air between a side and the text, and a buffer that keeps text in
;; its own margins keeps them, inside the box.
;;
;; Only window dressing is used: the buffer's `line-prefix' and one
;; buffer-spanning overlay carry the sides, and the window parameters
;; `tab-line-format', `header-line-format' and `mode-line-format' carry
;; the horizontal edges, so the buffer's own formats are not touched.
;; docs/implementation.org in the repository says why each part is
;; drawn the way it is.
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

(defface window-box--side '((t :inherit window-box))
  "Face the sides of the box are drawn in.
A fringe bitmap and a margin character are drawn in the foreground of
the face their display spec names, and the sides ride the buffer's
prefix into every window that shows it, the ones without a box too.
So the box remaps this face to the background for the buffer and to
the box's color for the windows it is drawn in.  Do not set it: remap
the `window-box' face, or set `window-box-color'.")

(defcustom window-box-color nil
  "Color of the box, or nil for the foreground of the `window-box' face.
Set it buffer-locally for a box color per buffer; turning the mode on
again applies it."
  :type '(choice (const :tag "Face foreground" nil) color)
  :local t)

(defcustom window-box-compose-prefix 64
  "How many prefixes of the buffer's own the box draws its sides over.
A line carries one `line-prefix', so a side of the box and a gutter the
buffer draws — dirvish's subtree guide, `org-indent-mode', a shell that
indents its output — are on the screen together only where the box
draws the two of them as one string.  It does that for up to this many
regions of the buffer's own, with an overlay for each.

Beyond that many the box gives those lines up instead of making an
overlay for each: the gutter is drawn and the sides are not.  Nil
composes however many there are.  Zero composes none: the sides win
and the gutter waits under the box.

The horizontal edges are drawn whatever this says: they ride the
window's rows, not the buffer's lines."
  :type '(choice (const :tag "However many there are" nil) natnum)
  :group 'window-box)

(defcustom window-box-window-predicate nil
  "Which windows of a boxed buffer get the box, or nil for all of them.
A function called with one window, whose buffer has `window-box-mode'
on; a nil answer leaves that window alone and takes an existing box
off it again.

The mode is a buffer's, and a buffer is often shown twice: a help
buffer in a side window and the same one in an ordinary window.  A
box usually belongs to the place rather than to the text, and this is
how a configuration says which places:

  (setq window-box-window-predicate
        (lambda (window) (window-parameter window \\='window-side)))"
  :type '(choice (const :tag "Every window showing the buffer" nil)
                 function))

(defcustom window-box-enclose-top 'tab-line
  "The topmost of the window's rows that is inside the box.
The rows above the text sit in a fixed order — tab line, then header
line — and the inside of the box is one unbroken stack, so the choice
is where the stack starts: `tab-line' encloses the tab line and the
header line with the text, `header-line' the header line alone — a
tab line, where the window shows one, stays outside — and nil draws
the top edge right above the text.  A row the window does not show is
skipped, and the edge lands on the topmost row it does.

A graphic display draws the edge as the overline of the topmost row
inside, or as the underline of the last row outside.  A terminal
draws with characters, and a character needs a row: the box writes
its own edge row into the row closest to the text the window leaves
free.  Where the window leaves none free — every row above the text
is shown and this option keeps them outside — a terminal has nothing
to draw the edge with, and the box is open at the top there.

Set it buffer-locally for a box of its own shape."
  :type '(choice (const :tag "Tab line and header line" tab-line)
                 (const :tag "Header line" header-line)
                 (const :tag "The text alone" nil))
  :local t)

(defcustom window-box-enclose-mode-line t
  "Whether the box encloses the mode line with the text.
The edge is the mode line's underline where the box takes it in, its
overline where it leaves it out.  A terminal has neither line, and no
row between the text and the mode line to draw one in: a mode line it
takes in carries the box's corners, and a mode line it leaves out
leaves the box open at the bottom.  A window without a mode line gets
a row of the box's own below the text, on both displays.

Set it buffer-locally for a box of its own shape."
  :type 'boolean
  :local t)

(defcustom window-box-padding 0
  "Columns of margin between the sides of the box and the text, per side.
Set it buffer-locally for a buffer that wants more air than the
others.  A graphic display takes no margin at all for a padding of
zero, so turning one down to zero applies when the mode goes on again.

A buffer that uses its margins for its own text keeps them: the box
asks for its columns beside the buffer's, so the sides sit outside
whatever the buffer draws there."
  :type 'natnum
  :local t)

;;;; The edges

;; There is no option for the look of the graphic sides.  A character
;; was tried: how tall its ink is, is the font's business, and most
;; fonts leave bare pixel rows between the lines — a dashed side.  A
;; filled margin column was tried: ten pixels against horizontal edges
;; of one — a pillar.  A margin image was tried: it is one default
;; line tall, and a taller line — a banner, a formula preview — keeps
;; bare pixels above and below it, while a taller image grows every
;; line to its height.  A periodic fringe bitmap repeats over each
;; line's full height whatever the font and however tall the line, so
;; it is the only shape drawn.

(defun window-box--color ()
  "Return the color the box is drawn in.
Never nil: a face with no foreground of its own — a terminal leaves
the default face without one — would give `:overline nil', which is
no overline at all, and an invalid `:background nil'."
  (or window-box-color
      (face-foreground 'window-box nil 'default)
      (frame-parameter nil 'foreground-color)
      "grey50"))

(defun window-box--row-width (&optional window)
  "Return the columns a row of WINDOW spans: its body and both margins.
WINDOW is the selected one by default.  Not `window-total-width',
which counts the column a terminal puts between two windows side by
side: a row one column too long loses its last corner off the end."
  (let ((margins (window-margins window)))
    (+ (window-body-width window)
       (or (car margins) 0)
       (or (cdr margins) 0))))

(defun window-box--edge (top)
  "Return the top edge of the box when TOP is non-nil, else the bottom one.
Called from the window parameter the box sets, so the window being
redisplayed is the selected one.  A graphic display draws a bar of one
pixel across the whole row, with the row's height from the display
spec alone: a face `:height' below one in a side window's mode line
sends Emacs into an endless measuring recursion.  Both background and
overline, because a row of the box's own takes the background in a
tab line but not in a mode line, where the line's own face wins.  A
terminal draws corner, fill and corner in the columns the row has."
  (if (display-graphic-p)
      (propertize " "
                  'face (let ((color (window-box--color)))
                          (list :background color :overline color))
                  ;; Larger than any row is long: the fill stops at the
                  ;; row's end, fringes and margins included.
                  'display '(space :align-to 10000 :height (1)))
    (let ((corners (if top "┌┐" "└┘")))
      (propertize
       (concat (substring corners 0 1)
               (make-string (max 0 (- (window-box--row-width) 2)) ?─)
               (substring corners 1))
       ;; The row encloses the text, so it carries the background of
       ;; the text and not the grey of the header or mode line whose
       ;; row it borrows.  `:inherit' first, or `default' takes the
       ;; foreground as well and the edge is drawn in the text color.
       'face (list :inherit 'default :foreground (window-box--color))))))

(defun window-box--cap (glyph)
  "Return the box's end for one side of a row it draws its ends on.
GLYPH is the character a terminal draws: the vertical edge where the
box goes on past this row, a corner where the row is the one that
closes it.  A graphic display draws a bar of one pixel, which fills a
row of any height and lands on the outermost pixel of the window, where
the fringe below it draws the side."
  (if (display-graphic-p)
      (propertize " " 'face (list :background (window-box--color))
                  'display '(space :width (1)))
    (propertize (string glyph) 'face (list :foreground (window-box--color)))))

;;;; The sides

(defun window-box--width (window)
  "Return the margin the box needs on each side of WINDOW, in columns.
A terminal draws the side itself in the outermost column and the
padding inside it; a graphic display draws the sides in the fringes,
so its margins carry `window-box-padding' alone — and none at all
where that is zero.  The frame of WINDOW decides, not the selected
one: a daemon serves a graphic frame and a terminal frame at once."
  (let ((padding (if (natnump window-box-padding) window-box-padding 0)))
    (if (display-graphic-p (window-frame window)) padding (1+ padding))))

(defun window-box--side-bitmap (side width)
  "Return the bitmap that draws SIDE in a fringe WIDTH pixels wide.
SIDE is `left' or `right'.  The bitmap is as wide as the fringe, with
its outermost pixel set: a fringe draws a bitmap from its inner edge
outwards and clips what does not fit, so a wider bitmap loses the very
pixel the box wants — the right side went missing in every window
whose right fringe was narrower, and `dirvish-side' gives its window
one pixel.  One bitmap per side and width, defined on first use."
  (let* ((width (max width 1))
         (name (intern (format "window-box--%s-side-%d" side width))))
    ;; A build without a window system has no fringes, and no function
    ;; to define one with.
    (unless (or (get name 'window-box--bitmap)
                (not (fboundp 'define-fringe-bitmap)))
      (define-fringe-bitmap name
        (vector (if (eq side 'left) (ash 1 (1- width)) 1))
        1 width '(center t))
      (put name 'window-box--bitmap t))
    name))

(defun window-box--prefix (window right)
  "Return the line prefix that draws the sides of the box in WINDOW.
On a graphic display a one pixel periodic bitmap at the outermost pixel
of each fringe, which repeats over the whole height of every line; the
fringes keep their width, so a line whose fringe shows an indicator of
its own shows that instead of the side.  In a terminal a character in
the outermost column of each margin.  RIGHT is the whole right margin
in columns: a margin display string is laid out from the *inner* edge
of the right margin, so the string is as wide as the margin — with
magit's thirty column author and date margin the side sat thirty
columns inside the window's edge.

The prefix belongs to the buffer and serves every window that shows
it, so a buffer shown in two windows whose fringes or margins differ
wears the sides of the one drawn last."
  (if (display-graphic-p (window-frame window))
      (pcase-let ((`(,left ,right . ,_) (window-fringes window)))
        (concat
         (propertize " " 'display
                     `(left-fringe ,(window-box--side-bitmap 'left left)
                                   window-box--side))
         (propertize " " 'display
                     `(right-fringe ,(window-box--side-bitmap 'right right)
                                    window-box--side))))
    (let ((side (propertize "│" 'face 'window-box--side))
          (padding (make-string (1- (window-box--width window)) ?\s)))
      (concat
       (propertize " " 'display `((margin left-margin)
                                  ,(concat side padding)))
       (propertize " " 'display `((margin right-margin)
                                  ,(concat (make-string (max 0 (1- right)) ?\s)
                                           side)))))))

;;;; The rows a window shows

(defconst window-box--rows
  '((tab-line-format window-box--saved-tab-line
                     (:eval (window-box--edge t))
                     (:eval (window-box--row 'tab-line-format)))
    (header-line-format window-box--saved-header-line
                        (:eval (window-box--edge t))
                        (:eval (window-box--row 'header-line-format)))
    (mode-line-format window-box--saved-mode-line
                      (:eval (window-box--edge nil))
                      (:eval (window-box--row 'mode-line-format))))
  "The three rows a window shows besides its text, top to bottom.
Each entry names the window parameter, the parameter the box keeps the
row's own value in, the format of an edge row of the box's own, and
the format that puts the box's ends on the window's row.")

(defun window-box--saved (parameter)
  "Return the parameter the value of the row PARAMETER is kept in."
  (nth 1 (assq parameter window-box--rows)))

(defun window-box--own (parameter)
  "Return the format of the box's own edge row in PARAMETER."
  (nth 2 (assq parameter window-box--rows)))

(defun window-box--dressed (parameter)
  "Return the format that puts the box's ends on the row PARAMETER."
  (nth 3 (assq parameter window-box--rows)))

(defun window-box--content (window parameter)
  "Return what WINDOW shows in the row PARAMETER names, box aside.
The window parameter wins over the buffer's variable, as it does in
redisplay.  A value of the box's own is not the window's, so the one
the box put away answers in its place.  The answer can be `none',
which is how a window says it hides the row."
  (let ((param (window-parameter window parameter)))
    (if (or (null param) (member param (cddr (assq parameter window-box--rows))))
        (or (window-parameter window (window-box--saved parameter))
            (buffer-local-value parameter (window-buffer window)))
      param)))

(defun window-box--shown-p (window parameter)
  "Return non-nil when WINDOW shows the row PARAMETER names, box aside."
  (let ((content (window-box--content window parameter)))
    (and content (not (eq content 'none)))))

(defun window-box--inside-p (parameter)
  "Return non-nil when the box encloses the row PARAMETER.
`window-box-enclose-top' rules the rows above the text and
`window-box-enclose-mode-line' the one below; enclosing the tab line
encloses the header line with it, so the inside is one unbroken
stack."
  (pcase parameter
    ('tab-line-format (eq window-box-enclose-top 'tab-line))
    ('header-line-format (memq window-box-enclose-top '(tab-line header-line)))
    ('mode-line-format (and window-box-enclose-mode-line t))))

(defun window-box--free-slot (window)
  "Return the row above WINDOW's text the box may take for an edge of its own.
A row the window does not show, below every row the box leaves
outside — an edge above such a row would draw that row inside — and
above every row it takes in, so the inside stays whole.  The header
row first, as the one closer to the text.

This is how a row named by `window-box-enclose-top' appears when the
window has none: the box writes its own edge into that row, on both
displays, rather than leaving the box to close itself elsewhere."
  (let ((tabs (window-box--shown-p window 'tab-line-format))
        (header (window-box--shown-p window 'header-line-format)))
    (cond ((and (not header)
                (not (and tabs (window-box--inside-p 'tab-line-format))))
           'header-line-format)
          ((and (not tabs)
                (or (not header) (window-box--inside-p 'header-line-format)))
           'tab-line-format))))

(defun window-box--top-edge (window)
  "Return where the top edge of the box goes in WINDOW.
One of (overline . PARAMETER) for the overline of a row inside the
box, (own . PARAMETER) for a row of the box's own in a row the window
leaves free, (underline . PARAMETER) for the underline of the last row
outside the box, or nil where the display has nowhere to draw it —
then the row below closes the box with corners.

The overline of the topmost row inside marks the boundary as well as
the underline of the row above it, and it is a row the box dresses,
so its ends carry the corners.  A terminal has neither line and needs
a row of its own; the underline is the last resort of a graphic
display, for a window whose rows above the text are all outside the
box and leave no row free."
  (let* ((graphic (display-graphic-p (window-frame window)))
         (shown (seq-filter (lambda (parameter)
                              (window-box--shown-p window parameter))
                            '(tab-line-format header-line-format)))
         (inside (seq-filter #'window-box--inside-p shown))
         (slot (window-box--free-slot window)))
    (cond ((and inside graphic) (cons 'overline (car inside)))
          (slot (cons 'own slot))
          ((and shown graphic) (cons 'underline (car (last shown)))))))

(defun window-box--bottom-edge (window)
  "Return where the bottom edge of the box goes in WINDOW.
The same shapes as `window-box--top-edge', for the one row below the
text: a row of the box's own where the window shows no mode line, the
mode line's underline where the box takes it in, its overline where
the box leaves it out, and nil in a terminal, which has neither line
and no row below the mode line — there the mode line carries the
corners."
  (cond ((not (window-box--shown-p window 'mode-line-format))
         '(own . mode-line-format))
        ((not (display-graphic-p (window-frame window))) nil)
        ((window-box--inside-p 'mode-line-format)
         '(underline . mode-line-format))
        (t '(overline . mode-line-format))))

(defun window-box--dressed-rows (window)
  "Return the rows of WINDOW the box draws its ends on, top to bottom.
The rows the enclose options take in and the window shows, on both
displays alike."
  (seq-filter (lambda (parameter)
                (and (window-box--inside-p parameter)
                     (window-box--shown-p window parameter)))
              (mapcar #'car window-box--rows)))

(defun window-box--corners (window parameter)
  "Return the two glyphs for the ends of the row PARAMETER in WINDOW.
A string of two characters: corners where the row is the one that
closes the box on that side, vertical edges where the box goes on past
it.

A graphic display draws the box's edge on the row that carries it, so
that row's ends are its corners.  A terminal has neither an overline
nor an underline: there the row that closes the box is the first row
the box takes in, where no row above it is free for an edge of the
box's own, and the mode line it takes in, where there is no row below
it."
  (let ((top (window-box--top-edge window))
        (bottom (window-box--bottom-edge window)))
    (if (display-graphic-p (window-frame window))
        (cond ((equal top (cons 'overline parameter)) "┌┐")
              ((equal bottom (cons 'underline parameter)) "└┘")
              (t "││"))
      (cond ((and (eq parameter (car (window-box--dressed-rows window)))
                  (not (eq parameter 'mode-line-format))
                  (not top))
             "┌┐")
            ((and (eq parameter 'mode-line-format) (not bottom)) "└┘")
            (t "││")))))

;;;; A row with the box's ends on it

(defun window-box--indented (spec)
  "Return SPEC with each `right' in it moved to the row's right end.
A window parameter is the whole row, and the box takes the last
column of it, or the last pixel.  What the content of the row aligns
to `right' must stop short of that, or it fills the place of the end
and the box has a hole in that row.

On a graphic display the row reaches past the text area to the
window's edge, the margins and the fringe with it, while `right'
names the text area's edge.  A tail that hugs `right' in a window
without a margin would sit a margin short of the box's end in one
with it — magit's log keeps thirty columns of a margin, and the
buttons of a panel header hung thirty columns off the side — so
`right' moves out by the margin and in by the pixel of the end.  A
terminal moves it in by two: a window left of another spends its last
column on the separator, and a tail that compensates for the margin
otherwise ends exactly on the cap's column."
  (cond ((eq spec 'right)
         (if (display-graphic-p)
             `(+ right
                 (,(* (or (cdr (window-margins)) 0) (frame-char-width)))
                 (- (1)))
           '(- right 2)))
        ((consp spec) (mapcar #'window-box--indented spec))
        (t spec)))

(defun window-box--fitted (content)
  "Return CONTENT drawn, with room for the end of the box after it.
A header line with a button at its right hand end aligns that button
to `right', which is where the box puts its own end.  The content is
therefore drawn here, and the alignments it carries are moved to the
row's right end.  The drawing keeps the text properties, so a button
still has its keymap and its face."
  (let ((row (format-mode-line content))
        (pos 0))
    ;; A session without a display draws nothing, and there is nothing
    ;; to fit: the content goes back as it came.
    (setq row (and row (not (string-empty-p row)) (copy-sequence row)))
    (while (and row
                (setq pos (text-property-not-all pos (length row)
                                                 'display nil row)))
      (let ((spec (get-text-property pos 'display row))
            (end (next-single-property-change pos 'display row (length row))))
        ;; A display property is one spec or a list of them, and one
        ;; that slips through unmoved fills the row to its very end
        ;; and pushes the box's end off it.
        (when (or (eq (car-safe spec) 'space)
                  (and (consp spec) (consp (car-safe spec))))
          (put-text-property pos end 'display (window-box--indented spec) row))
        (setq pos end)))
    (or row content)))

(defun window-box--trimmed (row limit)
  "Return ROW cut to LIMIT columns, where it is a drawn string.
A row wider than its window pushes everything after it off the edge,
the end of the box with it — the default mode line does it in any
window narrower than its text.  Stock redisplay clips such a row at
the window's edge, so the cut loses nothing that was shown.

The measure is `string-width', which counts a stretch glyph as one
column: a row whose content carries an absolute stretch of its own is
reported short, is not cut, and redisplay clips the end of the box
off the edge."
  (if (and (stringp row) (> (string-width row) limit))
      (truncate-string-to-width row limit)
    row))

(defun window-box--row (parameter)
  "Return the row PARAMETER names with the box's ends on it.
Called from the window parameter the box sets, so the window being
redisplayed is the selected one and its buffer is current.  The
content may fill the row up to the divider less the two ends: one
column covers them both on a graphic display, where they are a pixel
each, and exactly on a terminal, where they are a column each."
  (let* ((window (selected-window))
         (graphic (display-graphic-p))
         (corners (window-box--corners window parameter))
         (limit (if graphic
                    (1- (/ (- (window-pixel-width window)
                              (window-right-divider-width window))
                           (frame-char-width)))
                  (- (window-box--row-width window) 2))))
    (list (window-box--cap (aref corners 0))
          (window-box--trimmed
           (window-box--fitted (window-box--content window parameter))
           limit)
          ;; The stretch reaches the last column, or the last pixel,
          ;; and the end goes after it — where the side edge of the
          ;; text below it runs.
          (propertize " " 'display
                      (if graphic
                          ;; `right' is the right edge of the text
                          ;; area; the row spans the margin and the
                          ;; fringe outside it, less the end's own
                          ;; pixel: a glyph aligned to the row's very
                          ;; end would start outside it and be clipped.
                          `(space :align-to
                                  (+ right
                                     (,(+ (* (or (cdr (window-margins)) 0)
                                             (frame-char-width))
                                          (cadr (window-fringes))
                                          -1))))
                        ;; A terminal spends a column of a window left
                        ;; of another on the separator, and `right'
                        ;; does not count it: a stretch to `right'
                        ;; swallows the end.  The column is counted
                        ;; from the text area outwards instead.
                        `(space :align-to
                                ,(- (window-box--row-width)
                                    (or (car (window-margins)) 0)
                                    1))))
          (window-box--cap (aref corners 1)))))

;;;; Face remaps

(defvar-local window-box--remaps nil
  "The face remaps this buffer holds, as (WANTED . COOKIES).
WANTED is the alist of face and spec they were made from.  A remap is
the buffer's and would reach every window showing it, so the specs of
the box are filtered on the window parameter the box sets; the one
that hides the sides is not, and the filtered ones are added after it
and win where they apply.")

(defun window-box--remap (wanted)
  "Hold exactly the remaps WANTED, an alist of face and spec.
Nothing is done while WANTED is what the buffer holds already; a
change — the box's color, the edge moved from one row to another, a
theme with another background — remakes them all."
  (unless (equal wanted (car window-box--remaps))
    (mapc #'face-remap-remove-relative (cdr window-box--remaps))
    (setq window-box--remaps
          (and wanted
               (cons wanted
                     (mapcar (lambda (entry)
                               (face-remap-add-relative (car entry) (cdr entry)))
                             wanted))))))

(defun window-box--row-faces (parameter)
  "Return the faces that draw the row PARAMETER names.
A row has one face for the selected window and one for the others: the
mode line always had the pair, and the header line and the tab line have
it from Emacs 31 on.  A face that carries an attribute of its own —
spacious-padding gives `header-line-inactive' an underline of its own —
never reads the inherited one, so the remap has to name each face that
is drawn."
  (let ((name (replace-regexp-in-string "-format\\'" "" (symbol-name parameter))))
    (or (seq-filter #'facep
                    (list (intern (concat name "-active"))
                          (intern (concat name "-inactive"))))
        (list (intern name)))))

(defconst window-box--bare-lines '(:overline nil :underline nil :box nil)
  "The spec that takes a row's own lines and border off it.
A row inside the box gives them up wherever the edge happens to be:
both are drawn where the box draws, and a row must not change its look
when the edge moves to the row above it.  A row the box leaves outside
keeps everything but the one line it borrows — stripping its border
took the padding off a mode line dressed by `spacious-padding' and
moved the row the box was drawing against.")

(defun window-box--line-spec (edge parameter color dressed)
  "Return the spec that draws EDGE as a line of the row PARAMETER, in COLOR.
EDGE is `overline' or `underline'; the underline is asked for the bottom
position, at the row's very last pixel, so the same row can be inside
the box or outside it.  DRESSED are the rows inside the box, whose own
lines go."
  (plist-put (copy-sequence (and (memq parameter dressed) window-box--bare-lines))
             (if (eq edge 'overline) :overline :underline)
             (if (eq edge 'overline) color (list :color color :position 0))))

(defun window-box--edge-remaps (color top bottom dressed)
  "Return the remaps that draw the box's edges as lines of the rows, in COLOR.
TOP and BOTTOM are the edges the box chose and DRESSED the rows it
puts its ends on, as an alist of face and spec."
  (let (wanted)
    (pcase-dolist (`(,edge . ,parameter) (list top bottom))
      (when (memq edge '(overline underline))
        (dolist (face (window-box--row-faces parameter))
          (push (cons face (window-box--line-spec edge parameter color dressed))
                wanted))))
    (dolist (parameter dressed)
      (dolist (face (window-box--row-faces parameter))
        (unless (assq face wanted)
          (push (cons face window-box--bare-lines) wanted))))
    (nreverse wanted)))

(defun window-box--wanted-remaps (color top bottom dressed)
  "Return the remaps the box wants, in COLOR, as an alist of face and spec.
TOP and BOTTOM are the edges the box chose and DRESSED the rows it
puts its ends on.  First the remap that hides the sides in the buffer's
background everywhere, where the display names one; then, filtered to
the windows the box is drawn in, the sides in COLOR and the lines of
the rows."
  (let ((background (or (face-background 'default nil 'default)
                        (frame-parameter nil 'background-color))))
    (append
     (and background
          (list (cons 'window-box--side (list :foreground background))))
     (mapcar (lambda (entry)
               (cons (car entry) `(:filtered (:window window-box t) ,(cdr entry))))
             (cons (cons 'window-box--side (list :foreground color))
                   (window-box--edge-remaps color top bottom dressed))))))

;;;; The sides' carriers

(defvar-local window-box--prefix-overlay nil
  "The overlay that carries the sides over lines with prefixes of their own.
A line that brings a `line-prefix' as a text property — a shell that
indents its output does — beats the buffer-local variable, and its
stretch of the sides would go missing.  An overlay's prefix outranks
the line's.  The overlay cannot carry the sides alone: it ends at the
last line of text, and the rows below it show only what the variable
says — so the sides ride both.")
(put 'window-box--prefix-overlay 'permanent-local t)

(defvar-local window-box--saved-prefix nil
  "What the buffer's line and wrap prefix were before the box.
A list (LINE WRAP LOCAL), where LOCAL says the buffer had a prefix of
its own, so it goes back as a buffer-local value; without it the
variables are killed again.")

(defvar-local window-box--worn nil
  "What the sides were last hung with, as (PREFIX . REGIONS).
A refresh runs on every window state change, and hanging the same
prefix again would remake every composed overlay each time.")

(defvar-local window-box--composed nil
  "The overlays that carry a side and a prefix of the buffer's as one.")

(defvar-local window-box--compose-timer nil
  "The idle timer that will draw the sides over new gutter, if any.")

(defun window-box--own-prefixes ()
  "Return the prefix regions the buffer draws itself, as (BEG END PREFIX).
A `line-prefix' on the text, or on an overlay that is neither the box's
carrier nor one of its own composed ones.  Only a string: a side is
concatenated to it, and dirvish keeps a number in that property as
bookkeeping beside the overlay that carries the guide."
  (let (found)
    (dolist (ov (overlays-in (point-min) (point-max)))
      (let ((own (overlay-get ov 'line-prefix)))
        (when (and (stringp own)
                   (not (eq ov window-box--prefix-overlay))
                   (not (memq ov window-box--composed)))
          (push (list (overlay-start ov) (overlay-end ov) own) found))))
    (let ((pos (point-min)))
      (while (< pos (point-max))
        (let ((own (get-text-property pos 'line-prefix))
              (next (or (next-single-property-change pos 'line-prefix)
                        (point-max))))
          (when (stringp own) (push (list pos next own) found))
          (setq pos next))))
    found))

(defun window-box--uncompose ()
  "Take the box's composed overlays off the buffer, and its timer with them."
  (when (timerp window-box--compose-timer)
    (cancel-timer window-box--compose-timer))
  (setq window-box--compose-timer nil)
  (mapc #'delete-overlay window-box--composed)
  (setq window-box--composed nil
        window-box--worn nil))

(defun window-box--shed ()
  "Take the box's prefix off the current buffer, every carrier."
  (window-box--uncompose)
  (when (overlayp window-box--prefix-overlay)
    (delete-overlay window-box--prefix-overlay))
  (setq window-box--prefix-overlay nil)
  (when-let* ((saved window-box--saved-prefix))
    (if (nth 2 saved)
        (setq-local line-prefix (nth 0 saved)
                    wrap-prefix (nth 1 saved))
      (kill-local-variable 'line-prefix)
      (kill-local-variable 'wrap-prefix))
    (setq window-box--saved-prefix nil)))

(defun window-box--wear (prefix regions)
  "Hang PREFIX, the sides, on the current buffer, on both carriers.
REGIONS are the prefixes the buffer draws itself: each gets an overlay
of its own carrying the side and that region's prefix as one string,
above the box's own carrier.  Where two overlap the narrower one wins,
as Emacs resolves a tie between overlays of one priority, so a subtree
inside a subtree keeps the deeper guide.

Nothing is done where the same PREFIX and REGIONS are worn already and
the carrier is live and spans the buffer.  A live carrier is moved
rather than remade, and a dead one is remade: `delete-overlay' leaves
an overlay that is still an overlay, only detached, and a buffer that
renders itself again throws every overlay away.  What the buffer wore
before is kept once, for the mode to give back."
  (unless window-box--saved-prefix
    (setq window-box--saved-prefix
          (list line-prefix wrap-prefix (local-variable-p 'line-prefix))))
  (save-restriction
    (widen)
    (let ((live (and (overlayp window-box--prefix-overlay)
                     (overlay-buffer window-box--prefix-overlay))))
      (unless (and live
                   (= (overlay-start window-box--prefix-overlay) (point-min))
                   (= (overlay-end window-box--prefix-overlay) (point-max))
                   (equal-including-properties prefix (car window-box--worn))
                   (equal regions (cdr window-box--worn)))
        (setq-local line-prefix prefix
                    wrap-prefix prefix)
        (if live
            (move-overlay window-box--prefix-overlay (point-min) (point-max))
          (setq window-box--prefix-overlay
                ;; Rear-advance, so text added at the end wears it too.
                (make-overlay (point-min) (point-max) nil nil t)))
        ;; Above every other overlay: a shell that draws an indent
        ;; gutter puts prefixes on overlays of its own, and a tie
        ;; between overlays falls whichever way redisplay walks them.
        (overlay-put window-box--prefix-overlay 'priority 100)
        (overlay-put window-box--prefix-overlay 'line-prefix prefix)
        (overlay-put window-box--prefix-overlay 'wrap-prefix prefix)
        (window-box--uncompose)
        (pcase-dolist (`(,beg ,end ,own) regions)
          (let ((ov (make-overlay beg end))
                (both (concat prefix own)))
            (overlay-put ov 'priority 101)
            (overlay-put ov 'line-prefix both)
            (overlay-put ov 'wrap-prefix both)
            (push ov window-box--composed)))
        (setq window-box--worn (cons prefix regions))))))

(defun window-box--recompose (buffer)
  "Hang the sides of BUFFER again, over the prefixes it draws itself now.
From an idle timer, because the gutter of a buffer arrives on an
overlay and an overlay arrives without a hook: dirvish opens a subtree
by inserting its listing and then hanging the guide over it, so the
change hook runs before there is anything to compose with."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq window-box--compose-timer nil)
      (when (and window-box--saved-prefix (stringp line-prefix))
        (window-box--wear line-prefix (window-box--own-prefixes))))))

(defun window-box--watch (_beginning _end _before)
  "Put the sides back when a change has taken them away.
For `after-change-functions', buffer-locally, while the box is worn.  A
buffer that renders itself again throws every overlay away and then
writes its text — symbols-outline calls `delete-all-overlays' and
`erase-buffer' on every refresh — and none of the window hooks the box
listens to fires for a change in the text alone.  A dead carrier is
remade at once, before the redisplay; a live one is asked about new
gutter once Emacs is idle, one timer to a buffer however many changes
arrive, so a shell writing its output does not walk its overlays on
every one of them."
  (when (and window-box--saved-prefix (stringp line-prefix))
    (if (and (overlayp window-box--prefix-overlay)
             (overlay-buffer window-box--prefix-overlay))
        (unless window-box--compose-timer
          (setq window-box--compose-timer
                (run-with-idle-timer 0.1 nil #'window-box--recompose
                                     (current-buffer))))
      (window-box--wear line-prefix (window-box--own-prefixes)))))

;;;; Dressing a window

(defun window-box--dress (window parameter format)
  "Give WINDOW the row FORMAT for PARAMETER and keep what was there.
What was there is the window's own value, never one of the box's: a
box that changes its mind about a row — from an edge of its own to
the ends on the window's — must still give back what it found."
  (unless (equal (window-parameter window parameter) format)
    (unless (member (window-parameter window parameter)
                    (cddr (assq parameter window-box--rows)))
      (set-window-parameter window (window-box--saved parameter)
                            (window-parameter window parameter)))
    (set-window-parameter window parameter format)))

(defun window-box--undress (window parameter)
  "Give WINDOW back the row PARAMETER it had before the box."
  (let ((saved (window-box--saved parameter)))
    (set-window-parameter window parameter (window-parameter window saved))
    (set-window-parameter window saved nil)))

(defun window-box--apply-rows (window top bottom dressed)
  "Give WINDOW the rows the box asks of it.
An edge row of its own where the window leaves that row free, its ends
where the row is inside the box — that is DRESSED — and nothing at all
otherwise.  TOP and BOTTOM are the edges the box chose."
  (dolist (entry window-box--rows)
    (let* ((parameter (car entry))
           (format (cond ((member (cons 'own parameter) (list top bottom))
                          (window-box--own parameter))
                         ((memq parameter dressed)
                          (window-box--dressed parameter)))))
      (cond (format (window-box--dress window parameter format))
            ((member (window-parameter window parameter) (cddr entry))
             (window-box--undress window parameter))))))

(defun window-box--own-margins (window width)
  "Return the margins WINDOW would wear without the box, as (LEFT RIGHT).
Either can be nil, which is how a window says the buffer's own
`left-margin-width' and `right-margin-width' decide.  The answer is
saved the first time the box takes the margins, so the box never adds
its own WIDTH columns to columns of its own — and a window split off a
boxed one, which arrives wearing them, is recognised by them.

A WIDTH of zero takes no margins and saves none: what the window wore
then is not the box's to give back, and writing those numbers back at
the end would pin a margin the buffer has since dropped."
  (or (and (zerop width) (list (car (window-margins window))
                               (cdr (window-margins window))))
      (window-parameter window 'window-box--saved-margins)
      (let* ((margins (window-margins window))
             (buffer (window-buffer window))
             (own (list (buffer-local-value 'left-margin-width buffer)
                        (buffer-local-value 'right-margin-width buffer)))
             (mine (cons (+ (or (nth 0 own) 0) width)
                         (+ (or (nth 1 own) 0) width)))
             (theirs (if (equal margins mine)
                         '(nil nil)
                       (list (car margins) (cdr margins)))))
        (set-window-parameter window 'window-box--saved-margins theirs)
        theirs)))

(defun window-box--apply-sides (window)
  "Give WINDOW the margins and the sides of the box.
The box asks for its columns *beside* the buffer's own, never instead
of them: magit's log writes the author and the date into a thirty
column right margin, `diff-hl-margin-mode' marks every changed line in
two on the left, and the box's side sits outside all of it.  On a
graphic display the fringes go outside the margins, where the sides
belong; the widths are not touched, and the window gets its order back
when the box goes.  More gutter of the buffer's own than
`window-box-compose-prefix' allows leaves those lines to their owner:
no margins taken and no prefix hung."
  (if-let* ((regions (unless (eql window-box-compose-prefix 0)
                       (window-box--own-prefixes)))
            (cap window-box-compose-prefix)
            ((> (length regions) cap)))
      (window-box--shed)
    (let* ((width (window-box--width window))
           (own (window-box--own-margins window width))
           (left (+ (or (nth 0 own) left-margin-width 0) width))
           (right (+ (or (nth 1 own) right-margin-width 0) width)))
      (unless (or (zerop width)
                  (equal (window-margins window) (cons left right)))
        (set-window-margins window left right))
      (when (and (display-graphic-p (window-frame window))
                 (not (nth 2 (window-fringes window))))
        (set-window-parameter window 'window-box--saved-order t)
        ;; Four arguments, not five: the fifth would pin the widths
        ;; across every later `set-window-buffer'.
        (set-window-fringes window (car (window-fringes window))
                            (cadr (window-fringes window)) t))
      (window-box--wear (window-box--prefix window right) regions))))

(defun window-box--apply (window)
  "Draw the box around WINDOW.
Call it with the window's buffer current."
  (set-window-parameter window 'window-box t)
  (let ((top (window-box--top-edge window))
        (bottom (window-box--bottom-edge window))
        (dressed (window-box--dressed-rows window)))
    (window-box--apply-rows window top bottom dressed)
    (window-box--remap
     (window-box--wanted-remaps (window-box--color) top bottom dressed))
    (window-box--apply-sides window)))

(defun window-box--clear (window)
  "Remove the box from WINDOW.
The face remaps are the buffer's and go when the mode turns off."
  (set-window-parameter window 'window-box nil)
  (dolist (entry window-box--rows)
    (when (member (window-parameter window (car entry)) (cddr entry))
      (window-box--undress window (car entry))))
  (when (window-parameter window 'window-box--saved-order)
    (set-window-fringes window (car (window-fringes window))
                        (cadr (window-fringes window)) nil)
    (set-window-parameter window 'window-box--saved-order nil))
  ;; The margins the window wore without the box, nil and all: nil is
  ;; how a window leaves the width to the buffer, and a number the box
  ;; wrote over would take that away.
  (when-let* ((saved (window-parameter window 'window-box--saved-margins)))
    (set-window-margins window (nth 0 saved) (nth 1 saved))
    (set-window-parameter window 'window-box--saved-margins nil))
  (with-current-buffer (window-buffer window)
    ;; The sides hang on one overlay of the buffer's, so they serve
    ;; every boxed window at once.
    (unless (seq-some (lambda (other)
                        (and (not (eq other window))
                             (window-parameter other 'window-box)))
                      (get-buffer-window-list nil 'no-minibuffer t))
      (window-box--shed))))

;; `window-state-get' saves the margins, so what the box set travels
;; with a hidden side window.  The marks that say those settings are
;; the box's have to travel too, or a mode turned off while such a
;; window is away leaves it wearing the box's margins with no box.
;; The widths and the marks are numbers and t, which a state written
;; to a file can hold; the rows the box took over are formats, which
;; can hold a closure, so those travel within the session only.
(dolist (entry '((window-box . writable)
                 (window-box--saved-margins . writable)
                 (window-box--saved-order . writable)
                 (window-box--saved-tab-line . t)
                 (window-box--saved-header-line . t)
                 (window-box--saved-mode-line . t)))
  (unless (assq (car entry) window-persistent-parameters)
    (push entry window-persistent-parameters)))

;;;; Refresh

(defun window-box--boxed-p (window)
  "Return non-nil when WINDOW is one to draw a box around."
  (and (buffer-local-value 'window-box-mode (window-buffer window))
       (or (null window-box-window-predicate)
           (funcall window-box-window-predicate window))))

(defun window-box--refresh (&optional frame)
  "Box and unbox the windows of FRAME to match their buffers.
Showing a buffer resets the window's fringes and margins, so boxed
windows also get theirs back here; only what this package drew is
taken away."
  (dolist (window (window-list frame 'no-minibuffer))
    (if (window-box--boxed-p window)
        (with-current-buffer (window-buffer window)
          (window-box--apply window))
      (when (window-parameter window 'window-box)
        (window-box--clear window)))))

(defun window-box--refresh-frames (&rest _)
  "Draw the box again in each window of each frame.
A theme change reaches every frame at once and changes the color the
box is drawn in, which lives in face remaps made when a window is
dressed; a major mode change clears those remaps in the buffer, whose
windows may be on any frame."
  (dolist (frame (frame-list))
    (window-box--refresh frame)))

;;;; The mode

;; Before the mode, so that loading the package sets it whether or not
;; the mode has ever been on: a major mode change would otherwise clear
;; the mode along with every other local variable.
(put 'window-box-mode 'permanent-local t)

;;;###autoload
(define-minor-mode window-box-mode
  "Draw a rectangular box around every window that shows this buffer.
What your header line and your mode line show stays yours;
`window-box-enclose-top' and `window-box-enclose-mode-line' say
which of the rows around the text are inside the box.  A row that is
inside gets the ends of the box at its two sides.  See the commentary
for how the box is built."
  :lighter ""
  (if window-box-mode
      (progn
        ;; Displaying a buffer resets the window's fringes, margins and
        ;; parameters, and a package that dresses windows — side window
        ;; rules, for one — sets its own over the box's every time it
        ;; displays.  So the box puts itself back on every window
        ;; change, and only ever changes what differs, or setting the
        ;; margins here would call this back forever.  The state change
        ;; hook runs from the redisplay, after everything in the cycle
        ;; has had its say, which gives the box the last word.  The
        ;; hooks stay for the session: they walk the windows of one
        ;; frame and read a buffer-local variable.
        (add-hook 'window-buffer-change-functions #'window-box--refresh)
        (add-hook 'window-configuration-change-hook #'window-box--refresh)
        (add-hook 'window-state-change-functions #'window-box--refresh)
        ;; A major mode change clears the face remaps and the saved
        ;; prefix along with every other local variable, and neither
        ;; event above fires for it.  The mode itself survives, being
        ;; permanent-local, so the box is drawn again from scratch — on
        ;; every frame, because the overlay that carries the sides is
        ;; permanent-local as well and would show them in `shadow'
        ;; wherever the buffer is.
        (add-hook 'after-change-major-mode-hook
                  #'window-box--refresh-frames)
        ;; A theme change is not a window change, and the color of the
        ;; box comes from a face.
        (add-hook 'enable-theme-functions #'window-box--refresh-frames)
        ;; A change in the text alone fires none of the window hooks, and
        ;; a buffer that renders itself again deletes the overlay the
        ;; sides ride.  Buffer-local.
        (add-hook 'after-change-functions #'window-box--watch nil t)
        ;; The predicate has the same say here as in the refresh: the
        ;; mode is the buffer's and the box is the window's.
        (dolist (window (get-buffer-window-list nil nil t))
          (when (window-box--boxed-p window)
            (window-box--apply window))))
    (remove-hook 'after-change-functions #'window-box--watch t)
    (dolist (window (get-buffer-window-list nil nil t))
      (window-box--clear window))
    (window-box--remap nil)
    (window-box--shed)))

(provide 'window-box)
;;; window-box.el ends here
