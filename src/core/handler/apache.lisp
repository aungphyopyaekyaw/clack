#|
  This file is a part of Clack package.
  URL: http://github.com/fukamachi/clack
  Copyright (c) 2011 Eitarow Fukamachi <e.arrows@gmail.com>

  Clack is freely distributable under the LLGPL License.
|#

(clack.util:namespace clack.handler.apache
  (:use :cl
        :modlisp
        :metabang-bind
        :split-sequence
        :anaphora)
  (:import-from :clack.component :call)
  (:import-from :clack.util.hunchentoot
                :url-decode))

(cl-annot:enable-annot-syntax)

@export
(defun run (app &key debug (port 3000))
  "Start talking to mod_lisp process."
  @ignore debug
  (ml:modlisp-start :port port
                    :processor 'clack-request-dispatcher
                    :processor-args (list app)))

@export
(defun stop (server)
  "Close socket to talk with mod_lisp.
If no server given, try to stop `*server*' by default."
  (ml:modlisp-stop server))

(defun clack-request-dispatcher (command app)
  "Apache(mod_lisp) request dispatcher for Clack. Process modlisp command alist.
This is called on each request."
  (handler-bind ((error #'invoke-debugger))
    (handle-response (call app (command->plist command)))))

(defun command->plist (command)
  (bind ((url (ml:header-value command :url))
         (pos (position #\? url))
         ((server-name server-port)
          (split-sequence #\: (ml:header-value command :host))))
    (append
     (list
      :request-method (ml:header-value command :method)
      :script-name ""
      :path-info (awhen (subseq url 0 pos)
                   (url-decode it))
      :query-string (subseq url (1+ (or pos 0)))
      :raw-body (awhen (ml:header-value command :posted-content)
                  (flex:make-flexi-stream
                   (flex:make-in-memory-input-stream
                    (flex:string-to-octets it))
                   :external-format :utf-8))
      :content-length (parse-integer (ml:header-value command :content-length)
                                     :junk-allowed t)
      :content-type (ml:header-value command :content-type)
      :server-name server-name
      :server-port (parse-integer server-port :junk-allowed t)
      :server-protocol (ml:header-value command :server-protocol)
      :request-uri url
      ;; FIXME: always return :http
      :url-scheme :http
      :remote-addr (ml:header-value command :remote-ip-addr)
      :remote-port (ml:header-value command :remote-ip-port)
;      :http-user-agent (ml:header-value command :user-agent)
;      :http-referer (ml:header-value command :referer)
;      :http-host (ml:header-value command :host)
;      :http-cookies (ml:header-value command :cookie)
      :http-server :modlisp)

     ;; NOTE: this code almost same thing of Clack.Handler.Hunchentoot's
     (loop for (k . v) in command
           unless (member k '(:request-method :script-name :path-info :server-name :server-port :server-protocol :request-uri :remote-addr :remote-port :query-string :content-length :content-type :accept :connection))
             append (list (intern (concatenate 'string "HTTP-" (string-upcase k)) :keyword) v)))))

(defun handle-response (res)
  "Function for managing response. Take response and output it to `ml:*modlisp-socket*'."
  (bind (((status headers body) res)
         (keep-alive-p (getf headers :content-length)))
    (setf (getf headers :status) (write-to-string status))
    (when keep-alive-p
      (setf (getf headers :keep-socket) "1"
            (getf headers :connection) "Keep-Alive"))

    ;; NOTE: This almost same of Clack.Handler.Hunchentoot's.
    ;; Convert plist to alist and make sure the values are strings.
    (setf headers
          (loop for (k v) on headers by #'cddr
                with hash = (make-hash-table :test #'eq)
                if (gethash k hash)
                  do (setf (gethash k hash)
                           (format nil "~:[~;~:*~A, ~]~A" (gethash k hash) v))
                else do (setf (gethash k hash) v)
                finally
             (return (loop for k being the hash-keys in hash
                           using (hash-value v)
                           if v
                             collect (cons k (format nil "~A" v))))))

    (etypecase body
      (pathname
       (with-open-file (file body
                             :direction :input
                             :element-type '(unsigned-byte 8)
                             :if-does-not-exist nil)
         (ml::write-response (:headers headers
                              :len (format nil "~A" (file-length file)))
          (loop with buf = (make-array 1024 :element-type '(unsigned-byte 8))
                for pos = (read-sequence buf file)
                until (zerop pos)
                do (write-sequence buf ml:*modlisp-socket* :end pos)))))
      (list
       (ml::write-response (:headers headers)
        (write-sequence (flex:string-to-octets
                         (format nil "~{~A~^~%~}" body)
                         :external-format :utf-8)
         ml:*modlisp-socket*))))))

(doc:start)

@doc:NAME "
Clack.Handler.Apache - Clack handler for Apache2 + mod_lisp.
"

@doc:DESCRIPTION "
Clack.Handler.Apache is a Clack handler for Apache2 + mod_lisp.

This is not maintained well. Sorry.
"

@doc:AUTHOR "
Eitarow Fukamachi (e.arrows@gmail.com)
"
