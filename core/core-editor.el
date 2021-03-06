;;; core-editor.el -*- lexical-binding: t; -*-

(defvar doom-large-file-size 1
  "Size (in MB) above which the user will be prompted to open the file literally
to avoid performance issues. Opening literally means that no major or minor
modes are active and the buffer is read-only.")

(defvar doom-large-file-modes-list
  '(fundamental-mode special-mode archive-mode tar-mode jka-compr
    git-commit-mode image-mode doc-view-mode doc-view-mode-maybe
    ebrowse-tree-mode pdf-view-mode)
  "Major modes that `doom|check-large-file' will ignore.")

(defvar-local doom-inhibit-indent-detection nil
  "A buffer-local flag that indicates whether `dtrt-indent' should try to detect
indentation settings or not. This should be set by editorconfig if it
successfully sets indent_style/indent_size.")

(defvar doom-detect-indentation-excluded-modes '(fundamental-mode)
  "A list of major modes in which indentation should be automatically
detected.")

(setq-default
 large-file-warning-threshold 30000000
 vc-follow-symlinks t
 ;; Save clipboard contents into kill-ring before replacing them
 save-interprogram-paste-before-kill t
 ;; Bookmarks
 bookmark-default-file (concat doom-etc-dir "bookmarks")
 bookmark-save-flag t
 ;; Formatting
 delete-trailing-lines nil
 fill-column 80
 sentence-end-double-space nil
 word-wrap t
 ;; Scrolling
 hscroll-margin 2
 hscroll-step 1
 scroll-conservatively 1001
 scroll-margin 0
 scroll-preserve-screen-position t
 ;; Whitespace (see `editorconfig')
 indent-tabs-mode nil
 require-final-newline t
 tab-always-indent t
 tab-width 4
 tabify-regexp "^\t* [ \t]+" ; for :retab
 ;; Wrapping
 truncate-lines t
 truncate-partial-width-windows 50)

;; Remove hscroll-margin in shells, otherwise it causes jumpiness
(setq-hook! '(eshell-mode-hook term-mode-hook) hscroll-margin 0)

(defun doom|check-large-file ()
  "Check if the buffer's file is large (see `doom-large-file-size'). If so, ask
for confirmation to open it literally (read-only, disabled undo and in
fundamental-mode) for performance sake."
  (when (and (not (memq major-mode doom-large-file-modes-list))
             auto-mode-alist
             (get-buffer-window))
    (when-let* ((size (nth 7 (file-attributes buffer-file-name))))
      (when (and (> size (* 1024 1024 doom-large-file-size))
                 (y-or-n-p
                  (format (concat "%s is a large file, open literally to "
                                  "avoid performance issues?")
                          (file-relative-name buffer-file-name))))
        (setq buffer-read-only t)
        (buffer-disable-undo)
        (fundamental-mode)))))
(add-hook 'find-file-hook #'doom|check-large-file)


;;
;; Built-in plugins
;;

(push '("/LICENSE\\'" . text-mode) auto-mode-alist)

(electric-indent-mode -1) ; enabled by default in Emacs 25+. No thanks.

(add-hook 'after-save-hook #'executable-make-buffer-file-executable-if-script-p)

;; revert buffers for changed files
(def-package! autorevert
  :after-call after-find-file
  :config
  (setq auto-revert-verbose nil)
  (global-auto-revert-mode +1))

;; persist variables across sessions
(def-package! savehist
  :defer 1
  :after-call post-command-hook
  :config
  (setq savehist-file (concat doom-cache-dir "savehist")
        savehist-save-minibuffer-history t
        savehist-autosave-interval nil ; save on kill only
        savehist-additional-variables '(kill-ring search-ring regexp-search-ring))
  (savehist-mode +1)

  (defun doom|unpropertize-kill-ring ()
    "Remove text properties from `kill-ring' in the interest of shrinking the
savehist file."
    (setq kill-ring (mapcar #'substring-no-properties kill-ring)))
  (add-hook 'kill-emacs-hook #'doom|unpropertize-kill-ring))

;; persistent point location in buffers
(def-package! saveplace
  :after-call (after-find-file dired-initial-position-hook)
  :config
  (setq save-place-file (concat doom-cache-dir "saveplace"))
  (defun doom*recenter-on-load-saveplace (&rest _)
    "Recenter on cursor when loading a saved place."
    (if buffer-file-name (ignore-errors (recenter))))
  (advice-add #'save-place-find-file-hook
              :after-while #'doom*recenter-on-load-saveplace)
  (save-place-mode +1))

;; Keep track of recently opened files
(def-package! recentf
  :defer 1
  :after-call after-find-file
  :commands recentf-open-files
  :config
  (setq recentf-save-file (concat doom-cache-dir "recentf")
        recentf-auto-cleanup 'never
        recentf-max-menu-items 0
        recentf-max-saved-items 300
        recentf-filename-handlers '(file-truename)
        recentf-exclude
        (list #'file-remote-p "\\.\\(?:gz\\|gif\\|svg\\|png\\|jpe?g\\)$"
              "^/tmp/" "^/ssh:" "\\.?ido\\.last$" "\\.revive$" "/TAGS$"
              "^/var/folders/.+$"
              ;; ignore private DOOM temp files (but not all of them)
              (lambda (file) (file-in-directory-p file doom-local-dir))))
  (unless noninteractive
    (add-hook 'kill-emacs-hook #'recentf-cleanup)
    (quiet! (recentf-mode +1))))

(def-package! server
  :when (display-graphic-p)
  :defer 1
  :after-call (pre-command-hook after-find-file)
  :config
  (unless (server-running-p)
    (server-start)))


;;
;; Core Plugins
;;

;; Auto-close delimiters and blocks as you type. It's more powerful than that,
;; but that is all Doom uses it for.
(def-package! smartparens
  :after-call (doom-exit-buffer-hook after-find-file)
  :commands (sp-pair sp-local-pair sp-with-modes)
  :config
  (require 'smartparens-config)
  (setq sp-highlight-pair-overlay nil
        sp-highlight-wrap-overlay nil
        sp-highlight-wrap-tag-overlay nil
        sp-show-pair-from-inside t
        sp-cancel-autoskip-on-backward-movement nil
        sp-show-pair-delay 0.1
        sp-max-pair-length 4
        sp-max-prefix-length 50
        sp-escape-quotes-after-insert nil)  ; not smart enough

  ;; Smartparens' navigation feature is neat, but does not justify how expensive
  ;; it is. It's also less useful for evil users. This may need to be
  ;; reactivated for non-evil users though. Needs more testing!
  (defun doom|disable-smartparens-navigate-skip-match ()
    (setq sp-navigate-skip-match nil
          sp-navigate-consider-sgml-tags nil))
  (add-hook 'after-change-major-mode-hook #'doom|disable-smartparens-navigate-skip-match)

  ;; autopairing in `eval-expression' and `evil-ex'
  (defun doom|init-smartparens-in-eval-expression ()
    "Enable `smartparens-mode' in the minibuffer, during `eval-expression' or
`evil-ex'."
    (when (memq this-command '(eval-expression evil-ex))
      (smartparens-mode)))
  (add-hook 'minibuffer-setup-hook #'doom|init-smartparens-in-eval-expression)
  (sp-local-pair 'minibuffer-inactive-mode "'" nil :actions nil)

  ;; smartparens breaks evil-mode's replace state
  (add-hook 'evil-replace-state-entry-hook #'turn-off-smartparens-mode)
  (add-hook 'evil-replace-state-exit-hook  #'turn-on-smartparens-mode)

  (smartparens-global-mode +1))

;; Automatic detection of indent settings
(def-package! dtrt-indent
  :unless noninteractive
  :defer t
  :init
  (defun doom|detect-indentation ()
    (unless (or (not after-init-time)
                doom-inhibit-indent-detection
                (member (substring (buffer-name) 0 1) '(" " "*"))
                (memq major-mode doom-detect-indentation-excluded-modes))
      (dtrt-indent-mode +1)))
  (add-hook! '(change-major-mode-after-body-hook read-only-mode-hook)
    #'doom|detect-indentation)
  :config
  (setq dtrt-indent-verbosity (if doom-debug-mode 2 0))
  (add-to-list 'dtrt-indent-hook-generic-mapping-list '(t tab-width)))

;; Branching undo
(def-package! undo-tree
  :after-call (doom-exit-buffer-hook after-find-file)
  :config
  (setq undo-tree-auto-save-history t
        ;; undo-in-region is known to cause undo history corruption, which can
        ;; be very destructive! Disabling it deters the error, but does not fix
        ;; it entirely!
        undo-tree-enable-undo-in-region nil
        undo-tree-history-directory-alist
        `(("." . ,(concat doom-cache-dir "undo-tree-hist/"))))
  (global-undo-tree-mode +1)

  (advice-add #'undo-tree-load-history :around #'doom*shut-up)

  ;; compress undo history with xz
  (defun doom*undo-tree-make-history-save-file-name (file)
    (cond ((executable-find "zstd") (concat file ".zst"))
          ((executable-find "gzip") (concat file ".gz"))
          (file)))
  (advice-add #'undo-tree-make-history-save-file-name :filter-return
              #'doom*undo-tree-make-history-save-file-name)

  (defun doom*strip-text-properties-from-undo-history (&rest args)
    (dolist (item buffer-undo-list)
      (and (consp item)
           (stringp (car item))
           (setcar item (substring-no-properties (car item))))))
  (advice-add 'undo-list-transfer-to-tree :before #'doom*strip-text-properties-from-undo-history)

  (defun doom*compress-undo-tree-history (orig-fn &rest args)
    (cl-letf* ((jka-compr-verbose nil)
               (old-write-region (symbol-function #'write-region))
               ((symbol-function #'write-region)
                (lambda (start end filename &optional append _visit &rest args)
                  (apply old-write-region start end filename append 0 args))))
      (apply orig-fn args)))
  (advice-add #'undo-tree-save-history :around #'doom*compress-undo-tree-history))


;;
;; Autoloaded Plugins
;;

;; `command-log-mode'
(setq command-log-mode-auto-show t
      command-log-mode-open-log-turns-on-mode t)

(def-package! expand-region
  :commands (er/contract-region er/mark-symbol er/mark-word)
  :config
  (defun doom*quit-expand-region ()
    "Properly abort an expand-region region."
    (when (memq last-command '(er/expand-region er/contract-region))
      (er/contract-region 0)))
  (advice-add #'evil-escape :before #'doom*quit-expand-region)
  (advice-add #'doom/escape :before #'doom*quit-expand-region))

;; A better *help* buffer
(def-package! helpful
  :defer t
  :init
  (setq counsel-describe-function-function #'helpful-callable
        counsel-describe-variable-function #'helpful-variable)

  (define-key! 'global
    [remap describe-function] #'helpful-callable
    [remap describe-command]  #'helpful-command
    [remap describe-variable] #'helpful-variable
    [remap describe-key]      #'helpful-key))

(provide 'core-editor)
;;; core-editor.el ends here
