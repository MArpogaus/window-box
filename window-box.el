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
;; Only window dressing is used:
;;
;; - The sides hang on the buffer's `line-prefix' and on one
;;   buffer-spanning overlay's.  The variable reaches the rows below
;;   the last line of text, where the overlay ends; the overlay
;;   outranks a prefix a line brings of its own, as a shell's
;;   indented output does, where the variable loses.  A display bound
;;   for a fringe or a margin stays invisible in a window without
;;   one.  The box puts the fringes outside the margins, which is
;;   where its sides belong.
;; - A row of the box's own lives in the window's tab line or mode
;;   line, set through the window parameter, so the buffer's own
;;   `tab-line-format' and `mode-line-format' are not touched — and
;;   only while the window is not using that row itself.
;; - A row the box takes in keeps what it shows and gets the box's
;;   ends around it, through the same window parameters.
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
A graphic display draws lines of one pixel instead.

A value that is not exactly six characters long is ignored and the
default drawn instead.  The box is drawn from a `:eval\' in the tab
line, so a value the drawing cannot read would turn every redisplay
of a boxed window into an error."
  :type '(string :tag "Six characters, in the order ┌ ┐ └ ┘ │ ─"))

(defcustom window-box-color nil
  "Color of the box, or nil for the foreground of the `window-box' face.
Set it buffer-locally for a box color per buffer; turning the mode on
again applies it."
  :type '(choice (const :tag "Face foreground" nil) color)
  :local t)

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
        (lambda (window) (window-parameter window \='window-side)))"
  :type '(choice (const :tag "Every window showing the buffer" nil)
                 function))

(defcustom window-box-enclose-top 'tab-line
  "The topmost of the window\='s rows that is inside the box.
The rows above the text sit in a fixed order — tab line, then header
line — and the inside of the box is one unbroken stack, so the choice
is where the stack starts: `tab-line\=' encloses the tab line and the
header line with the text, `header-line\=' the header line alone — a
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
The edge is the mode line\='s underline where the box takes it in, its
overline where it leaves it out.  A terminal has neither line, and no
row between the text and the mode line to draw one in: a mode line it
takes in carries the box\='s corners, and a mode line it leaves out
leaves the box open at the bottom.  A window without a mode line gets
a row of the box\='s own below the text, on both displays.

Set it buffer-locally for a box of its own shape."
  :type 'boolean
  :local t)

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

(defcustom window-box-padding 0
  "Columns of margin between the sides of the box and the text, per side.
Set it buffer-locally for a buffer that wants more air than the
others.

A buffer that uses its margins for its own text keeps them: the box
asks for its columns beside the buffer\='s, so the sides sit outside
whatever the buffer draws there."
  :type 'natnum
  :local t)

(defcustom window-box-radius 0
  "Radius of the box\='s corners in pixels, or zero for right angles.
A graphic display rounds the corners of the rows the box draws itself:
the edge row it writes into a row the window leaves free, above the
text or below it.  Everywhere else the ends stay square — a row the
window brought is as tall as its face and its content make it, and an
image can be placed against such a row\='s baseline but not against its
edge, so an arc there lands beside the line rather than on it.

A terminal rounds by character: any radius above zero draws the
default corners as ╭ ╮ ╰ ╯, and an explicit `window-box-characters\='
is respected as it is.

Set it buffer-locally for a buffer of its own roundness."
  :type 'natnum
  :local t)

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

(defun window-box--radius ()
  "Return the corner radius the box is drawn with."
  (if (natnump window-box-radius) window-box-radius 0))

(defun window-box--characters ()
  "Return the six characters the box is drawn with.
`window-box-characters' can be set to anything — `setq\' asks no
`:type\' — and a shorter string would signal from inside redisplay,
where an error repaints as one instead of naming the option that
caused it.  Such a value is dropped for the default."
  (let ((default (eval (car (get 'window-box-characters 'standard-value)) t))
        (chars (and (stringp window-box-characters)
                    (= (length window-box-characters) 6)
                    window-box-characters)))
    (cond ((and chars (not (equal chars default))) chars)
          ;; The radius rounds the default corners; an explicit choice
          ;; above is the user's and stays.
          ((> (window-box--radius) 0) "╭╮╰╯│─")
          (t default))))

(defun window-box--edge (left right)
  "Return one horizontal edge of the box, from corner LEFT to corner RIGHT.
The corners are indices into `window-box-characters\='.  A graphic
display draws a thin bar across the whole row — with a radius, a row
as tall as the arcs at its ends.  A terminal draws characters, and
the columns are exact."
  (if (display-graphic-p)
      (let ((radius (window-box--radius))
            (color (window-box--color)))
        (if (zerop radius)
            ;; The row's height comes from the display spec alone.  A
            ;; face `:height' below one in a side window's mode line
            ;; sends Emacs into an endless measuring recursion and it
            ;; dies of a stack overflow; the display spec has none.
            (propertize " "
                        ;; Background and overline both: a one pixel
                        ;; row of the box's own takes the background in
                        ;; a tab line but not in a mode line, where the
                        ;; line's own face wins — the overline paints
                        ;; that pixel either way.
                        'face (list :background color :overline color)
                        ;; Larger than any row is long: the fill stops
                        ;; at the row's end, fringes and margins
                        ;; included, which is where the side edges are.
                        'display '(space :align-to 10000 :height (1)))
          ;; A radius needs room to bend: the row is as tall as the
          ;; arc, the line sits on the row's outer pixel row — the
          ;; overline of a top row, the underline of a bottom one —
          ;; and an arc closes each end.
          (concat
           (window-box--cap left t)
           (propertize " "
                       'face (if (< left 2)
                                 (list :overline color)
                               (list :underline
                                     (list :color color :position 0)))
                       ;; `:ascent 100' keeps the font's descent out of
                       ;; the row: the row is the arcs' own height, and
                       ;; the arcs fill it, so the curve meets the line.
                       'display `(space :align-to
                                        (+ right
                                           (,(+ (* (or (cdr (window-margins))
                                                       0)
                                                   (frame-char-width))
                                                (cadr (window-fringes))
                                                (- radius))))
                                        :height (,radius)
                                        :ascent 100))
           (window-box--cap right t))))
    ;; The body and the margins, not `window-total-width': that counts
    ;; the column a terminal puts between two windows side by side, and
    ;; an edge one column too long loses its last corner off the end.
    (let* ((margins (window-margins))
           (width (+ (window-body-width)
                     (or (car margins) 0)
                     (or (cdr margins) 0))))
      (propertize
       (let ((characters (window-box--characters)))
         (concat (string (aref characters left))
                 (make-string (max 0 (- width 2)) (aref characters 5))
                 (string (aref characters right))))
       'face (list :foreground (window-box--color))))))

(defun window-box--top ()
  "Return the top edge of the box."
  (window-box--edge 0 1))

(defun window-box--bottom ()
  "Return the bottom edge of the box."
  (window-box--edge 2 3))

(defun window-box--side ()
  "Return the character that draws a side of the box in a terminal.
The graphic sides are fringe bitmaps; see `window-box--fringe-prefix\='."
  (propertize (string (aref (window-box--characters) 4))
              'face (list :foreground (window-box--color))))

(defun window-box--width ()
  "Return the margin the box needs on each side, in columns.
A terminal draws the side itself in the outermost column and the
padding inside it; a graphic display draws the sides in the fringes,
so its margins carry `window-box-padding\=' alone — and none at all
where that is zero."
  (let ((padding (if (natnump window-box-padding) window-box-padding 0)))
    (if (display-graphic-p) padding (1+ padding))))

(defun window-box--prefix ()
  "Return the line prefix that draws the sides in a terminal\='s margins.
The side sits in the outermost column, so the box ends where the
window does; the padding is the rest of the margin."
  (let ((padding (make-string (1- (window-box--width)) ?\s))
        (side (window-box--side)))
    (concat
     (propertize " " 'display `((margin left-margin)
                                ,(concat side padding)))
     (propertize " " 'display `((margin right-margin)
                                ,(concat padding side))))))

