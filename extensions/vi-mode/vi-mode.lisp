(defpackage :lem-vi-mode
  (:use :cl
        :lem
        :lem-vi-mode/core
        :lem-vi-mode/ex)
  (:import-from :lem-vi-mode/options
                :vi-option-value)
  (:import-from :lem-vi-mode/commands/utils
                :vi-command
                :vi-command-repeat)
  (:export :vi-mode
           :define-vi-state
           :*command-keymap*
           :*insert-keymap*
           :*ex-keymap*
           :vi-option-value))
(in-package :lem-vi-mode)

(defmethod post-command-hook ((state normal))
  (let ((command (this-command)))
    (when (and (typep command 'vi-command)
               (eq (vi-command-repeat command) t))
      (setf *last-repeat-keys* (vi-this-command-keys)))))

(defmethod post-command-hook ((state insert))
  (when (eq :separator (lem-base::last-edit-history (current-buffer)))
    (vector-pop (lem-base::buffer-edit-history (current-buffer)))))

(defmethod state-disabled-hook ((state insert))
  (unless (eq :separator (lem-base::last-edit-history (current-buffer)))
    (buffer-undo-boundary)))