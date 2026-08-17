;;; gui-test.el --- Graphic display session for the pixel test -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded by `make gui' inside a graphic Emacs.  It is the one test
;; file the Makefile leaves out of the byte-compilation, because it
;; calls what only a build with X defines.  It boxes two side
;; windows, exports the frame and exits; gui-check.py reads the pixels
;; back.
;;
;; The header line here measures itself with `string-pixel-width', the
;; way a header with right aligned buttons has to.  That measurement
;; re-enters redisplay, and it is what turned a face `:height' below
;; one in a side window's mode line into a stack overflow.  Keep it.

;;; Code:

(require 'window-box)

;; The sides are a character in a margin, and how much of its cell a
;; character covers is the font's business.  The measurement needs a
;; font whose side character is a line down the whole cell.
(let ((font (seq-find (lambda (name) (find-font (font-spec :name name)))
                      '("Noto Sans Mono" "DejaVu Sans Mono"
                        "Liberation Mono"))))
  (when font (set-frame-font (format "%s 13" font) nil t)))

;; The default draws each side as a hairline, which is a character, and
;; how tall its ink is, is the font's business: the fonts on a runner
;; are not the fonts on a desk.  The measurement asks for the column
;; instead, so that a gap in a side is the package's fault and never
;; the font's.  `window-box-test-a-side-is-a-character-or-a-column'
;; covers the choice itself.
(setq window-box-side-characters nil)

;; A scroll bar sits outside the fringe, so the box's right edge would
;; land inside it.  Off, as a configuration that wants boxes has it.
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

(defconst gui-test-file "/tmp/window-box-gui.png"
  "Where the exported frame lands.")

