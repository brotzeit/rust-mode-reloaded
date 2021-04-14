;; -*- lexical-binding: t -*-
;; Before editing, eval (load-file "test-helper.el")

(ert-deftest rustic-test-format-buffer ()
  (let ((string "fn main()      {}")
        (formatted-string "fn main() {}\n")
        (buf (get-buffer-create "test"))
        (buffer-read-only nil))
    (with-current-buffer buf
      (erase-buffer)
      (rustic-mode)
      (insert string)
      (backward-char 10)
      (let ((proc (rustic-format-start-process
                   'rustic-format-sentinel
                   :buffer (current-buffer)
                   :stdin (buffer-string))))
        (while (eq (process-status proc) 'run)
          (sit-for 0.1)))
      (should (string= (buffer-string) formatted-string))
      (should-not (= (point) (or (point-min) (point-max)))))
    (kill-buffer buf)))

(ert-deftest rustic-test-format-buffer-failure ()
  (let ((string "fn main()      {}")
        (string-dummy "can't format this string")
        (buf (get-buffer-create "test"))
        (buffer-read-only nil))
    (kill-buffer rustic-format-buffer-name)
    (with-current-buffer buf
      (erase-buffer)
      (insert string)
      ;; no rustic-mode buffer
      (should-error (rustic-format-buffer))
      (should-not (get-buffer rustic-format-buffer-name))
      (erase-buffer)
      (rustic-mode)
      (insert string-dummy)
      (let* ((proc (rustic-format-start-process
                    'rustic-format-sentinel
                    :buffer (current-buffer)
                    :stdin (buffer-string)))
             (buf (process-buffer proc)))
        (with-current-buffer buf
          ;; check if buffer has correct name and correct major mode
          (should (string= (buffer-name buf) rustic-format-buffer-name))
          (should (eq major-mode 'rustic-format-mode)))))
    (kill-buffer buf)))

(ert-deftest rustic-test-format-file ()
  (let* ((string "fn main()      {}")
         (formatted-string "fn main() {}\n")
         (dir (rustic-babel-generate-project t))
         (main (expand-file-name "main.rs" (concat dir "/src")))
         (buf (get-buffer-create "test")))
    (with-current-buffer buf (write-file main))
    (write-region string nil main nil 0)
    (let ((proc (rustic-format-start-process
                 'rustic-format-file-sentinel
                 :buffer buf
                 :files main)))
      (while (eq (process-status proc) 'run)
        (sit-for 0.1)))
    (with-temp-buffer
      (insert-file-contents main)
      (should (string= (buffer-string) formatted-string)))
    (should-error (rustic-format-start-process
                   'rustic-format-file-sentinel
                   :buffer "dummy"
                   :files "/tmp/nofile"))))

(ert-deftest rustic-test-format-file-with-tabs ()
  (let* ((string "fn main()      {()}")
         (formatted-string "fn main() {\n\t()\n}\n")
         (rustic-rustfmt-config-alist '((hard_tabs . t)))
         (dir (rustic-babel-generate-project t))
         (main (expand-file-name "main.rs" (concat dir "/src")))
         (buf (get-buffer-create "test")))
    (with-current-buffer buf (write-file main))
    (write-region string nil main nil 0)
    (let ((proc (rustic-format-start-process
                 'rustic-format-file-sentinel
                 :buffer buf
                 :files main)))
      (while (eq (process-status proc) 'run)
        (sit-for 0.1)))
    (with-temp-buffer
      (insert-file-contents main)
      (should (string= (buffer-string) formatted-string)))))

(ert-deftest rustic-test-format-file-old-syntax ()
  (let* ((string "fn main()      {}")
         (formatted-string "fn main() {}\n")
         (dir (rustic-babel-generate-project t))
         (main (expand-file-name "main.rs" (concat dir "/src")))
         (buf (get-buffer-create "test")))
    (with-current-buffer buf (write-file main))
    (write-region string nil main nil 0)
    (let ((proc (rustic-format-start-process
                 'rustic-format-file-sentinel
                 :buffer buf
                 :command `(,rustic-rustfmt-bin ,main))))
      (while (eq (process-status proc) 'run)
        (sit-for 0.1)))
    (with-temp-buffer
      (insert-file-contents main)
      (should (string= (buffer-string) formatted-string)))))

(ert-deftest rustic-test-format-multiple-files ()
  (let* ((string "fn main()      {}")
         (formatted-string "fn main() {}\n")
         (dir (rustic-babel-generate-project t))
         (f-one (expand-file-name "one.rs" (concat dir "/src")))
         (f-two (expand-file-name "two.rs" (concat dir "/src")))
         (buf (get-buffer-create "test")))
    (with-current-buffer buf (write-file f-one) (write-file f-two))
    (write-region string nil f-one nil 0)
    (write-region string nil f-two nil 0)
    (let ((proc (rustic-format-start-process
                 'rustic-format-file-sentinel
                 :buffer buf
                 :files (list f-one f-two))))
      (while (eq (process-status proc) 'run)
        (sit-for 0.1)))
    (with-temp-buffer
      (insert-file-contents f-one)
      (should (string= (buffer-string) formatted-string)))
    (with-temp-buffer
      (insert-file-contents f-two)
      (should (string= (buffer-string) formatted-string)))))

(ert-deftest rustic-test-format-buffer-before-save ()
  (let* ((string "fn main()      {}")
         (formatted-string "fn main() {}\n")
         (buf (get-buffer-create "test-save"))
         (default-directory org-babel-temporary-directory)
         (file (progn (shell-command-to-string "touch test.rs")
                      (expand-file-name "test.rs")))
         (buffer-read-only nil))
    (let ((rustic-format-trigger 'on-save))
      (with-current-buffer buf
        (write-file file)
        (erase-buffer)
        (rustic-mode)
        (insert string)
        (backward-char 10)
        (save-buffer)
        (if-let ((proc (get-process rustic-format-process-name)))
            (while (eq (process-status proc) 'run)
              (sit-for 0.01)))
        (should (string= (buffer-string) formatted-string))
        (should-not (= (point) (or (point-min) (point-max))))))
    (let ((buf (get-buffer-create "test-save-no-format"))
          (file (progn (shell-command-to-string "touch test-no-format.rs")
                       (expand-file-name "test-no-format.rs")))
          (rustic-format-trigger nil))
      (with-current-buffer buf
        (write-file file)
        (erase-buffer)
        (rustic-mode)
        (insert string)
        (save-buffer)
        (should (string= (buffer-string) (concat string "\n")))))
    (kill-buffer buf)))

(ert-deftest rustic-test-cargo-format ()
  (let* ((buffer1 (get-buffer-create "b1"))
         (string "fn main()      {}")
         (formatted-string "fn main() {}\n")
         (dir (rustic-babel-generate-project t)))
    (let* ((default-directory dir)
           (src (concat dir "/src"))
           (file1 (expand-file-name "main.rs" src))
           (rustic-format-trigger nil))
      (with-current-buffer buffer1
        (insert string)
        (write-file file1))

      ;; run 'cargo fmt'
      (call-interactively 'rustic-cargo-fmt)
      (if-let ((proc (get-process rustic-format-process-name)))
          (while (eq (process-status proc) 'run)
            (sit-for 0.01)))
      (with-current-buffer buffer1
        (should (string= (buffer-string) formatted-string))))
    (kill-buffer buffer1)))

;; `rustic-format-trigger' is set to 'on-compile
(ert-deftest rustic-test-trigger-format-on-compile ()
  (let* ((buffer1 (get-buffer-create "b1"))
         (string "fn main()      {}")
         (formatted-string "fn main() {}\n")
         (dir (rustic-babel-generate-project t))
         (compilation-read-command nil))
    (let* ((default-directory dir)
           (src (concat dir "/src"))
           (file1 (expand-file-name "main.rs" src))
           (rustic-format-trigger 'on-compile))
      (with-current-buffer buffer1
        (insert string)
        (write-file file1))

      ;; run `rustic-compile'
      (if-let ((proc (call-interactively 'rustic-compile)))
          (while (eq (process-status proc) 'run)
            (sit-for 0.01)))
      (with-current-buffer buffer1
        (revert-buffer t t)
        (should (string= (buffer-string) formatted-string)))
      (kill-buffer buffer1))))