;; The graphic sides: a one pixel periodic bitmap at the outermost
;; pixel of each fringe, which repeats over the whole height of every
;; line — a text line, a banner drawn from images, a formula preview.
;; The fringes keep their width, so their indicators stay; a line
;; whose fringe shows an indicator of its own shows that instead of
;; the side, which is a one line gap where the indicator matters more.
;; The margins are left to their owners: the buffer's own content sits
;; inside the box, with the default order, and `window-box-padding'
;; only ever adds blank ones.
(when (fboundp 'define-fringe-bitmap)
  (define-fringe-bitmap 'window-box--left-side [#b10000000] 1 8 '(center t))
  (define-fringe-bitmap 'window-box--right-side [#b00000001] 1 8 '(center t)))

(defun window-box--fringe-prefix ()
  "Return the line prefix that draws the sides in the fringes."
  (concat
   (propertize " " 'display '(left-fringe window-box--left-side window-box))
   (propertize " " 'display '(right-fringe window-box--right-side window-box))))

(defun window-box--arc-image (corner height &optional fill)
  "Return the image of one rounded CORNER, HEIGHT pixels tall.
FILL says the row is exactly as tall as the image, so the image is
anchored to the baseline, which is then the row\='s own bottom edge.
Without it the image is centred on the text, which is where a row the
window brought wants it.
CORNER is an index as in `window-box-characters\=': 0 and 1 the top
corners, 2 and 3 the bottom ones.  The image is `window-box--radius\='
wide; the arc fills its corner quarter with a one pixel stroke, and
the side\='s column carries on through the rest of the height, down to
the row\='s edge, where the fringe bitmap takes over."
  (let* ((radius (min (window-box--radius) height))
         (r (1- radius))
         (rows (let (rows) (dotimes (_ height)
                             (push (make-string radius ?0) rows))
                    (vconcat rows)))
         (top (memq corner '(0 1)))
         (left (memq corner '(0 2)))
         (dot (lambda (x y)
                ;; The canonical arc is the top right corner; the
                ;; others are its mirror images.
                (let ((px (if left (- r x) x))
                      (py (if top y (- height 1 y))))
                  (aset (aref rows py) px ?1)))))
    ;; The quarter circle, walked along both axes so a steep stretch
    ;; leaves no gap.
    (dotimes (y radius)
      (funcall dot (round (sqrt (- (* r r) (* (- r y) (- r y))))) y))
    (dotimes (x radius)
      (funcall dot x (- r (round (sqrt (- (* r r) (* x x)))))))
    ;; The side's column, from the arc to the row's other edge — in
    ;; canonical coordinates, like the arc: the mirror is the dot's.
    (dotimes (i (- height radius))
      (funcall dot r (+ radius i)))
    `(image :type pbm
            :data ,(format "P1\n%d %d\n%s" radius height
                           (mapconcat #'identity rows))
            :foreground ,(window-box--color)
            :ascent ,(if fill 100 'center)
            :scale 1)))

(defun window-box--cap (corner &optional own)
  "Return the box\='s end for one side of a row it draws its ends on.
CORNER is an index into `window-box-characters\=', which a terminal
draws: the vertical edge where the box goes on past this row, a corner
where the row is the one that closes it.

A graphic display draws a bar of one pixel, which fills a row of any
height.  OWN says the row is a row of the box\='s own, exactly as tall
as `window-box-radius\=' — the one row whose height the box sets — and
there a corner is drawn as an arc.

A row the window brought keeps the bar, whatever the radius.  An image
is placed against its row\='s baseline rather than the row\='s edge, and
the distance between the two is not something the package can work
out: measured in one mode line, the face reported four pixels of
border where the row had eight, and an arc placed on that arithmetic
lands beside the line instead of on it.  Worse, the box\='s own glyphs
are part of what makes a row as tall as it is, so measuring the row to
decide how to draw it settles into whichever answer it started from."
  (if (display-graphic-p)
      (if (and own (< corner 4) (> (window-box--radius) 0))
          ;; The row's own edge must not cross the arc: the remap that
          ;; draws it reaches every glyph of the row, this one opts out.
          (propertize " " 'face '(:overline nil :underline nil)
                      'display (window-box--arc-image
                                corner (window-box--radius) t))
        ;; A row spans no fringes: a bar of one pixel lands on the
        ;; outermost pixel of the window, which is where the fringe
        ;; below it draws the side.
        (propertize " " 'face (list :background (window-box--color))
                    'display '(space :width (1))))
    (propertize (string (aref (window-box--characters) corner))
                'face (list :foreground (window-box--color)))))

;;;; Boxing and unboxing windows

(defvar-local window-box--cookies nil
  "Face remaps this buffer holds, as a list (FACE COOKIE SPEC).
The spec is kept so a box that wants a different one — the edge above
a row rather than below it — can tell and remake the remap.")

(defvar-local window-box--cookie-color nil
  "Color the cookies were made with, so a change renews them.")

(defun window-box--remap (face spec)
  "Remap FACE in the current buffer with SPEC, once.
A remap is the buffer\='s and would reach every window showing it,
including the ones `window-box-window-predicate\=' spares — which is
the case that predicate exists for.  The spec is therefore filtered on
the window parameter the box sets, so it applies where the box is
drawn and nowhere else."
  (unless (assq face window-box--cookies)
    (push (list face
                (face-remap-add-relative
                 face `(:filtered (:window window-box t) ,spec))
                spec)
          window-box--cookies)))