(defconst gui-test-geometry "/tmp/window-box-gui.txt"
  "Where the pixel edges of the boxed windows land.
The checker needs them: a frame holds more grey lines than this
package draws, the mode line's own shadow among them.")

(defconst gui-test-encloses-file "/tmp/window-box-encloses.png"
  "Where the frame of the `window-box-encloses\=' examples lands.")

(defconst gui-test-encloses-geometry "/tmp/window-box-encloses.txt"
  "Where the boxed windows of that frame land, with the edges they want.
Each line is LEFT TOP RIGHT BOTTOM TOP-EDGE BOTTOM-EDGE, the last two
worked out from the row heights Emacs reports and the setting alone,
so the checker measures the package against the display and not
against itself.")

(defvar gui-test-header
  '(:eval
    (let* ((chip (propertize " ! " 'face '(:background "#d08770"
                                           :foreground "white")))
           (buttons (concat (propertize "─" 'mouse-face 'highlight)
                            " "
                            (propertize "✕" 'mouse-face 'highlight)))
           ;; The box cannot reach this row: fringes and margins stop
           ;; below it.  So the header closes the box itself, with a
           ;; one pixel cap at each end, and only while there is a box
           ;; to close.
           (cap (if window-box-mode
                    (propertize " " 'face (list :background
                                                (face-foreground
                                                 'window-box nil 'default))
                                'display '(space :width (1)))
                  "")))
      (list cap chip " " (format-mode-line "%b")
            (propertize " " 'display
                        `(space :align-to
                                (- right (,(+ (string-pixel-width
                                               (propertize buttons 'face
                                                           'header-line))
                                              1)))))
            buttons
            ;; The cap goes in the last column, not where the
            ;; measurement lands: a glyph can render a pixel wider
            ;; than it measures, and the box would miss the corner.
            (propertize " " 'display '(space :align-to right))
            cap)))
  "A header line that measures itself, as a real one does.")

(defun gui-test--fringes ()
  "Check that unboxing gives a split window its own fringes back.
Emacs gives a new window the fringes of the one it was split from, so
a window split off while the box is on arrives wearing the box\='s
own — and saving those would give them back for good.  Only a graphic
display has fringes, so this is checked here rather than in the batch
suite."
  (let ((buffer (get-buffer-create "*fringes*")))
    (with-current-buffer buffer
      (erase-buffer)
      (insert "split while boxed\n"))
    (switch-to-buffer buffer)
    (delete-other-windows)
    (let ((wide (seq-take (window-fringes (selected-window)) 2)))
      (with-current-buffer buffer (window-box-mode 1))
      (window-box--refresh)
      (split-window-below)
      (window-box--refresh)
      (with-current-buffer buffer (window-box-mode -1))
      (window-box--refresh)
      (dolist (window (window-list nil 'no-minibuffer))
        (unless (equal (seq-take (window-fringes window) 2) wide)
          (error "A window kept the box's fringes: %S, wanted %S"
                 (seq-take (window-fringes window) 2) wide))))
    (delete-other-windows)
    (kill-buffer buffer)))

(defun gui-test--wanted (window)
  "Return the pixel rows the box\='s edges want around WINDOW.
The edge above a row that is inside the box sits on that row\='s first
pixel, the edge below a row that is outside it on that row\='s last —
so the rows the setting leaves out are what stands between the window
and its box."
  (pcase-let* ((`(,_ ,top ,_ ,bottom) (window-edges window nil nil t))
               (encloses (buffer-local-value 'window-box-encloses
                                             (window-buffer window)))
               (outside (+ (if (memq 'tab-line encloses)
                               0 (window-tab-line-height window))
                           (if (memq 'header-line encloses)
                               0 (window-header-line-height window)))))
    (list (if (zerop outside) top (+ top outside -1))
          (if (memq 'mode-line encloses)
              (1- bottom)
            (- bottom (window-mode-line-height window))))))

(defun gui-test--example (name encloses tabs)
  "Return a buffer NAME with rows to enclose, ENCLOSES what to take in.
TABS non-nil gives it a tab line of its own."
  (let ((buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (erase-buffer)
      (insert (format "%s: %s\n"
                      name (if encloses
                               (mapconcat #'symbol-name encloses ", ")
                             "the text alone")))
      (setq-local header-line-format " a header line of my own "
                  mode-line-format " a mode line of my own "
                  window-box-encloses encloses)
      (when tabs (setq-local tab-line-format " a tab line of my own ")))
    buffer))

(defun gui-test--encloses ()
  "Export a frame with one window per `window-box-encloses\=' setting."
  ;; Four windows with a header, a mode line and room to see them.
  (set-frame-size (selected-frame) 700 900 t)
  (switch-to-buffer (gui-test--example "*text*" nil nil))
  (delete-other-windows)
  (let* ((first (selected-window))
         (second (split-window first nil 'below))
         (third (split-window second nil 'below))
         (fourth (split-window third nil 'below))
         (windows (list first second third fourth)))
    (set-window-buffer second (gui-test--example "*header*" '(header-line) nil))
    (set-window-buffer third (gui-test--example "*header and mode*"
                                                '(header-line mode-line) nil))
    ;; and one with padding: the box takes a column for its side and
    ;; two more for air, and the side stays at the window's edge.
    (with-current-buffer (window-buffer second)
      (setq-local window-box-padding 2))
    (set-window-buffer fourth (gui-test--example "*everything*"
                                                 '(tab-line header-line
                                                            mode-line)
                                                 t))
    ;; A buffer that keeps a margin of its own, as magit's log does:
    ;; the row spans that margin, and the end of the box has to reach
    ;; past it.
    (with-current-buffer (window-buffer third)
      (setq-local right-margin-width 10)
      (set-window-buffer third (current-buffer)))
    ;; One of them split, so a window that is not at the frame's right
    ;; edge is measured too: an end placed by the row's own right edge
    ;; can land in what separates the two.
    (let ((beside (with-selected-window third (split-window-right))))
      (set-window-buffer beside (gui-test--example "*beside*"
                                                   '(header-line mode-line)
                                                   nil))
      (setq windows (append windows (list beside))))
    (dolist (window windows)
      (with-current-buffer (window-buffer window) (window-box-mode 1)))
    (window-box--refresh)
    (force-mode-line-update t)
    (redisplay t)
    (write-region
     (mapconcat (lambda (window)
                  (format "%s %s\n"
                          (string-join
                           (mapcar #'number-to-string
                                   (window-edges window nil nil t))
                           " ")
                          (string-join
                           (mapcar #'number-to-string
                                   (append (gui-test--wanted window)
                                           ;; whether the box draws
                                           ;; sides here at all: a
                                           ;; buffer that keeps its
                                           ;; own margins gets none
                                           ;; asked in the window's
                                           ;; own buffer, because the
                                           ;; padding is the buffer's
                                           (list (if (with-current-buffer
                                                         (window-buffer window)
                                                       (window-box--wide-margins-p
                                                        window))
                                                     0 1))))
                           " ")))
                windows "")
     nil gui-test-encloses-geometry nil 'quiet)
    (let ((coding-system-for-write 'binary))
      (write-region (x-export-frames nil 'png) nil
                    gui-test-encloses-file nil 'quiet))
    (dolist (window windows)
      (with-current-buffer (window-buffer window) (window-box-mode -1)))
    (delete-other-windows)))

(defun gui-test--order ()
  "Check that the box puts the margins outside the fringes.
The sides are drawn in the margins, and with the fringes outside them
a side sits between the fringe and the text.  A window keeps that
order, so one that another package left the other way round, or an
older version of this package, says so.  Only a graphic display has
fringes, so this is checked here and not in the batch suite."
  (set-frame-size (selected-frame) 700 520 t)
  (let ((buffer (get-buffer-create "*order*")))
    (with-current-buffer buffer
      (erase-buffer)
      (insert "fringes outside the margins\n"))
    (switch-to-buffer buffer)
    (delete-other-windows)
    (let ((window (selected-window)))
      (set-window-fringes window 8 8 t)
      (with-current-buffer buffer (window-box-mode 1))
      (window-box--refresh)
      (when (nth 2 (window-fringes window))
        (error "The box left the fringes outside the margins"))
      (unless (equal (seq-take (window-fringes window) 2) '(8 8))
        (error "The box changed the fringe widths: %S"
               (seq-take (window-fringes window) 2)))
      (with-current-buffer buffer (window-box-mode -1))
      (window-box--refresh)
      (unless (nth 2 (window-fringes window))
        (error "The box kept the order it turned around")))
    (delete-other-windows)
    (kill-buffer buffer)))

(defun gui-test--run ()
  "Box two side windows, export the frame and exit."
  (set-frame-size (selected-frame) 700 520 t)
  (gui-test--fringes)
  (gui-test--order)
  (switch-to-buffer (get-buffer-create "*main*"))
  (delete-other-windows)
  (insert "The main window keeps its own dressing.\n")
  (dolist (side '(top bottom))
    (let ((buffer (get-buffer-create (format "*%s*" side))))
      (with-current-buffer buffer
        (erase-buffer)
        (insert (format "The %s side window is boxed.\n" side))
        (setq-local header-line-format gui-test-header
                    mode-line-format nil))
      (display-buffer-in-side-window buffer `((side . ,side)
                                              (window-height . 6)))
      (with-current-buffer buffer (window-box-mode 1))))
  (force-mode-line-update t)
  (redisplay t)
  (write-region
   (mapconcat (lambda (window)
                (format "%s\n" (string-join
                                (mapcar #'number-to-string
                                        (window-edges window nil nil t))
                                " ")))
              (seq-filter (lambda (window)
                            (buffer-local-value 'window-box-mode
                                                (window-buffer window)))
                          (window-list nil 'no-minibuffer))
              "")
   nil gui-test-geometry nil 'quiet)
  (let ((coding-system-for-write 'binary))
    (write-region (x-export-frames nil 'png) nil gui-test-file nil 'quiet))
  (gui-test--encloses)
  (kill-emacs 0))

;; Wait for the frame: the test measures pixels, so redisplay has to
;; have brought it up.
(run-with-timer 0.5 nil
                (lambda ()
                  (condition-case err (gui-test--run)
                    (error
                     ;; A message goes to the echo area of a frame
                     ;; nobody is watching; the runner reads this.
                     (write-region (format "gui-test: %S\n" err) nil
                                   "/tmp/window-box-gui-error.txt" nil 'quiet)
                     (kill-emacs 1)))))

(provide 'gui-test)
;;; gui-test.el ends here
