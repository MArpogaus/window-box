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
;; mode line say stays yours, and `window-box-encloses' says whether
;; they are inside the box or outside it.
;;
;; The sides are drawn in the margins, on both displays, and the
;; horizontal edges on the rows the window has: a row of the box's own
;; where there is a free one, an overline above a row that is inside
;; the box, an underline below one that is not.  The fringes keep their
;; width, so their indicators stay legible, and `window-box-padding'
;; buys air between a side and the text.
;;
;; Only window dressing is used:
;;
;; - The sides are the outermost column of the margin, hung on the
;;   buffer's `line-prefix'.  A prefix reaches the rows below the last
;;   line of text, where an overlay would stop, and a string bound for
;;   a margin stays invisible in a window without one.  The box puts
;;   the margins outside the fringes, which is where its sides belong.
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
A graphic display draws its horizontal edges as lines of one pixel and
its sides as a column of the margin; see
`window-box-side-characters\='.

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

(defcustom window-box-encloses '(tab-line header-line mode-line)
  "Which of a window\='s own rows the box encloses.
A list of `tab-line\=', `header-line\=' and `mode-line\='.  The text is
always inside; a row named here is inside with it, and a row left out
stays outside the box.  Nil draws a box around the text alone.

The rows sit in a fixed order — tab line, header line, text, mode line
— so the box is drawn around the text and whatever of them is next to
it, and its edges land where the inside stops.

A graphic display draws every combination: the edge above a row is
that row\='s overline, the edge below it its underline, both one pixel
at the row\='s very edge.  A terminal draws with characters and can
only use a row it is given: the top edge needs the tab line row free,
there is no row below the mode line, and where an edge has nowhere to
go the row that closes the box carries the corners instead."
  :type '(set (const :tag "Tab line" tab-line)
              (const :tag "Header line" header-line)
              (const :tag "Mode line" mode-line))
  :local t)

(defcustom window-box-side-characters "▏▕"
  "The two characters the sides are drawn with on a graphic display.
In order: the left side and the right side.  A margin holds one
character of the frame\='s font, which is wider than a line, so the
pair is a character that is a hairline at the edge of its own cell.
The default pair lands on the outermost pixel of the window, where the
horizontal edges end, and the box is one pixel on every side.

How tall the ink of a character is, is the font\='s business.  Where it
is shorter than a line, the pixels between the lines stay bare and the
side reads as a dashed line, so the box asks the font and draws a
column of the margin in the box color instead.  A column is one
unbroken line whatever the font does.

Nil asks for that column from the start.  A value that is neither nil
nor exactly two characters long is ignored and the default drawn
instead, for the reason `window-box-characters\=' gives."
  :type '(choice (const :tag "A column of the margin" nil)
                 (string :tag "Two characters, in the order ▏ ▕")))

