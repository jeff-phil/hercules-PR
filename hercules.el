;;; hercules.el --- An auto-magical, `which-key'-based `hydra' banisher. -*- lexical-binding: t; -*-

;; Copyright (C) 2019 Uros Perisic

;; Author: Uros Perisic
;; URL: https://gitlab.com/jjzmajic/hercules
;;
;; Version: 0.1
;; Keywords: faces
;; Package-Requires: ((emacs "24.4") (which-key "3.0.0"))

;; This program is free software: you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free Software
;; Foundation, either version 3 of the License, or (at your option) any later
;; version.

;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
;; details.

;; You should have received a copy of the GNU General Public License along with
;; this program. If not, see <http://www.gnu.org/licenses/>.

;; This file is not part of Emacs.

;;; Commentary:
;; An auto-magical, `which-key'-based `hydra' banisher.

;; In at most 7 lines of set-up code, `hercules' lets you
;; call any group of related command sequentially with no prefix keys,
;; while showing a handy popup to remember the bindings for those
;; commands.  It can create both of these (the grouped commands, and
;; the popup) from any keymap.

;;; Code:
(require 'which-key)

(declare-function hercules--hide-popup-backup load-file-name)
(defalias #'hercules--hide-popup-backup
  (indirect-function #'which-key--hide-popup))

(defun hercules--disable ()
  "Re-enable `which-key--hide-popup'.
Add it to `pre-command-hook', and restore its original function
definition."
  (add-hook 'pre-command-hook #'which-key--hide-popup)
  (defalias #'which-key--hide-popup
    #'hercules--hide-popup-backup))

(defun hercules--enable ()
  "Disable `which-key--hide-popup'.
Remove it from `pre-command-hook', and set its function
definition to `ignore'.  This is necessary as `which-key' calls
`which-key--hide-popup' in several internal calls that cannot be
disabled."
  (remove-hook 'pre-command-hook #'which-key--hide-popup)
  ;; Called from helper functions I cannot disable.
  ;; Necessary for now.
  (defalias #'which-key--hide-popup
    #'ignore))

(defun hercules--hide (&rest _)
  "Hide `hercules'."
  (hercules--disable)
  (which-key--hide-popup))

(defun hercules--show (keymap &rest _)
  "Show `hercules' showing KEYMAP."
  (hercules--enable)
  (when keymap (which-key-show-keymap keymap)))

(defun hercules--toggle (keymap &rest _)
  "Toggle `hercules' showing KEYMAP."
  (if (which-key--popup-showing-p)
      (hercules--hide)
    (hercules--show keymap)))

(defun hercules---enlist (exp)
  "Return EXP wrapped in a list, or as-is if already a list."
  (declare (pure t) (side-effect-free t))
  (if (listp exp) exp (list exp)))

(defun hercules--show-funs (funs &optional keymap)
  "Show `hercules' showing KEYMAP when FUNS are called."
  (cl-loop for fun in (hercules---enlist funs) do
            (advice-add fun :after
                        (apply-partially
                        #'hercules--show keymap))))

(defun hercules--hide-funs (funs)
  "Hide `hercules' when FUNS are called."
  (cl-loop for fun in (hercules---enlist funs) do
            (advice-add fun :after
                        #'hercules--hide)))

(defun hercules--toggle-funs (funs &optional keymap)
  "Toggle `hercules' with KEYMAP when FUNS are called."
  (cl-loop for fun in (hercules---enlist funs) do
           (advice-add fun :after
                       (apply-partially
                        #'hercules--toggle keymap))))

;;;###autoload
(cl-defmacro hercules-def (&key toggle-funs
                                show-funs
                                hide-funs
                                keymap
                                pseudo-mode
                                pseudo-mode-fun)
  "
Summon `hercules' to banish your `hydra's.

In at most 7 lines of set-up code, `hercules' lets you call any
group of related command sequentially with no prefix keys, while
showing a handy popup to remember the bindings for those
commands. He can create both of these (the grouped commands, and
the popup) from any keymap.

The following arguments define entry and exit point functions
that invoke `hercules' (both lists and single functions work):

- TOGGLE-FUNS :: Processed with `hercules--toggle-funs'.
- SHOW-FUNS :: Processed with `hercules--show-funs'.
- HIDE-FUNS :: Processed with `hercules--hide-funs'.

Now to the slightly less obvious options:

- KEYMAP :: The keymap to display in `hercules'. If it is nil, it is
  assumed that the function you are calling will result in a
  `which-key--show-popup' call. This might be desirable if you wish to
  enable `hercules' for `which-key-show-top-level' or something
  similar. For example, this is what I have in my config so I can
  scroll to the `which-key' page of interest when I'm dealing with
  some fringe Evil commands I kind of forgot. Then I keep it around
  until I feel comfortable enough to kill it with
  `keyboard-quit'. This has the side effect of killing all `hercules's
  on `keyboard-quit', but then again all commands are supposed to obey
  it.
  
 #+BEGIN_SRC emacs-lisp :tangle yes
   (hercules-def
    :show-funs '(which-key-show-top-level)
    :hide-funs '(keyboard-quit keyboard-escape-quit))
 #+END_SRC 

- PSEUDO-MODE :: Whether to create a pseudo-mode by setting a
  KEYMAP as an overriding transient map. This is handy if the
  function you are summoning `hercules' with isn't actually a
  mode, or is fighting for keybindings with other
  minor-modes. The keymap stops taking precedence over other
  keymaps once a key outside of it is pressed. See
  `set-transient-map' for details. To take advantage of this
  capability, it isn't enough to call `hercules-def'. You should
  bind its return value (a symbol) to the key you plan to use to
  enter the PSEUDO-MODE. E.g.:

#+BEGIN_SRC emacs-lisp
  (my:elisp::general-def
    \"m\" '(:ignore t :wk \"macrostep\")
    \"m.\" (hercules-def
          :toggle-funs '(macrostep-mode)
          :keymap 'macrostep-keymap
          :pseudo-mode t
          :pseudo-mode-fun #'macrostep-mode)
    \"me\" #'macrostep-expand
    \"mc\" #'macrostep-collapse
    \"mn\" #'macrostep-next-macro
    \"mp\" #'macrostep-prev-macro)
#+END_SRC
 
- PSEUDO-MODE-FUN :: The command to call when entering
  PSEUDO-MODE.  You can omit it if you just want to summon
  `hercules' without actually doing anything right away.
"
  (let ((keymap-symbol (eval keymap)))
    (hercules--show-funs (eval show-funs) keymap-symbol)
    (hercules--hide-funs (eval hide-funs))
    (hercules--toggle-funs (eval toggle-funs))
    (when pseudo-mode
      (let* ((keymap-name (symbol-name keymap-symbol))
              (func-symbol (intern
                            (format "hercules-%s-pseudo-mode"
                                    keymap-name)))
              (func-doc (format
                        (concat "Pseudo-mode for %s.\n"
                                "Defined by `hercules-def'.")
                                keymap-name)))
        (hercules--show-funs `(,func-symbol) keymap-symbol)
        `(progn
            (defun ,func-symbol ()
              ,func-doc
              (interactive)
              ,(when pseudo-mode-fun
                 `(,(eval pseudo-mode-fun)))
              (set-transient-map ,keymap-symbol t #'hercules--hide))
            ',func-symbol)))))

(provide 'hercules)
;;; hercules.el ends here