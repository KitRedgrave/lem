#|
link : http://www.daregada.sakuraweb.com/paredit_tutorial_ja.html
|#

(defpackage :lem-paredit-mode
  (:use :cl
        :lem
        :lem-vi-mode.word)
  (:export :paredit-mode
           :paredit-forward
           :paredit-backward
           :paredit-insert-paren
           :paredit-backward-delete
           :paredit-close-parenthesis
           :paredit-slurp
           :paredit-barf
           :paredit-splice
           :*paredit-mode-keymap*))
(in-package :lem-paredit-mode)

(define-minor-mode paredit-mode
    (:name "paredit"
     :keymap *paredit-mode-keymap*))

(defun move-to-word-end (q)
  (loop while (not (syntax-space-char-p (character-at q)))
        do (character-offset q 1)))

(defun backward-open-paren-char-p (p)
  (with-point ((q p))
    (skip-whitespace-backward q)
    (syntax-open-paren-char-p (character-at q))))

(defun %skip-closed-parens-and-whitespaces-forward (point skip-last-whitespaces)
  (loop while (syntax-closed-paren-char-p (character-at point))
        do (progn
             (skip-whitespace-forward point)
             (character-offset point 1)))
  (character-offset point 1)
  (when skip-last-whitespaces
    (skip-whitespace-forward point)))

(define-command paredit-forward (&optional (n 1)) ("p")
  (forward-sexp n))

(define-command paredit-backward (&optional (n 1)) ("p")
  (backward-sexp n))

(defun bolp (point)
  (zerop (point-charpos point)))

(defun eolp (point)
  (let ((len (length (line-string point))))
    (or (zerop len)
        (>= (point-charpos point)
            (1- len)))))

