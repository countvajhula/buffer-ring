;;; buffer-ring.el --- A torus for buffer navigation. A ring of buffers, and a ring of buffer rings. -*- lexical-binding: t -*-

;; Copyright (C) 2009 Mike Mattie
;; Author: Mike Mattie codermattie@gmail.com
;; Maintainer: Mike Mattie codermattie@gmail.com
;; Created: 2009-4-16
;; Version: 0.1.0
;; Package-Requires: ((dynamic-ring "0.0.2"))

;; This file is NOT a part of Gnu Emacs.

;; License: GPL-v3

;; buffer-ring.el is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(defconst buffer-ring-version "0.1.1" "buffer-ring version")
(require 'dynamic-ring)

;;
;; default keymap
;;

(global-set-key (kbd "C-c C-b b") 'buffer-ring-list-buffers)
(global-set-key (kbd "C-c C-b r") 'buffer-torus-list-rings)

(global-set-key (kbd "C-c C-b a") 'buffer-ring-add)
(global-set-key (kbd "C-c C-b d") 'buffer-ring-delete)

(global-set-key (kbd "C-c C-b f") 'buffer-ring-next-buffer)
(global-set-key (kbd "C-c C-b b") 'buffer-ring-prev-buffer)

(global-set-key (kbd "C-c C-b n") 'buffer-torus-next-ring)
(global-set-key (kbd "C-c C-b p") 'buffer-torus-prev-ring)
(global-set-key (kbd "C-c C-b e") 'buffer-torus-delete-ring)

(defvar buffer-ring-torus (make-dyn-ring)
  "a global ring of all the buffer rings. A torus I believe.")

(defvar buffer-ring-default nil
  "The default buffer ring")

;;
;;  buffer rings registry
;;

;; a hash mapping names of buffer rings to the ring structures
(defvar buffer-rings
  (ht))

;; this being "flat" means that ring names are global rather than
;; torus-specific.
;; we could just prefix a coordinate in the insertion function
;; so don't worry about this for now

(defun bfr-register-ring (name ring)
  "Register a newly created buffer RING under NAME."
  (ht-set! buffer-rings name ring))

(defun bfr-lookup-ring (name)
  "Lookup a ring by NAME."
  (ht-get buffer-rings name))

;;
;;  buffer torus functions.
;;

(defun bfr-torus--create-ring (name)
  "Create ring with name NAME."
  (let ((ring (make-dyn-ring)))
    (dyn-ring-insert buffer-ring-torus ring)
    (bfr-register-ring name ring)
    ring))

(defun bfr-torus-get-ring (name)
  "bfr-torus-get-ring NAME

   Find a existing buffer ring, or create a new buffer ring with name.
   buffer-ring-default is updated. The buffer-ring is returned.
  "
  (let ((ring (dyn-ring-find-forwards
               (bfr-lookup-ring name))))
    (if ring
        (progn
          (message "Adding to existing ring: %s" name)
          ring)
      (message "Creating a new ring \"%s\"" name)
      (bfr-torus--create-ring name))))

(defun bfr-torus-switch-to-ring (name)
  "Switch to ring NAME."
  (interactive)
  (let ((ring (bfr-lookup-ring name)))
    (when ring
      (dyn-ring-break-insert buffer-ring-torus ring)
      (switch-to-buffer
       (dyn-ring-value ring)))))

;;
;; buffer ring functions
;;

(defun bfr-ring-jump-to-buffer ()
  "If a buffer is visited directly without rotating
   to it, it should modify the ring structure so that
   recency is accounted for correctly."
  ;; TODO: add this to the buffer visited hook
  ;; if ∈ current ring, break-and-insert
  ;; elif ∈ some ring R, switch to one of them
  ;;   this should itself be a ring of rings, but just
  ;;   use a list for now
  ;; else do nothing - we retain our position in the
  ;; active buffer ring, and any buffer-ring operations
  ;; would assume the current buffer doesn't even exist
  ;; or rather, would assume that we are currently at head
  (dyn-ring-break-insert (bfr-current-ring)
                         (current-buffer)))

(defun bfr-ring-size ()
  "bfr-ring-size

   Returns the number of buffers in the current ring.
   If there is no active buffer ring, it returns -1 so that
   you can always use a numeric operator.
  "
  (let ((ring (bfr-current-ring)))
    (if ring
        (dyn-ring-size ring)
      -1)))

;;
;; buffer ring interface
;;

(defun buffer-ring-add (ring-name)
  "buffer-ring-add RING-NAME

   Add the current buffer to a ring. It will prompt for the ring
   to add the buffer to.
  "
  (interactive "sAdd to ring ? ")
  (let ((ring (bfr-torus-get-ring ring-name))
        (buffer (current-buffer)))
    (cond ((dyn-ring-contains-p ring buffer)
           (message "buffer %s is already in ring \"%s\"" (buffer-name)
                    ring-name)
           nil)
          (t (dyn-ring-insert ring buffer)
             ;; revisit - looks buffer-local, but is it?
             (add-hook 'kill-buffer-hook 'buffer-ring-delete t t)
             t))))

(defun buffer-ring-delete ()
  "buffer-ring-delete

   Delete the current buffer from the current ring.
   This modifies the ring, it does not kill the buffer.
  "
  (interactive)
  (let ((ring (bfr-current-ring))
        (buffer (current-buffer)))
    (if (dyn-ring-delete ring buffer)
        ;; TODO: if called as part of kill buffer, this needs
        ;; to delete the buffer from all rings - so that should
        ;; actually be a separate function, buffer-ring-drop-buffer
        ;; and we don't need to unhook it here
        (remove-hook 'kill-buffer-hook 'buffer-ring-delete t)
      (message "This buffer is not in the current ring"))))

(defun buffer-ring-list-buffers ()
  "buffer-ring-list-buffers

   List the buffers in the current buffer ring.
  "
  (interactive)
  (let ((ring (bfr-current-ring)))
    (if ring
        (let ((result (dyn-ring-traverse-collect ring #'buffer-name)))
          (if result
              (message "buffers in [%s]: %s" "TODO:ring-name" result)
            (message "Buffer ring is empty.")))
      (message "No active buffer ring."))) )

;; TODO: standardize interface names
(defun bfr-ring--rotate (direction)
  (let ((ring (bfr-current-ring)))
    (if (< (dyn-ring-size ring) 2)
        (message "There is only one buffer in the ring.")
      (progn
        (funcall direction buffer-ring)
        (switch-to-buffer (dyn-ring-value ring))))))

(defun buffer-ring-prev-buffer ()
  "buffer-ring-prev-buffer

   Switch to the previous buffer in the buffer ring.
  "
  (interactive)
  (bfr-ring--rotate #'dyn-ring-rotate-left))

(defun buffer-ring-next-buffer ()
  "buffer-ring-next-buffer

   Switch to the previous buffer in the buffer ring.
  "
  (interactive)
  (bfr-ring--rotate #'dyn-ring-rotate-right))

;;
;; buffer torus interface
;;

(defun bfr-current-name ()
  (car (dyn-ring-value buffer-ring-torus)))

;; TODO: decide on reference ordering, i.e. how do we get the current ring?
;; is it by consulting the torus? Or is it the other way around, that the
;; torus is found by starting at the current ring and going outward?
;; If we are going to assume a single torus, we can leave it as is for now
;; otherwise, we must address the possibility of more than one torus
;; containing the current ring
;; -> just consult "the" torus for now
(defun bfr-current-ring ()
  (dyn-ring-value buffer-ring-torus))

(defun bfr-rotate-buffer-torus ( direction )
  (if (< (dyn-ring-size buffer-ring-torus) 2)
    (message "There is only one buffer ring; ignoring the rotate global ring command")
    ;; rotate past any empties
    (if (dyn-ring-rotate-until buffer-ring-torus
                               direction
                               (lambda (ring)
                                 (not (dyn-ring-empty-p ring))))
      (progn
        (message "switching to ring %s" "TODO:ring-name")
        (switch-to-buffer
         (dyn-ring-value (bfr-current-ring))))
      (message "All of the buffer rings are empty. Keeping the current ring position")) ))

(defun buffer-torus-next-ring ()
  "buffer-torus-next-ring

   Switch to the previous buffer in the buffer ring.
  "
  (interactive)
  (bfr-rotate-buffer-torus 'dyn-ring-rotate-right))

(defun buffer-torus-prev-ring ()
  "buffer-torus-prev-ring

   Switch to the previous buffer in the buffer ring.
  "
  (interactive)
  (bfr-rotate-buffer-torus 'dyn-ring-rotate-left))

;; TODO: continue from here
(defun buffer-torus-list-rings ()
  "buffer-torus-list-rings.

   List the buffer rings in the buffer torus.
  "
  (interactive)

  (let
    ((ring-list nil))

    (mapc
      (lambda ( name )
        (setq ring-list
          (if ring-list
            (concat name "," ring-list)
            name)))
      (dyn-ring-traverse-collect buffer-ring-torus 'bfr-ring-name))

    (message "buffer rings: %s" ring-list) ))

(defun buffer-torus-delete-ring ()
  "buffer-torus-delete-ring

   Delete the entire current buffer-ring.
  "
  (interactive)

  (save-excursion
    (mapc
      (lambda ( buffer-name )
        (with-current-buffer buffer-name
          (buffer-ring-delete)))

      (dyn-ring-traverse-collect (bfr-current-ring)
                                 #'bfr-find-buffer-for-id))
    (dyn-ring-delete buffer-ring-torus (car buffer-ring-torus)) ))

(provide 'buffer-ring)
;;; buffer-ring.el ends here