(defcustom window-box-padding 0
  "Columns between the sides of the box and the text, per side.
The box draws its sides in one column of margin, and this many
columns more hold nothing.  Set it buffer-locally for a buffer that
wants more air than the others.

A buffer that uses its margins for its own text keeps them, and it
gets neither the sides nor the padding."
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

(defun window-box--characters ()
  "Return the six characters the box is drawn with.
`window-box-characters' can be set to anything — `setq\' asks no
`:type\' — and a shorter string would signal from inside redisplay,
where an error repaints as one instead of naming the option that
caused it.  Such a value is dropped for the default."
  (if (and (stringp window-box-characters)
           (= (length window-box-characters) 6))
      window-box-characters
    (eval (car (get 'window-box-characters 'standard-value)) t)))

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

(defun window-box--covers-line-p (character)
  "Return non-nil when CHARACTER is drawn over a whole line in this frame.
The sides are one character of a margin, and a block character is a
hairline at the edge of its cell — one pixel, which is what the box
draws everywhere else.  How tall its ink is, is the font\='s business:
where it is shorter than the line, the pixels between the lines stay
bare and the side reads as a dashed line.  The font is asked, so that
the box does not need a setting for it.

Measured with three fonts at the same size: FiraCode draws the
hairline 23 pixels tall on a line of 23, Noto Sans Mono 22 on a line
of 26."
  (when-let* ((font (car-safe (internal-char-font nil character)))
              (glyphs (font-get-glyphs font 0 1 (string character)))
              (glyph (and (> (length glyphs) 0) (aref glyphs 0))))
    (>= (+ (aref glyph 7) (aref glyph 8)) (default-line-height))))

(defun window-box--side (side)
  "Return the string that draws SIDE of the box, `left\=' or `right\='.
A terminal draws the vertical edge from `window-box-characters\='.  A
graphic display draws the pair in `window-box-side-characters\=', where
the font draws them over a whole line, and a space in the box color
where it does not: a face fills the whole cell for each line, whatever
the font does with a character."
  (let* ((pair (and (stringp window-box-side-characters)
                    (= (length window-box-side-characters) 2)
                    window-box-side-characters))
         (character (and pair (aref pair (if (eq side 'left) 0 1)))))
    (cond
     ((not (display-graphic-p))
      (propertize (string (aref (window-box--characters) 4))
                  'face (list :foreground (window-box--color))))
     ((and character (window-box--covers-line-p character))
      (propertize (string character)
                  'face (list :foreground (window-box--color))))
     (t (propertize " " 'face (list :background (window-box--color)))))))

(defun window-box--width ()
  "Return the margin the box needs on each side, in columns.
One column for the side itself and `window-box-padding\=' for air."
  (1+ (if (natnump window-box-padding) window-box-padding 0)))

(defun window-box--prefix ()
  "Return the line prefix that draws the sides.
The side goes in the outermost column of the margin, so the box ends
where the window does: first on the left, last on the right.  The
padding is the columns between it and the text."
  (let* ((padding (make-string (1- (window-box--width)) ?\s))
         (left (window-box--side 'left))
         (right (window-box--side 'right)))
    (concat
     (propertize " " 'display `((margin left-margin) ,(concat left padding)))
     (propertize " " 'display `((margin right-margin)
                                ,(concat padding right))))))

(defun window-box--cap (corner)
  "Return the box\='s end for one side of a row it encloses.
CORNER is an index into `window-box-characters\=', which a terminal
draws: the vertical edge where the box goes on past this row, a corner
where the row is the one that closes it."
  (if (display-graphic-p)
      ;; A row is not a margin: a bar of one pixel lands on the
      ;; outermost pixel of the window, which is where the side below
      ;; it runs, whether that side is a solid column or a character.
      (propertize " " 'face (list :background (window-box--color))
                  'display '(space :width (1)))
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
     :dressed window-box--header-row-format)
    (mode-line-format
     :name mode-line
     :saved window-box--saved-mode-line
     :dressed window-box--mode-row-format
     :own window-box--bottom-format))
  "The three rows a window can show besides its text.
Each entry is a window parameter and a plist:

  :name     what the option `window-box-encloses\=' calls the row,
            which is also the name of its face
  :saved    the parameter that keeps the value the row had
  :dressed  the format that puts the box\='s ends on the row
  :own      the format of an edge row of the box\='s own, where the
            box can have the row to itself")

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
  "Return non-nil when `window-box-encloses\=' takes in the row PARAMETER."
  (memq (window-box--row-part parameter :name) window-box-encloses))

(defun window-box--above (window)
  "Return the rows WINDOW shows above its text, top to bottom."
  (seq-filter (lambda (parameter)
                (window-box--line-visible-p window parameter))
              '(tab-line-format header-line-format)))

(defun window-box--top-edge (window)
  "Return where the top edge of the box goes in WINDOW.
Either (overline . PARAMETER) or (underline . PARAMETER) for an edge
on a row the window already has, the symbol `own\=' for a row of the
box\='s own in the free tab line row, or nil where the display has
nowhere to draw it — then the row below closes the box with corners.

The edge lands where the inside of the box stops: above the topmost
row `window-box-encloses\=' takes in, and below the last row it leaves
out."
  (let* ((above (window-box--above window))
         ;; A terminal has neither an overline nor an underline, so an
         ;; edge there needs a row of its own.
         (attach (display-graphic-p (window-frame window)))
         (inside (seq-drop-while (lambda (parameter)
                                   (not (window-box--enclosed-p parameter)))
                                 above)))
    (cond
     ;; Nothing above the text: the tab line row is free for an edge.
     ((null above) 'own)
     ;; The topmost row is inside, so the edge goes above it — which
     ;; is the tab line row itself when that is the row, and a row of
     ;; the box's own is only possible while it is free.
     ((eq (car inside) (car above))
      (cond (attach (cons 'overline (car above)))
            ;; No overline to attach to: a row of the box's own, where
            ;; the tab line row is free for one.
            ((not (eq (car above) 'tab-line-format)) 'own)))
     ;; Something above is left out: the edge goes under the last of
     ;; those rows, which only an underline can do.
     (attach (cons 'underline (car (if inside
                                       (seq-difference above inside)
                                     (last above))))))))

(defun window-box--bottom-edge (window)
  "Return where the bottom edge of the box goes in WINDOW.
Like `window-box--top-edge\=', for the mode line: below it where
`window-box-encloses\=' takes it in, above it where it does not, and a
row of the box\='s own where the window shows no mode line."
  (let ((attach (display-graphic-p (window-frame window))))
    (cond
     ((not (window-box--line-visible-p window 'mode-line-format)) 'own)
     ((not attach) nil)
     ((window-box--enclosed-p 'mode-line-format)
      (cons 'underline 'mode-line-format))
     (t (cons 'overline 'mode-line-format)))))

(defun window-box--dressed-rows (window)
  "Return the rows of WINDOW the box draws its ends on, top to bottom."
  (seq-filter (lambda (parameter)
                (and (window-box--enclosed-p parameter)
                     (window-box--line-visible-p window parameter)))
              '(tab-line-format header-line-format mode-line-format)))

(defun window-box--corners (window parameter)
  "Return the two characters that end the row PARAMETER in WINDOW.
A vertical edge where the box goes on past the row, a corner where
the row is the one that closes it — which is what a terminal is left
with when the edge beyond it has nowhere to go."
  (let ((rows (window-box--dressed-rows window)))
    (cond ((and (eq parameter (car rows))
                (not (eq parameter 'mode-line-format))
                (not (window-box--top-edge window)))
           '(0 1))
          ((and (eq parameter 'mode-line-format)
                (not (window-box--bottom-edge window)))
           '(2 3))
          (t '(4 4)))))

(defun window-box--indented (spec)
  "Return SPEC with each `right\=' in it moved in by the width of one end.
A window parameter is the whole row, and the box takes the last
column of it, or the last pixel.  What the content of the row aligns
to `right\=' must therefore stop one step earlier, or it fills the
place of the end and the box has a hole in that row."
  (cond ((eq spec 'right) (if (display-graphic-p) '(- right (1)) '(- right 1)))
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
        (when (eq (car-safe spec) 'space)
          (put-text-property pos end 'display (window-box--indented spec) row))
        (setq pos end)))
    (or row content)))

(defun window-box--row-faces (parameter)
  "Return the faces that draw the row PARAMETER names.
A mode line has one for the selected window and one for the others."
  (if (eq parameter 'mode-line-format)
      '(mode-line-active mode-line-inactive)
    (list (window-box--row-part parameter :name))))

(defun window-box--row (parameter)
  "Return the row PARAMETER names with the box\='s ends on it.
Called from the window parameter the box sets, so the window being
redisplayed is the selected one and its buffer is current."
  (let* ((window (selected-window))
         (corners (window-box--corners window parameter)))
    (list (window-box--cap (nth 0 corners))
          (window-box--fitted (window-box--content window parameter))
          ;; The stretch reaches the last column, or the last pixel,
          ;; and the end goes after it — where the side edge of the
          ;; text below it runs.  In a terminal that column is counted
          ;; rather than asked for: a window left of another spends a
          ;; column of its own width on the separator, `right' does
          ;; not count it, and an end placed by it lands in it.
          (propertize " " 'display
                      (if (display-graphic-p)
                          ;; `right' is the right edge of the text
                          ;; area, and a margin of the buffer's own
                          ;; lies outside it.  The row spans the
                          ;; margin, so the end of the box has to
                          ;; reach past it, in pixels.
                          `(space :align-to
                                  (+ right
                                     (,(* (or (cdr (window-margins)) 0)
                                          (frame-char-width)))))
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

(defun window-box--order (window)
  "Put the margins of WINDOW outside its fringes.
The sides are drawn in the margins, and the box wants them at the
edge of the window.  With the fringes outside the margins a side sits
between the fringe and the text, and the horizontal edges, which span
the row, then reach past it.

Emacs keeps this order in the window, so a window that another
package left with the fringes outside its margins says so, and an
older version of this package set it that way itself.  The widths are
not touched, only the order, and the window gets its order back when
the box goes."
  (let ((fringes (window-fringes window)))
    (when (nth 2 fringes)
      (set-window-parameter window 'window-box--saved-fringes t)
      (set-window-fringes window (nth 0 fringes) (nth 1 fringes) nil t))))

(defun window-box--wide-margins-p (window)
  "Return non-nil when WINDOW has margins of its own to keep.
The box needs `window-box--width\=' columns for a side and its
padding; anything wider was put there by whoever dressed the window,
and holds something the box must not drop.

The buffer is asked as well as the window, and any width it asks for
counts.  Emacs applies `left-margin-width' when the buffer is
displayed, so a buffer that asks for a margin later — as
`outline-minor-mode' does when it draws its buttons there — would
never be seen: the box has written its own width into the window by
then.  One column is enough for a fold arrow, so the box gives way to
any width at all rather than to a wider one."
  (let ((margins (window-margins window))
        (width (window-box--width)))
    (or (> (or (car margins) 0) width)
        (> (or (cdr margins) 0) width)
        (with-current-buffer (window-buffer window)
          (or (> (or left-margin-width 0) 0)
              (> (or right-margin-width 0) 0))))))

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
    ;; The horizontal edges: an overline sits at the top of a row and
    ;; an underline, asked for the bottom position, at its very last
    ;; pixel — so the same row can be inside the box or outside it,
    ;; whichever `window-box-encloses' says.  The row's own underline
    ;; and box give way to the edge; content, fonts and colors stay.
    (pcase-dolist (`(,edge . ,parameter) (delq nil (list (and (consp top) top)
                                                         (and (consp bottom)
                                                              bottom))))
      (dolist (face (window-box--row-faces parameter))
        (push (cons face
                    (if (eq edge 'overline)
                        (list :overline color :underline nil :box nil)
                      (list :underline (list :color color :position 0)
                            :overline nil :box nil)))
              wanted)))
    ;; A row that is inside the box gives up the underline and the
    ;; border of its own face, wherever the edge of the box happens to
    ;; be.  Both are drawn where the box draws, and a row must not
    ;; change its look because the edge moved to the row above it.
    (dolist (parameter dressed)
      (dolist (face (window-box--row-faces parameter))
        (unless (assq face wanted)
          (push (cons face (list :underline nil :box nil)) wanted))))
    ;; A row of the box's own, where a row is free for one.
    (dolist (parameter '(tab-line-format mode-line-format))
      (let ((own (and (eq (if (eq parameter 'tab-line-format) top bottom) 'own)
                      (window-box--own-format parameter))))
        (cond
         (own (window-box--dress window parameter own))
         ((equal (window-parameter window parameter)
                 (window-box--own-format parameter))
          (window-box--undress window parameter)))))
    ;; The ends of the rows the box takes in: neither margins nor
    ;; fringes reach those rows, so the box goes on them through the
    ;; row itself, which it takes over and gives back as it found it.
    (dolist (parameter '(tab-line-format header-line-format
                                         mode-line-format))
      (if (memq parameter dressed)
          (window-box--dress window parameter
                             (window-box--dressed-format parameter))
        (when (equal (window-parameter window parameter)
                     (window-box--dressed-format parameter))
          (window-box--undress window parameter))))
    (window-box--remaps (nreverse wanted))
    ;; The sides are characters in the margins, on both displays.
    ;; They hang on the buffer's `line-prefix' and not on an overlay,
    ;; because an overlay ends where the buffer does and the box would
    ;; end with it, leaving the rows below the last line open.  A
    ;; prefix reaches those rows on a graphic display as well.
    ;; Buffer-wide is no loss of precision: a character bound for a
    ;; margin stays invisible in a window that has none, and the box
    ;; gives the margins only to the windows it is drawn in.
    ;;
    ;; A buffer that keeps something in its margins needs them more
    ;; than the box does: magit's log writes the author and the date
    ;; into a thirty column right margin, and taking that column for a
    ;; side drops it without a word.  Such a window keeps its margins
    ;; and gets the horizontal edges alone.  The test is the margins
    ;; as they stand, not what they were when the box went up, so a
    ;; buffer that sets them later is noticed on the next change and
    ;; the sides give way then.
    (window-box--order window)
    (let ((width (window-box--width)))
      (if (window-box--wide-margins-p window)
          (progn
            ;; Give back what the box took, if it took anything: the
            ;; buffer's own widths, which Emacs applies when it
            ;; displays a buffer and which the box has been writing
            ;; over since.  A window dressed by someone else, magit's
            ;; log among them, is left as it stands.
            (when (and (window-parameter window 'window-box--saved-margins)
                       ;; only the box's own width, never a width
                       ;; someone else has set since
                       (equal (window-margins window) (cons width width)))
              (set-window-margins window left-margin-width right-margin-width))
            (set-window-parameter window 'window-box--saved-margins nil)
            (window-box--restore-prefix))
        (unless (window-parameter window 'window-box--saved-margins)
          (let ((margins (window-margins window)))
            (set-window-parameter
             window 'window-box--saved-margins
             ;; A window split off from a boxed one arrives with the
             ;; box's own margins, and saving those would give them
             ;; back for good.  The buffer's widths are what Emacs
             ;; would have given such a window.
             (if (equal margins (cons width width))
                 (list left-margin-width right-margin-width)
               (list (car margins) (cdr margins))))))
        (unless (equal (window-margins window) (cons width width))
          (set-window-margins window width width))
        (unless window-box--saved-prefix
          (setq window-box--saved-prefix
                (list line-prefix wrap-prefix (local-variable-p 'line-prefix))))
        (let ((prefix (window-box--prefix)))
          (setq-local line-prefix prefix
                      wrap-prefix prefix))))))

(defun window-box--clear (window)
  "Remove the box from WINDOW.
The face remaps are the buffer's and go when the mode turns off."
  (set-window-parameter window 'window-box nil)
  (dolist (parameter '(tab-line-format header-line-format mode-line-format))
    (when (member (window-parameter window parameter)
                  (window-box--own-values parameter))
      (window-box--undress window parameter)))
  ;; The order of margins and fringes, where the box turned it around.
  (when (window-parameter window 'window-box--saved-fringes)
    (let ((fringes (window-fringes window)))
      (set-window-fringes window (nth 0 fringes) (nth 1 fringes) t t))
    (set-window-parameter window 'window-box--saved-fringes nil))
  ;; The margins the window had, where the box took them.
  (when-let* ((saved (window-parameter window 'window-box--saved-margins)))
    (set-window-margins window (nth 0 saved) (nth 1 saved))
    (set-window-parameter window 'window-box--saved-margins nil))
  (with-current-buffer (window-buffer window)
    ;; The terminal sides hang on the buffer's own prefix, so they
    ;; serve every boxed window at once.  Taking it back while another
    ;; one still needs it would strip that window and the next refresh
    ;; would put it back, once a window change.
    (unless (seq-some (lambda (other)
                        (and (not (eq other window))
                             (window-parameter other 'window-box)))
                      (get-buffer-window-list nil 'no-minibuffer t))
      (window-box--restore-prefix))))

(defun window-box--persist ()
  "Let the box\='s window parameters travel with a saved window state.
`window-state-get\=' saves the margins and the order of the margins and
the fringes, so what the box set travels with a hidden side window.
The marks that say those settings are the box\='s do not, unless they
are named here.  Turn the mode off while such a window is away, and it
comes back wearing the box\='s margins with no box, and nothing left
that knows to take them off again.

The widths and the marks are numbers and t, which a state written to a
file can hold.  The rows the box took over are formats, and a format
can hold a closure, which such a state cannot, so those travel within
the session only."
  (dolist (entry '((window-box . writable)
                   (window-box--saved-margins . writable)
                   (window-box--saved-fringes . writable)
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
What your header line and your mode line show stays yours, and
`window-box-encloses\=' says which of the rows around the text are
inside the box.  A row that is inside gets the ends of the box at its
two sides.  See the commentary for how the box is built."
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
    (window-box--restore-prefix)))

(provide 'window-box)
;;; window-box.el ends here