(defun integer-char-p (char)
  (< (char-code #\0) (char-code char) (char-code #\9)))

(defun sharp-literal-p (char point)
  (with-point ((p point))
    (character-offset p -1)
    (and (character-at p)
         (char-equal (character-at p) char)
         (eql (character-at p -1) #\#))))

(defun sharp-n-literal-p (char point)
  (with-point ((p point))
    (character-offset p -1)
    (when (char-equal char (character-at p))
      (character-offset p -1)
      (skip-chars-backward p #'integer-char-p)
      (and (integer-char-p (character-at p))
           (eql (character-at p -1) #\#)))))

(defparameter *non-space-following-chars*
  '(#\Space #\( #\' #\` #\,))

(defparameter *non-space-preceding-chars*
  '(#\Space #\)))

(define-command paredit-insert-paren () ()
  (let ((p (current-point)))
    (when (in-string-or-comment-p p)
      (insert-character p #\()
      (return-from paredit-insert-paren))
    (when (eql (character-at p -1) #\\)
      (insert-character p #\()
      (return-from paredit-insert-paren))
    (unless (or (bolp p)
                (find (character-at p -1)
                      *non-space-following-chars*)
                (eql (character-at p -1) #\#)
                (and (eql (character-at p -1) #\@)
                     (eql (character-at p -2) #\,))
                (sharp-literal-p #\' p)
                (sharp-literal-p #\. p)
                (sharp-literal-p #\S p)
                (sharp-literal-p #\C p)
                (sharp-literal-p #\+ p)
                (sharp-literal-p #\- p)
                (sharp-n-literal-p #\A p)
                (sharp-n-literal-p #\= p))
      (insert-character p #\Space))
    (dolist (c '(#\( #\)))
      (insert-character p c))
    (unless (or (eolp p)
                (eql (character-at p) #\Space)
                (eql (character-at p) #\)))
      (insert-character p #\Space)
      (character-offset p -1))
    (character-offset p -1)))

(define-command paredit-insert-doublequote () ()
  (let ((p (current-point)))
    (cond
      ((eql (character-at p -1) #\\)
       (insert-character p #\"))
      ((and (in-string-p p)
            (eql (character-at p) #\"))
       (forward-char))
      ((and (in-string-p p)
            (not (eql (character-at p -1) #\\)))
       (insert-character p #\\)
       (insert-character p #\"))
      (t (unless (or (bolp p)
                     (find (character-at p -1)
                           *non-space-following-chars*)
                     (sharp-literal-p #\P p))
           (insert-character p #\Space))
         (dolist (c '(#\" #\"))
           (insert-character p c))
         (unless (or (eolp p)
                     (find (character-at p)
                           *non-space-preceding-chars*))
           (insert-character p #\Space)
           (character-offset p -1))
         (character-offset p -1)))))

(define-command paredit-backward-delete (&optional (n 1)) ("p")
  (when (< 0 n)
    (with-point ((p (current-point)))
      (cond
        ((eql (character-at p -2) #\\)
         (delete-previous-char 2))
        ((or (and (not (in-string-or-comment-p p))
                  (eql (character-at p -1) #\()
                  (eql (character-at p) #\)))
             (and (in-string-p p)
                  (eql (character-at p -1) #\")
                  (eql (character-at p) #\")))
         (delete-next-char)
         (delete-previous-char))
        ((and (not (in-string-or-comment-p p))
              (or (eql (character-at p -1) #\))
                  (eql (character-at p -1) #\")))
         (backward-char))
        (t
         (delete-previous-char))))
    (paredit-backward-delete (1- n))))

(define-command paredit-close-parenthesis () ()
  (with-point ((p (current-point)))
    (case (character-at p)
      (#\)
       (if (eql (character-at p -1) #\\)
           (insert-character p #\))
           (forward-char)))
      (otherwise
       (handler-case (scan-lists p 1 1)
         (error ()
           (insert-character p #\))
           (return-from paredit-close-parenthesis)))
       (with-point ((new-p p))
         (character-offset new-p -1)
         (move-point (current-point) new-p)
         (with-point ((p new-p))
           (skip-whitespace-backward p)
           (delete-between-points p new-p)))))))

(define-command paredit-slurp () ()
  (with-point ((origin (current-point))
               (kill-start (current-point)))
    (scan-lists kill-start 1 1)
    (character-offset kill-start -1)
    (with-point ((yank-point kill-start :left-inserting))
      (%skip-closed-parens-and-whitespaces-forward yank-point t)
      (if (syntax-open-paren-char-p (character-at yank-point))
          (scan-lists yank-point 1 0)
          (move-to-word-end yank-point))
      (kill-ring-new)
      (with-point ((kill-end kill-start))
        (%skip-closed-parens-and-whitespaces-forward kill-end nil)
        (character-offset kill-end -1)
        (kill-region kill-start kill-end)
        (move-point (current-point) yank-point)
        (yank)
        (move-point (current-point) origin)
        (indent-region origin yank-point)))))

(define-command paredit-barf () ()
  (with-point ((origin (current-point) :right-inserting)
               (p (current-point)))
    (scan-lists p -1 1)
    (when (syntax-open-paren-char-p (character-at p))
      (scan-lists p 1 0)
      (character-offset p -2)
      (with-point ((yank-point p))
        (if (syntax-closed-paren-char-p (character-at p))
            (scan-lists yank-point -1 1)
            (backward-word-begin yank-point 1 t))
        (move-point (current-point) yank-point)
        (skip-whitespace-backward yank-point)
        (kill-ring-new)
        (with-point ((q p))
          (character-offset p 1)
          (character-offset q 2)
          (kill-region p q)
          (move-point (current-point) yank-point)
          (yank)
          (move-point (current-point) origin)
          (indent-region origin p))))))

(define-command paredit-splice () ()
  (with-point ((origin (current-point) :right-inserting)
               (start (current-point)))
    (scan-lists start -1 1)
    (when (syntax-open-paren-char-p (character-at start))
      (with-point ((end start))
        (scan-lists start 1 0)
        (character-offset start -1)
        (delete-character start)
        (delete-character end)
        (indent-region start end)))))

(loop for (k . f) in '((forward-sexp . paredit-forward)
                       (backward-sexp . paredit-backward)
                       ("(" . paredit-insert-paren)
                       (")" . paredit-close-parenthesis)
                       ("\"" . paredit-insert-doublequote)
                       (delete-previous-char . paredit-backward-delete)
                       ("C-Right" . paredit-slurp)
                       ("C-Left" . paredit-barf)
                       ("M-s" . paredit-splice))
      do (define-key *paredit-mode-keymap* k f))