(defun window-box--unmap (face)
  "Take back the remap of FACE, if this buffer has one."
  (when-let* ((entry (assq face window-box--cookies)))
    (face-remap-remove-relative (nth 1 entry))
    (setq window-box--cookies (delq entry window-box--cookies))))

(defun window-box--unmap-all ()
  "Take back every remap this buffer holds.
The one way out for all of them: a cookie that a caller reads by hand
is a cookie that stays behind when the record changes shape."
  (dolist (entry (copy-sequence window-box--cookies))
    (window-box--unmap (car entry)))
  (setq window-box--cookies nil
        window-box--cookie-color nil))

(defun window-box--remaps (wanted)
  "Hold exactly the remaps in WANTED, an alist of face and spec.
A face that is no longer wanted gives its remap back, and one whose
spec has changed — the edge moved from above a row to below it — is
made anew."
  (dolist (entry (copy-sequence window-box--cookies))
    (let ((spec (cdr (assq (car entry) wanted))))
      (unless (equal spec (nth 2 entry))
        (window-box--unmap (car entry)))))
  (pcase-dolist (`(,face . ,spec) wanted)
    (window-box--remap face spec)))

;;;; The rows a window shows

(defconst window-box--top-format '(:eval (window-box--top))
  "The tab line format the box draws its own top edge with.")

(defconst window-box--bottom-format '(:eval (window-box--bottom))
  "The mode line format the box draws its own bottom edge with.")

(defconst window-box--tab-row-format '(:eval (window-box--row 'tab-line-format))
  "The tab line format that puts the box\='s ends on the window\='s tabs.")

(defconst window-box--header-row-format
  '(:eval (window-box--row 'header-line-format))
  "The header line format that puts the box\='s ends on the header.")

(defconst window-box--mode-row-format
  '(:eval (window-box--row 'mode-line-format))
  "The mode line format that puts the box\='s ends on the mode line.")

(defconst window-box--rows
  '((tab-line-format
     :name tab-line
     :saved window-box--saved-tab-line
     :dressed window-box--tab-row-format
     :own window-box--top-format)
    (header-line-format
     :name header-line
     :saved window-box--saved-header-line
     :dressed window-box--header-row-format
     :own window-box--top-format)
    (mode-line-format
     :name mode-line
     :saved window-box--saved-mode-line
     :dressed window-box--mode-row-format
     :own window-box--bottom-format))
  "The three rows a window can show besides its text.
Each entry is a window parameter and a plist:

  :name     the row\='s everyday name, which is also its face\='s
  :saved    the parameter that keeps the value the row had
  :dressed  the format that puts the box\='s ends on the row
  :own      the format of an edge row of the box\='s own, where the
            box can have the row to itself")

(defconst window-box--rows-order
  '(tab-line-format header-line-format mode-line-format)
  "The rows a window shows besides its text, top to bottom.")

(defun window-box--row-part (parameter part)
  "Return PART of the `window-box--rows\=' entry for PARAMETER.
PART is one of :name, :saved, :dressed and :own."
  (plist-get (cdr (assq parameter window-box--rows)) part))

(defun window-box--own-format (parameter)
  "Return the format of the box\='s own edge row in PARAMETER, or nil."
  (when-let* ((symbol (window-box--row-part parameter :own)))
    (symbol-value symbol)))

(defun window-box--dressed-format (parameter)
  "Return the format that puts the box\='s ends on the row PARAMETER."
  (symbol-value (window-box--row-part parameter :dressed)))

(defun window-box--saved-parameter (parameter)
  "Return the parameter the value PARAMETER had is kept in."
  (window-box--row-part parameter :saved))

(defun window-box--content (window parameter)
  "Return what WINDOW shows in the row PARAMETER names, box aside.
The window parameter wins over the buffer\='s variable, as it does in
redisplay.  A value of the box\='s own is not the window\='s, so the one
the box put away answers in its place.  The answer can be `none\=',
which is how a window says it hides the row."
  (let ((param (window-parameter window parameter)))
    (if (or (null param) (member param (window-box--own-values parameter)))
        (or (window-parameter window (window-box--saved-parameter parameter))
            (buffer-local-value parameter (window-buffer window)))
      param)))

(defun window-box--own-values (parameter)
  "Return the values the box itself gives the row PARAMETER."
  (delq nil (list (window-box--dressed-format parameter)
                  (window-box--own-format parameter))))

(defun window-box--line-visible-p (window parameter)
  "Return non-nil when WINDOW shows the line PARAMETER names.
The one question this asks is what the window shows there without the
box, which `window-box--content\=' answers."
  (let ((content (window-box--content window parameter)))
    (and content (not (eq content 'none)))))

(defun window-box--enclosed-p (parameter)
  "Return non-nil when the box encloses the row PARAMETER.
`window-box-enclose-top\=' rules the rows above the text and
`window-box-enclose-mode-line\=' the one below; enclosing the tab line
encloses the header line with it, so the inside is one unbroken
stack."
  (pcase parameter
    ('tab-line-format (eq window-box-enclose-top 'tab-line))
    ('header-line-format
     (memq window-box-enclose-top '(tab-line header-line)))
    ('mode-line-format (and window-box-enclose-mode-line t))))

(defun window-box--above (window)
  "Return the rows WINDOW shows above its text, top to bottom."
  (seq-filter (lambda (parameter)
                (window-box--line-visible-p window parameter))
              '(tab-line-format header-line-format)))

(defun window-box--free-slot (window)
  "Return the row above WINDOW\='s text the box may take for an edge of its own.
The box may take a row the window does not use, below every row it
leaves outside the box — an edge above such a row would draw that row
inside — and above every row it takes in, so the inside stays whole.
Innermost first, so the edge sits as close to the text as the window
allows.

This is how a row named by `window-box-enclose-top\=' appears when the
window has none: the box writes its own edge into that row, on both
displays, rather than leaving the box to close itself elsewhere."
  (let* ((slots (butlast window-box--rows-order))
         (above (window-box--above window))
         (index (lambda (row) (seq-position slots row)))
         (inside (seq-filter #'window-box--enclosed-p above))
         (outside (seq-remove #'window-box--enclosed-p above))
         (lower (if inside (funcall index (car inside)) (length slots)))
         (upper (if outside (funcall index (car (last outside))) -1)))
    (seq-find (lambda (slot)
                (and (not (memq slot above))
                     (< upper (funcall index slot) lower)))
              (reverse slots))))

(defun window-box--top-edge (window)
  "Return where the top edge of the box goes in WINDOW.
One of (overline . PARAMETER) for the overline of a row inside the
box, (own . PARAMETER) for a row of the box\='s own in a row the window
leaves free, (underline . PARAMETER) for the underline of the last row
outside the box, or nil where the display has nowhere to draw it —
then the row below closes the box with corners.

The edge marks the boundary between the rows the box leaves outside
and everything inside.  The overline of the topmost row inside marks
that boundary as well as the underline of the row above it, and it is
a row the box dresses, so its ends can carry the corners and bend to
`window-box-radius\='; the underline is the last resort, for a window
whose rows above the text are all outside the box and leave no row
free."
  (let* ((above (window-box--above window))
         ;; A terminal has neither an overline nor an underline, so an
         ;; edge there needs a row of its own.
         (attach (display-graphic-p (window-frame window)))
         (inside (seq-filter #'window-box--enclosed-p above))
         (slot (window-box--free-slot window)))
    (cond
     ;; A row inside the box is there to carry the edge.
     ((and inside attach) (cons 'overline (car inside)))
     ;; A terminal needs a row of its own for it, where one is free.
     (inside (and slot (cons 'own slot)))
     ;; Nothing inside above the text: the box draws its own edge row
     ;; in the innermost row the window leaves free.
     (slot (cons 'own slot))
     ;; None free: only an underline can mark the boundary.
     ((and above attach) (cons 'underline (car (last above)))))))

(defun window-box--bottom-edge (window)
  "Return where the bottom edge of the box goes in WINDOW.
The same shapes as `window-box--top-edge\=', for the one row below the
text: a row of the box\='s own where the window shows no mode line, the
mode line\='s underline where the box takes it in, its overline where
the box leaves it out, and nil in a terminal, which has neither line
and no row below the mode line — there the mode line carries the
corners."
  (cond
   ((not (window-box--line-visible-p window 'mode-line-format))
    '(own . mode-line-format))
   ((not (display-graphic-p (window-frame window))) nil)
   ((window-box--enclosed-p 'mode-line-format)
    '(underline . mode-line-format))
   (t '(overline . mode-line-format))))

(defun window-box--dressed-rows (window)
  "Return the rows of WINDOW the box draws its ends on, top to bottom.
The rows the enclose options take in and the window shows — on both
displays alike.  A terminal draws with characters and cannot draw a
line between the text and a row it leaves outside the box, so the box
has no edge on that side there; it does not take the row in to make
one."
  (seq-filter (lambda (parameter)
                (and (window-box--enclosed-p parameter)
                     (window-box--line-visible-p window parameter)))
              window-box--rows-order))

(defun window-box--corners (window parameter)
  "Return the two corner indices for the ends of the row PARAMETER in WINDOW.
Each is an index into `window-box-characters\=': a corner where the row
is the one that closes the box on that side, the vertical edge where
the box goes on past it.

A graphic display draws the box\='s edge on the row that carries it, so
that row\='s ends are its corners.  A terminal draws with characters and
has neither an overline nor an underline: there the row that closes the
box is the first row the box takes in, where no row above it is free
for an edge of the box\='s own, and the mode line it takes in, where
there is no row below it."
  (let ((graphic (display-graphic-p (window-frame window)))
        (top (window-box--top-edge window))
        (bottom (window-box--bottom-edge window)))
    (cond ((if graphic
               (equal top (cons 'overline parameter))
             (and (eq parameter (car (window-box--dressed-rows window)))
                  (not (eq parameter 'mode-line-format))
                  (not top)))
           '(0 1))
          ((if graphic
               (equal bottom (cons 'underline parameter))
             (and (eq parameter 'mode-line-format) (not bottom)))
           '(2 3))
          (t '(4 4)))))

(defun window-box--indented (spec)
  "Return SPEC with each `right\=' in it moved in, clear of the box\='s end.
A window parameter is the whole row, and the box takes the last
column of it, or the last pixel.  What the content of the row aligns
to `right\=' must stop short of that, or it fills the place of the end
and the box has a hole in that row.  A terminal moves it in by two: a
window left of another spends its last column on the separator, and a
tail that compensates for the margin — the reason this function
exists — otherwise ends exactly on the cap\='s column.  A stretch fills
whatever the move leaves open."
  (cond ((eq spec 'right)
         (if (display-graphic-p) '(- right (1)) '(- right 2)))
        ((consp spec) (mapcar #'window-box--indented spec))
        (t spec)))

(defun window-box--fitted (content)
  "Return CONTENT drawn, with room for the end of the box after it.
A header line with a button at its right hand end aligns that button
to `right\=', which is where the box puts its own end.  The content is
therefore drawn here, and the alignments it carries are moved in by
one.  The drawing keeps the text properties, so a button still has
its keymap and its face."
  (let ((row (format-mode-line content))
        (pos 0))
    ;; A session without a display draws nothing, and there is nothing
    ;; to fit: the content goes back as it came.
    (when (or (null row) (string-empty-p row))
      (setq row nil))
    (setq row (and row (copy-sequence row)))
    (while (and row
                (setq pos (text-property-not-all pos (length row)
                                                 'display nil row)))
      (let ((spec (get-text-property pos 'display row))
            (end (next-single-property-change pos 'display row (length row))))
        ;; A display property is one spec or a list of them — a
        ;; stretch written as ((space :align-to ...)) is as common as
        ;; the bare form, and one that slips through unmoved fills the
        ;; row to its very end and pushes the box's end off it.
        (when (or (eq (car-safe spec) 'space)
                  (and (consp spec) (consp (car-safe spec))))
          (put-text-property pos end 'display (window-box--indented spec) row))
        (setq pos end)))
    (or row content)))

(defun window-box--row-faces (parameter)
  "Return the faces that draw the row PARAMETER names.
A mode line has one for the selected window and one for the others."
  (if (eq parameter 'mode-line-format)
      '(mode-line-active mode-line-inactive)
    (list (window-box--row-part parameter :name))))

(defun window-box--trimmed (row limit)
  "Return ROW cut to LIMIT columns, where it is a drawn string.
A row wider than its window pushes everything after it off the edge,
the end of the box with it — the default mode line does it in any
window narrower than its text.  Stock redisplay clips such a row at
the window\='s edge, so the cut loses nothing that was shown, and the
stretch that follows the content fills what it opens."
  (if (and (stringp row) (> (string-width row) limit))
      (truncate-string-to-width row limit)
    row))

(defun window-box--row-limit (window)
  "Return the columns of WINDOW\='s rows that its content may fill.
The row spans the window up to the divider, and the box\='s two ends
must survive at its sides: one column covers them both on a graphic
display, where they are a pixel each, and exactly on a terminal,
where they are a column each."
  (if (display-graphic-p (window-frame window))
      (1- (/ (- (window-pixel-width window)
                (window-right-divider-width window))
             (frame-char-width)))
    (let ((margins (window-margins window)))
      (+ (window-body-width window)
         (or (car margins) 0) (or (cdr margins) 0) -2))))

(defun window-box--row (parameter)
  "Return the row PARAMETER names with the box\='s ends on it.
Called from the window parameter the box sets, so the window being
redisplayed is the selected one and its buffer is current."
  (let* ((window (selected-window))
         (graphic (display-graphic-p))
         (corners (window-box--corners window parameter))
         ;; The width of the end the stretch leaves room for: on a row
         ;; the window brought the end is a bar of one pixel.
         (end 1))
    (list (window-box--cap (nth 0 corners))
          (window-box--trimmed
           (window-box--fitted (window-box--content window parameter))
           (window-box--row-limit window))
          ;; The stretch reaches the last column, or the last pixel,
          ;; and the end goes after it — where the side edge of the
          ;; text below it runs.  In a terminal that column is counted
          ;; rather than asked for: a window left of another spends a
          ;; column of its own width on the separator, `right' does
          ;; not count it, and an end placed by it lands in it.
          (propertize " " 'display
                      (if graphic
                          ;; `right' is the right edge of the text
                          ;; area, and the margin and the fringe both
                          ;; lie outside it.  The row spans the two of
                          ;; them, so the end of the box reaches past
                          ;; both, in pixels, less the end's own width:
                          ;; a glyph aligned to the row's very end
                          ;; would start outside the row and be
                          ;; clipped away.
                          `(space :align-to
                                  (+ right
                                     (,(+ (* (or (cdr (window-margins)) 0)
                                             (frame-char-width))
                                          (cadr (window-fringes))
                                          (- end)))))
                        ;; `right' is the right edge of the text area,
                        ;; which is where the row ends in the window
                        ;; at the frame's edge and not in one left of
                        ;; another: a terminal spends a column of that
                        ;; window on the separator, and a stretch that
                        ;; runs to `right' there swallows the end that
                        ;; follows it.  The column is counted instead,
                        ;; from the text area outwards, as the drawn
                        ;; edges count their width.
                        (let ((margins (window-margins)))
                          `(space :align-to
                                  ,(+ (window-body-width)
                                      (or (cdr margins) 0) -1)))))
          (window-box--cap (nth 1 corners)))))

(defvar-local window-box--prefix-overlay nil
  "The overlay that carries the sides over lines with prefixes of their own.
A line that brings a `line-prefix' as a text property — a shell that
indents its output does — beats the buffer-local variable, and its
stretch of the sides would go missing.  An overlay\='s prefix outranks
the line\='s.  The overlay cannot carry the sides alone: it ends at the
last line of text, and the rows below it show only what the variable
says — so the sides ride both.")
(put 'window-box--prefix-overlay 'permanent-local t)

(defvar-local window-box--saved-prefix nil
  "What the buffer\='s line and wrap prefix were before the box.
A list (LINE WRAP LOCAL), where LOCAL says the buffer had a prefix of
its own, so it goes back as a buffer-local value; without it the
variables are killed again.")

(defun window-box--shed ()
  "Take the box\='s prefix off the current buffer, both carriers."
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

(defun window-box--order (window)
  "Put the fringes of WINDOW outside its margins.
The sides are periodic bitmaps at the fringes\=' outermost pixel, and
the box wants them at the very edge of the window.  A window is born
with the margins outside the fringes, and there a side would sit
between the text and the padding, or a buffer\='s own margin — inside
the box instead of on it.  The widths are not touched, and the window
gets its order back when the box goes."
  (let ((fringes (window-fringes window)))
    (unless (nth 2 fringes)
      (set-window-parameter window 'window-box--saved-order t)
      (set-window-fringes window (nth 0 fringes) (nth 1 fringes) t t))))

(defun window-box--own-margins (window width)
  "Return the margins WINDOW would wear without the box, as (LEFT RIGHT).
Either can be nil, which is how a window says the buffer\='s own
`left-margin-width\=' and `right-margin-width\=' decide.  The answer is
saved the first time the box takes the margins, so the box never adds
its own WIDTH columns to columns of its own — and a window split off a
boxed one, which arrives wearing them, is recognised by them."
  (or (window-parameter window 'window-box--saved-margins)
      (let* ((margins (window-margins window))
             (buffer (window-buffer window))
             (own (list (buffer-local-value 'left-margin-width buffer)
                        (buffer-local-value 'right-margin-width buffer)))
             (mine (cons (+ (or (nth 0 own) 0) width)
                         (+ (or (nth 1 own) 0) width)))
             (theirs (if (and (> width 0) (equal margins mine))
                         '(nil nil)
                       (list (car margins) (cdr margins)))))
        (set-window-parameter window 'window-box--saved-margins theirs)
        theirs)))

(defun window-box--dress (window parameter format)
  "Give WINDOW the row FORMAT for PARAMETER and keep what was there.
What was there is the window\='s own value, never one of the box\='s: a
box that changes its mind about a row — from an edge of its own to
the ends on the window\='s — must still give back what it found."
  (unless (equal (window-parameter window parameter) format)
    (unless (member (window-parameter window parameter)
                    (window-box--own-values parameter))
      (set-window-parameter window (window-box--saved-parameter parameter)
                            (window-parameter window parameter)))
    (set-window-parameter window parameter format)))

(defun window-box--undress (window parameter)
  "Give WINDOW back the row PARAMETER it had before the box."
  (let ((saved (window-box--saved-parameter parameter)))
    (set-window-parameter window parameter (window-parameter window saved))
    (set-window-parameter window saved nil)))

(defun window-box--apply (window)
  "Draw the box around WINDOW.
Call it with the window's buffer current."
  (set-window-parameter window 'window-box t)
  (let* ((color (window-box--color))
         (top (window-box--top-edge window))
         (bottom (window-box--bottom-edge window))
         (dressed (window-box--dressed-rows window))
         (wanted nil))
    (unless (equal color window-box--cookie-color)
      (window-box--unmap-all)
      (setq window-box--cookie-color color))
    ;; The sides: a fringe bitmap is drawn in the face its display
    ;; spec names, and that face is static — `window-box-color' and a
    ;; theme's change of the `window-box' face reach the bitmaps only
    ;; through a remap.
    (push (cons 'window-box (list :foreground color)) wanted)
    ;; The horizontal edges: an overline sits at the top of a row and
    ;; an underline, asked for the bottom position, at its very last
    ;; pixel — so the same row can be inside the box or outside it,
    ;; whichever the enclose options say.
    ;;
    ;; A row inside the box gives up the other line and the border of
    ;; its own face: both are drawn where the box draws.  A row the box
    ;; leaves outside keeps them, and everything else it wears — the
    ;; box only borrows the one line it needs there.  Stripping the
    ;; border of such a row took the padding off a mode line dressed by
    ;; `spacious-padding', which moved the row the box was drawing
    ;; against.
    (pcase-dolist (`(,edge . ,parameter)
                   ;; The lines only: a row of the box's own carries no
                   ;; line of the row's, it *is* the box's edge.
                   (seq-filter (lambda (edge)
                                 (memq (car-safe edge) '(overline underline)))
                               (list top bottom)))
      (let ((inside (memq parameter dressed)))
        (dolist (face (window-box--row-faces parameter))
          (push (cons face
                      (if (eq edge 'overline)
                          (if inside
                              (list :overline color :underline nil :box nil)
                            (list :overline color))
                        (if inside
                            (list :underline (list :color color :position 0)
                                  :overline nil :box nil)
                          (list :underline (list :color color
                                                 :position 0)))))
                wanted))))
    ;; A row that is inside the box gives up the overline, the
    ;; underline and the border of its own face, wherever the edge of
    ;; the box happens to be.  All three are drawn where the box
    ;; draws — spacious-padding gives the mode line an overline, many
    ;; themes give rows a box — and a row must not change its look
    ;; because the edge moved to the row above it.
    (dolist (parameter dressed)
      (dolist (face (window-box--row-faces parameter))
        (unless (assq face wanted)
          (push (cons face (list :overline nil :underline nil :box nil))
                wanted))))
    ;; A row of the box's own, where a row is free for one.  With a
    ;; radius the row is as tall as the arc, and the row's face — the
    ;; tab line's grey, most themes — would show as a band behind the
    ;; line: the box paints it in the buffer's own background instead.
    (dolist (parameter window-box--rows-order)
      (let ((own (and (member (cons 'own parameter) (list top bottom))
                      (window-box--own-format parameter))))
        (cond
         (own (window-box--dress window parameter own)
              ;; The radius-tall row is drawn in the row's face, and a
              ;; theme's lines on that face — spacious-padding's
              ;; overline on the mode line — would show in the band.
              (when (> (window-box--radius) 0)
                (dolist (face (window-box--row-faces parameter))
                  (unless (assq face wanted)
                    (push (cons face
                                (list :background
                                      (face-background 'default nil 'default)
                                      :overline nil :underline nil :box nil))
                          wanted)))))
         ((equal (window-parameter window parameter)
                 (window-box--own-format parameter))
          (window-box--undress window parameter)))))
    ;; The ends of the rows the box takes in: neither margins nor
    ;; fringes reach those rows, so the box goes on them through the
    ;; row itself, which it takes over and gives back as it found it.
    (dolist (parameter window-box--rows-order)
      (if (memq parameter dressed)
          (window-box--dress window parameter
                             (window-box--dressed-format parameter))
        (when (equal (window-parameter window parameter)
                     (window-box--dressed-format parameter))
          (window-box--undress window parameter))))
    (window-box--remaps (nreverse wanted))
    ;; The sides hang on the buffer's `line-prefix' and on a
    ;; buffer-spanning overlay's: the variable reaches the rows below
    ;; the last line of text, where an overlay ends, and the overlay
    ;; outranks the prefix a line brings of its own — a shell indents
    ;; its output that way, and those lines went bare on the variable
    ;; alone.  On a graphic display the
    ;; sides are periodic fringe bitmaps, one pixel at the outermost
    ;; edge, repeating over every line's full height — an image in the
    ;; margin is one default line tall, and a taller line, a banner or
    ;; a formula preview, kept bare pixels above and below it.  The
    ;; margins carry only the padding there.  A terminal has no
    ;; fringes and draws the sides in the margins.
    ;;
    ;; A buffer that keeps something in its margins keeps it: magit's
    ;; log writes the author and the date into a thirty column right
    ;; margin, and `diff-hl-margin-mode' marks every changed line of
    ;; every file in two columns on the left.  The box asks for its own
    ;; columns beside those, not instead of them — the margin grows by
    ;; the width the box needs, the box's side goes on the line prefix,
    ;; which a row shows before anything the buffer puts in the margin,
    ;; and the buffer's own marks sit inside the side.  A terminal drew
    ;; no sides at all in such a window before, which left the
    ;; horizontal edges hanging on nothing.
    (let* ((width (window-box--width))
           (graphic (display-graphic-p (window-frame window)))
           (own (window-box--own-margins window width))
           (left (+ (or (nth 0 own) left-margin-width 0) width))
           (right (+ (or (nth 1 own) right-margin-width 0) width)))
      (unless (or (zerop width)
                  (equal (window-margins window) (cons left right)))
        (set-window-margins window left right))
      (if graphic
          (progn (window-box--order window)
                 (window-box--wear (window-box--fringe-prefix)))
        (if (zerop width)
            (window-box--shed)
          (window-box--wear (window-box--prefix)))))))

(defun window-box--wear (prefix)
  "Hang PREFIX on the current buffer, on both carriers.
The buffer-local variable reaches the rows below the last line of
text; the overlay wins over lines that bring a prefix of their own.
What the buffer wore before is kept once, for the mode to give back."
  (unless window-box--saved-prefix
    (setq window-box--saved-prefix
          (list line-prefix wrap-prefix (local-variable-p 'line-prefix))))
  (setq-local line-prefix prefix
              wrap-prefix prefix)
  (unless (overlayp window-box--prefix-overlay)
    (setq window-box--prefix-overlay
          (save-restriction
            (widen)
            ;; Rear-advance, so text added at the end wears it too.
            (make-overlay (point-min) (point-max) nil nil t))))
  ;; Above every other overlay: a shell that draws an indent gutter
  ;; puts prefixes on overlays of its own, and a tie between overlays
  ;; falls whichever way redisplay walks them — the sides went missing
  ;; a stretch at a time.  While the box is up, its sides outrank a
  ;; line's own prefix; the buffer gets its gutter back with the box
  ;; gone.
  (overlay-put window-box--prefix-overlay 'priority 100)
  (overlay-put window-box--prefix-overlay 'line-prefix prefix)
  (overlay-put window-box--prefix-overlay 'wrap-prefix prefix))

(defun window-box--clear (window)
  "Remove the box from WINDOW.
The face remaps are the buffer's and go when the mode turns off."
  (set-window-parameter window 'window-box nil)
  (dolist (parameter window-box--rows-order)
    (when (member (window-parameter window parameter)
                  (window-box--own-values parameter))
      (window-box--undress window parameter)))
  ;; The order of fringes and margins, where the box turned it around.
  (when (window-parameter window 'window-box--saved-order)
    (let ((fringes (window-fringes window)))
      (set-window-fringes window (nth 0 fringes) (nth 1 fringes) nil t))
    (set-window-parameter window 'window-box--saved-order nil))
  ;; The margins the window wore without the box, nil and all: nil is
  ;; how a window leaves the width to the buffer, and a number the box
  ;; wrote over would take that away.
  (when-let* ((saved (window-parameter window 'window-box--saved-margins)))
    (set-window-margins window (nth 0 saved) (nth 1 saved))
    (set-window-parameter window 'window-box--saved-margins nil))
  (with-current-buffer (window-buffer window)
    ;; The sides hang on one overlay of the buffer's, so they serve
    ;; every boxed window at once.  Taking it off while another
    ;; window still needs it would strip that window and the next
    ;; refresh would put it back, once a window change.
    (unless (seq-some (lambda (other)
                        (and (not (eq other window))
                             (window-parameter other 'window-box)))
                      (get-buffer-window-list nil 'no-minibuffer t))
      (window-box--shed))))

(defun window-box--persist ()
  "Let the box\='s window parameters travel with a saved window state.
`window-state-get\=' saves the margins, so what the box set travels
with a hidden side window.  The marks that say those settings are the
box\='s do not, unless they are named here.  Turn the mode off while
such a window is away, and it comes back wearing the box\='s margins
with no box, and nothing left
that knows to take them off again.

The widths and the marks are numbers and t, which a state written to a
file can hold.  The rows the box took over are formats, and a format
can hold a closure, which such a state cannot, so those travel within
the session only."
  (dolist (entry '((window-box . writable)
                   (window-box--saved-margins . writable)
                   (window-box--saved-order . writable)
                   (window-box--saved-tab-line . t)
                   (window-box--saved-header-line . t)
                   (window-box--saved-mode-line . t)))
    (unless (assq (car entry) window-persistent-parameters)
      (push entry window-persistent-parameters))))

(window-box--persist)

(defun window-box--refresh-frames (&rest _)
  "Draw the box again in each window of each frame.
A theme change reaches every frame at once, and it changes the color
the box is drawn in.  The color of the fringes lives in a face remap,
which is made when a window is dressed; without this the box keeps
the color of the old theme until something else dresses that window
again.  A frame that switches from a light theme to a dark one on a
timer, as `auto-dark-mode\=' does, would keep the old color for the
rest of the session."
  (dolist (frame (frame-list))
    (window-box--refresh frame)))

(defun window-box--boxed-p (window)
  "Return non-nil when WINDOW is one to draw a box around."
  (and (buffer-local-value 'window-box-mode (window-buffer window))
       (or (null window-box-window-predicate)
           (funcall window-box-window-predicate window))))

(defun window-box--refresh (&optional frame)
  "Box and unbox the windows of FRAME to match their buffers.
Showing a buffer resets the window's fringes and margins, so boxed
windows also get theirs back here."
  (dolist (window (window-list frame 'no-minibuffer))
    (if (window-box--boxed-p window)
        (with-current-buffer (window-buffer window)
          (window-box--apply window))
      ;; Only take away what this package drew.
      (when (window-parameter window 'window-box)
        (window-box--clear window)))))

;;;; The mode

;; Before the mode, so that loading the package sets it whether or not
;; the mode has ever been on: a major mode change would otherwise clear
;; the mode along with every other local variable.
(put 'window-box-mode 'permanent-local t)

;;;###autoload
(define-minor-mode window-box-mode
  "Draw a rectangular box around every window that shows this buffer.
What your header line and your mode line show stays yours;
`window-box-enclose-top\=' and `window-box-enclose-mode-line\=' say
which of the rows around the text are inside the box.  A row that is
inside gets the ends of the box at its two sides.  See the commentary
for how the box is built."
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
        ;; A major mode change clears the face remaps and the saved
        ;; prefix along with every other local variable, and neither
        ;; event above fires for it.  The mode itself survives, being
        ;; permanent-local, so the box is drawn again from scratch —
        ;; which is what the cleared cookies ask for.
        (add-hook 'after-change-major-mode-hook #'window-box--refresh)
        ;; The last word.  A display rule can write the same window
        ;; parameters the box writes — `auto-side-windows' does, on
        ;; each display of the buffer — and whoever runs last wins.
        ;; This hook runs from the redisplay, after everything in the
        ;; cycle has had its say, so the box dresses the row again
        ;; before the frame is drawn.
        (add-hook 'window-state-change-functions #'window-box--refresh)
        ;; A theme change is not a window change, and the color of the
        ;; box comes from a face.
        (add-hook 'enable-theme-functions #'window-box--refresh-frames)
        (dolist (window (get-buffer-window-list nil nil t))
          (window-box--apply window)))
    (dolist (window (get-buffer-window-list nil nil t))
      (window-box--clear window))
    (window-box--unmap-all)
    (window-box--shed)))

(provide 'window-box)
;;; window-box.el ends here
