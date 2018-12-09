;;;; vex.lisp

(in-package #:vex)

(defmacro local-idiom (symbol)
  "Shorthand macro to output the name of a Vex idiom in the local package."
  (intern (format nil "*~a-IDIOM*" (string-upcase symbol))))

;; The idiom object defines a vector language instance with a persistent state.
(defclass idiom ()
  ((name :accessor idiom-name
    	 :initarg :name)
   (state :accessor idiom-state
	  :initarg :state)
   (base-state :accessor idiom-base-state
	       :initarg :state)
   (default-state :accessor idiom-default-state
                  :initarg :state)
   (utilities :accessor idiom-utilities
	      :initarg :utilities)
   (lexicons :accessor idiom-lexicons
	     :initform nil
	     :initarg :lexicons)
   (functions :accessor idiom-functions
	      :initform nil
	      :initarg :functions)
   (operators :accessor idiom-operators
	      :initform nil
	      :initarg :operators)
   (grammar-elements :accessor idiom-grammar-elements
		     :initform (make-hash-table :test #'eq)
		     :initarg :grammar-elements)
   (composer-opening-patterns :accessor idiom-composer-opening-patterns
			      :initform nil
			      :initarg :composer-opening-patterns)
   (composer-following-patterns :accessor idiom-composer-following-patterns
				:initform nil
				:initarg :composer-following-patterns)))

(defgeneric of-state (idiom property))
(defmethod of-state ((idiom idiom) property)
  "Retrieve a property of the idiom state."
  (getf (idiom-state idiom) property))

(defgeneric of-utilities (idiom utility))
(defmethod of-utilities ((idiom idiom) utility)
  "Retrieve one of the idiom's utilities used for parsing and language processing."
  (getf (idiom-utilities idiom) utility))

(defgeneric of-functions (idiom key type))
(defmethod of-functions ((idiom idiom) key type)
  "Retrive one of the idiom's functions."
  (gethash key (getf (idiom-functions idiom) type)))

(defgeneric of-operators (idiom key type))
(defmethod of-operators ((idiom idiom) key type)
  "Retrive one of the idiom's operators."
  (gethash key (getf (idiom-operators idiom) type)))

(defgeneric of-lexicon (idiom lexicon glyph))
(defmethod of-lexicon (idiom lexicon glyph)
  "Check whether a character belongs to a given Vex lexicon."
  (member glyph (getf (idiom-lexicons idiom) lexicon)))

(defmacro boolean-op (operation)
  "Wrap a boolean operation for use in a vector language, converting the t or nil it returns to 1 or 0."
  `(lambda (omega &optional alpha)
     (let ((outcome (funcall (function ,operation) alpha omega)))
       (if outcome 1 0))))

(defmacro reverse-op (is-dyadic &optional operation)
  "Wrap a function so as to reverse the arguments passed to it, so (- 5 10) will result in 5."
  (let ((is-dyadic (if operation is-dyadic))
	(operation (if operation operation is-dyadic)))
    `(lambda (omega &optional alpha)
       ,(if is-dyadic `(funcall (function ,operation) alpha omega)
	    `(if alpha (funcall (function ,operation) alpha omega)
		 (funcall (function ,operation) omega))))))


(defun process-lex-tests-for (symbol operator)
  "Process a set of tests for Vex functions or operators."
  (let* ((tests (rest (assoc (intern "TESTS" (package-name *package*))
			     (rest operator))))
	 (props (rest (assoc (intern "HAS" (package-name *package*))
			     (rest operator))))
	 (heading (format nil "[~a] ~a~a~%"
			  (first operator)
			  (if (getf props :title)
			      (getf props :title)
			      (if (getf props :titles)
				  (first (getf props :titles))))
			  (if (getf props :titles)
			      (concatenate 'string " / " (second (getf props :titles)))
			      ""))))
    (labels ((for-tests (tests &optional output)
	       (if tests (for-tests (rest tests)
				    (append output (list `(princ (format nil "  _ ~a" ,(cadr (first tests))))
							 (cond ((eql 'is (caar tests))
								`(is (,(intern (string-upcase symbol)
									       (package-name *package*))
								       ,(cadar tests))
								     ,(third (first tests))
								     :test #'equalp))))))
		   output)))
      (if tests (append `((princ ,heading))
			(for-tests tests)
			`((princ (format nil "~%"))))))))

(defun process-general-tests-for (symbol test-set)
  "Process specs for general tests not associated with a specific function or operator."
  `((princ ,(first test-set))
    (princ (format nil "~%  _ ~a" ,(second test-set)))
    (is (,(intern (string-upcase symbol) (package-name *package*))
	  ,(second test-set))
	,(third test-set)
	:test #'equalp)))

(defmacro vex-spec (symbol &rest subspecs)
  "Process the specification for a vector language and build functions that generate the code tree."
  (macrolet ((of-subspec (symbol-string)
	       `(rest (assoc (intern ,(string-upcase symbol-string) (package-name *package*))
			     subspecs)))
	     (build-lexicon () `(loop for lexicon in (getf (rest this-lex) :lexicons)
				   do (if (not (getf lexicon-data lexicon))
					  (setf (getf lexicon-data lexicon) nil))
				     (if (not (member glyph-char (getf lexicon-data lexicon)))
					 (setf (getf lexicon-data lexicon)
					       (cons glyph-char (getf lexicon-data lexicon)))))))
    (let* ((idiom-symbol (intern (format nil "*~a-IDIOM*" (string-upcase symbol))
				 (package-name *package*)))
	   (lexicon-data nil)
	   (lexicon-processor (getf (of-subspec utilities) :process-lexicon-macro))
	   (function-specs (loop :for spec :in (of-subspec functions)
			      :append (let* ((glyph-char (character (first spec)))
					     (this-lex (macroexpand (list (second lexicon-processor)
									  :functions glyph-char (third spec)))))
					(build-lexicon)
					`(,@(if (getf (getf (rest this-lex) :functions) :monadic)
						`((gethash ,glyph-char (getf fn-specs :monadic))
						  ',(getf (getf (rest this-lex) :functions) :monadic)))
					    ,@(if (getf (getf (rest this-lex) :functions) :dyadic)
						  `((gethash ,glyph-char (getf fn-specs :dyadic))
						    ',(getf (getf (rest this-lex) :functions) :dyadic)))
					    ,@(if (getf (getf (rest this-lex) :functions) :symbolic)
						  `((gethash ,glyph-char (getf fn-specs :symbolic))
						    ',(getf (getf (rest this-lex) :functions) :symbolic)))))))
	   (operator-specs (loop :for spec :in (of-subspec operators)
			      :append (let* ((glyph-char (character (first spec)))
					     (this-lex (macroexpand (list (second lexicon-processor)
									  :operators glyph-char (third spec)))))
					(build-lexicon)
					(if (member :lateral-operators (getf (rest this-lex) :lexicons))
					    `((gethash ,glyph-char (getf op-specs :lateral))
					      ,(getf (rest this-lex) :operators))
					    (if (member :pivotal-operators (getf (rest this-lex) :lexicons))
						`((gethash ,glyph-char (getf op-specs :pivotal))
						  ,(getf (rest this-lex) :operators)))))))
	   (function-tests (loop :for function :in (of-subspec functions)
			      :append (process-lex-tests-for symbol function)))
	   (operator-tests (loop :for operator :in (of-subspec operators)
			      :append (process-lex-tests-for symbol operator)))
	   (general-tests (loop :for test-set :in (of-subspec general-tests)
			     :append (process-general-tests-for symbol (rest test-set)))))
      (let* ((grammar-specs (of-subspec grammar))
	     (utility-specs (of-subspec utilities))
	     (pattern-settings `((idiom-composer-opening-patterns ,idiom-symbol)
				 (append ,@(loop :for pset :in (rest (assoc :opening-patterns grammar-specs))
					      :collect `(funcall (function ,pset) ,idiom-symbol)))
				 (idiom-composer-following-patterns ,idiom-symbol)
				 (append ,@(loop :for pset :in (rest (assoc :following-patterns grammar-specs))
					      :collect `(funcall (function ,pset) ,idiom-symbol)))))
	     (idiom-definition `(make-instance 'idiom :name ,(intern (string-upcase symbol) "KEYWORD")
					       :state ,(cons 'list (of-subspec state))
					       :utilities ,(cons 'list utility-specs)
					       :lexicons (quote ,lexicon-data)
					       :functions (let ((fn-specs (list :monadic (make-hash-table)
										:dyadic (make-hash-table)
										:symbolic (make-hash-table))))
							    (setf ,@function-specs)
							    fn-specs)
					       :operators (let ((op-specs (list :lateral (make-hash-table)
										:pivotal (make-hash-table))))
							    (setf ,@operator-specs)
							    op-specs))))
	`(progn (defvar ,idiom-symbol)
		(setf ,idiom-symbol ,idiom-definition)
		(let ((el (funcall (function ,(second (assoc :elements grammar-specs)))
				   ,idiom-symbol)))
		  (loop :for elem :in el :do (setf (gethash (first elem)
							    (idiom-grammar-elements ,idiom-symbol))
						   (second elem))))
		(setf ,@pattern-settings)
		(defmacro ,(intern (string-upcase symbol) (package-name *package*))
		    (options &optional input-string)
		  ;; this macro is the point of contact between users and the language, used to
		  ;; evaluate expressions and control properties of the language instance
		  (let* ((local-idiom (intern ,(format nil "*~a-IDIOM*" (string-upcase symbol)))))
		    `(progn ,@(if (not (boundp local-idiom))
				  ;; create idiom object within host package if it does not already exist
				  `((defvar ,local-idiom)
				    (setq ,local-idiom ,',idiom-definition)
				    (setf (idiom-composer-opening-patterns ,local-idiom)
					  (append ,@(loop :for pset :in ',(rest (assoc :opening-patterns
										       grammar-specs))
						       :collect `(funcall (function ,pset) ,local-idiom)))
					  (idiom-composer-following-patterns ,local-idiom)
					  (append ,@(loop :for pset :in ',(rest (assoc :following-patterns
										       grammar-specs))
						       :collect `(funcall (function ,pset) ,local-idiom))))
				    (let ((el (funcall (function ,',(second (assoc :elements grammar-specs)))
						       ,local-idiom)))
				      (loop :for elem :in el
					 :do (setf (gethash (first elem) (idiom-grammar-elements ,local-idiom))
						   (second elem))))))
			    ,(cond ((and options (listp options)
					 (string= "TEST" (string (first options))))
				    (let ((all-tests ',(append function-tests operator-tests general-tests)))
				      `(progn (setq prove:*enable-colors* nil)
					      (plan ,(loop :for exp :in all-tests :counting (eql 'is (first exp))))
					      ,@all-tests
					      (finalize)
					      (setq prove:*enable-colors* t))))
				   ;; the (test) setting is used to run tests
				   ((and options (listp options)
					 (string= "RESTORE-DEFAULTS" (string (first options))))
				    `(setf (idiom-state ,,idiom-symbol)
					   (copy-alist (idiom-base-state ,,idiom-symbol))))
				   ;; the (restore-defaults) setting is used to restore the workspace settings
				   ;; to the defaults from the spec
				   (t `(progn ,@(if (and (listp options)
							 (string= "SET" (string (first options)))
							 (assoc :space (rest options))
							 (not (boundp (second (assoc :space (rest options))))))
						    `((defvar ,(second (assoc :space (rest options)))
							(make-hash-table :test #'eq))))
					      (eval (vex-program ,local-idiom
								 (quote
								  ,(if input-string
								       (if (string= "SET" (string (first options)))
									   (rest options)
									   (error "Incorrect option syntax."))))
								 ,(if input-string input-string options)))
					      ;; ,(vex-program (eval (intern ,(format nil "*~a-IDIOM*"
					      ;; 					 (string-upcase symbol))))
					      ;; 		  (if input-string
					      ;; 		      (if (string= "SET" (string (first options)))
					      ;; 			  (rest options)
					      ;; 			  (error "Incorrect option syntax.")))
					      ;; 		  (if input-string input-string options))
					      )))))))))))


(defun derive-opglyphs (glyph-list &optional output)
  "Extract a list of function/operator glyphs from part of a Vex language specification."
  (if (not glyph-list)
      output (derive-opglyphs (rest glyph-list)
			      (let ((glyph (first glyph-list)))
				(if (characterp glyph)
				    (cons glyph output)
				    (if (stringp glyph)
					(append output (loop :for char :from 0 :to (1- (length glyph))
							  :collect (aref glyph char)))))))))

(defun =vex-string (idiom meta &optional output special-precedent)
  "Parse a string of text, converting its contents into nested lists of Vex tokens."
  (labels ((?blank-character () (?satisfies (of-utilities idiom :match-blank-character)))
	   (?token-character () (?satisfies (of-utilities idiom :match-token-character)))
	   (=string (&rest delimiters)
	     (let ((lastc nil)
		   (delimiter nil))
	       (=destructure (_ content _)
		   (=list (?satisfies (lambda (c) (if (member c delimiters)
						      (setq delimiter c))))
			  ;; note: nested quotes must be checked backwards; to determine whether a delimiter
			  ;; indicates the end of the quote, look at previous character to see whether it is a
			  ;; delimiter, then check whether the current character is an escape character #\\
			  (=subseq (%any (?satisfies (lambda (char)
						       (if (or (not lastc)
							       (not (char= char delimiter))
							       (char= lastc #\\))
							   (setq lastc char))))))
			  (?satisfies (lambda (c) (char= c delimiter))))
		 content)))
	   (=vex-closure (boundary-chars &optional transform-by)
	     (let ((balance 1)
		   (char-index 0))
	       (=destructure (_ enclosed _)
		   (=list (?eq (aref boundary-chars 0))
			  ;; for some reason, the first character in the string is iterated over twice here,
			  ;; so the character index is checked and nothing is done for the first character
			  ;; TODO: fix this
			  (=transform (=subseq (%some (?satisfies (lambda (char)
								    (if (and (char= char (aref boundary-chars 0))
									     (< 0 char-index))
									(incf balance 1))
								    (if (and (char= char (aref boundary-chars 1))
									     (< 0 char-index))
									(incf balance -1))
								    (incf char-index 1)
								    (< 0 balance)))))
				      (if transform-by transform-by
					  (lambda (string-content)
					    (parse string-content (=vex-string idiom meta)))))
			  (?eq (aref boundary-chars 1)))
		 enclosed)))
	   (handle-axes (input-string)
	     (let ((each-axis (funcall (of-utilities idiom :process-axis-string)
				       input-string)))
	       (cons :axes (mapcar (lambda (string) (parse string (=vex-string idiom meta)))
				   each-axis))))
	   (handle-function (input-string)
	     (list :fn (parse input-string (=vex-lines idiom meta)))))

    (let ((olnchar))
      ;; the olnchar flags are needed to handle characters that may be functional or part
      ;; of a number based on their context; in APL it's the . character, which may begin a number like .5
      ;; or may work as the inner/outer product operator, as in 1 2 3+.×4 5 6.
      (symbol-macrolet ((functional-character-matcher
			 ;; this saves space below
			 (let ((ix 0))
			   (lambda (char)
			     (if (and (> 2 ix)
				      (funcall (of-utilities idiom :match-overloaded-numeric-character)
					       char))
				 (setq olnchar char))
			     (if (and olnchar (= 2 ix)
				      (not (digit-char-p char)))
				 (setq olnchar nil))
			     (incf ix 1)
			     (and (not (< 2 ix))
				  (or (of-lexicon idiom :functions char)
				      (of-lexicon idiom :operators char)))))))
	(=destructure (_ item _ rest)
	    (=list (%any (?blank-character))
		   (%or (=vex-closure "()")
			(=vex-closure "[]" #'handle-axes)
			(=vex-closure "{}" #'handle-function)
			(=string #\' #\")
			(=transform (=subseq (%some (?satisfies functional-character-matcher)))
				    (lambda (string)
				      (let ((char (character string)))
					(if (not olnchar)
					    `(,(if (of-lexicon idiom :operators char)
						   :op (if (of-lexicon idiom :functions char)
							   :fn))
					       ,@(if (of-lexicon idiom :operators char)
						     (list (if (of-lexicon idiom :pivotal-operators char)
							       :pivotal :lateral)))
					       ,char)))))
			(=transform (=subseq (%some (?token-character)))
				    (lambda (string)
				      (funcall (of-utilities idiom :format-value)
					       (string-upcase (idiom-name idiom))
					       ;; if there's an overloaded token character passed in
					       ;; the special precedent, prepend it to the token being processed
					       meta (if (getf special-precedent :overloaded-num-char)
							(concatenate 'string (list (getf special-precedent
											 :overloaded-num-char))
								     string)
							string)))))
		   (%any (?blank-character))
		   (=subseq (%any (?satisfies 'characterp))))
	  ;; (print (list :rr rest))
	  (if (< 0 (length rest))
	      (parse rest (=vex-string idiom meta (if output (if item (cons item output)
								 output)
						      (if item (list item)))
				       (if olnchar (list :overloaded-num-char olnchar))))
	      (if item (cons item output)
		  output)))))))

(defun =vex-lines (idiom meta)
  "Parse lines of a vector language."
  (labels ((?blank-character () (?satisfies (of-utilities idiom :match-blank-character)))
	   (?newline-character () (?satisfies (of-utilities idiom :match-newline-character)))
	   (?but-newline-character ()
	     (?satisfies (lambda (char) (not (funcall (of-utilities idiom :match-newline-character)
						      char))))))
    (=destructure (_ content _ nextlines)
	(=list (%any (?blank-character))
	       (=subseq (%any (?but-newline-character)))
	       (%any (?newline-character))
	       (=subseq (%any (?satisfies 'characterp))))
      (list (parse content (=vex-string idiom meta))
	    nextlines))))

(defmacro set-composer-elements (name with &rest params)
  (let* ((with (rest with))
	 (idiom (gensym))
	 (tokens (getf with :tokens-symbol))
	 (idiom (getf with :idiom-symbol))
	 (space (getf with :space-symbol with))
	 (properties (getf with :properties-symbol))
	 (process (getf with :processor-symbol with)))
    `(defun ,(intern (string-upcase name)
		     (package-name *package*))
	 (,idiom)
       (declare (ignorable ,idiom))
       (list ,@(loop :for param :in params
		  :collect `(list ,(intern (string-upcase (first param)) "KEYWORD")
				  (lambda (,tokens &optional ,properties ,process ,idiom ,space)
				    (declare (ignorable ,properties ,process ,idiom ,space))
				    ,(second param))))))))

(defun composer (idiom space tokens &optional precedent properties)
  "Compile processed tokens output by the parser into code according to an idiom's grammars and primitive elements."
  ;; (print (list :comp tokens precedent properties))
  (if (not tokens)
      (values precedent properties)
      (let ((processed nil)
	    (special-params (getf properties :special)))
	;; (print (list :prec precedent))
	;; (print (list :tokens-b precedent tokens))
	(loop :while (not processed)
	   :for pattern :in (if (not precedent)
				(vex::idiom-composer-opening-patterns idiom)
				(vex::idiom-composer-following-patterns idiom))
	   :when (or (not (getf special-params :omit))
		     (not (member (getf pattern :name)
				  (getf special-params :omit))))
	   :do ;; (print (list :pattern (getf pattern :name) precedent tokens properties))
	   (multiple-value-bind (new-processed new-props remaining)
	       (funcall (getf pattern :function)
			tokens space (lambda (item &optional sub-props)
				       (declare (ignorable sub-props))
				       (composer idiom space item nil sub-props))
			precedent properties)
	     ;; (if new-processed (princ (format nil "~%~%!!Found!! ~a ~%~a~%" new-processed
	     ;; 				      (list new-props remaining))))
	     (if new-processed (setq processed new-processed properties new-props tokens remaining))))
	(if special-params (setf (getf properties :special) special-params))
	(if (not processed)
	    (values precedent properties tokens)
	    (composer idiom space tokens processed properties)))))


(defmacro set-composer-patterns (name with &rest params)
  "Generate part of a Vex grammar from entered specifications."
  (let* ((with (rest with))
	 (idiom (gensym)) (token (gensym)) (invalid (gensym)) (properties (gensym))
	 (space (or (getf with :space-symbol) (gensym)))
	 (precedent-symbol (getf with :precedent-symbol))
	 (precedent (or precedent-symbol (gensym)))
	 (process (or (getf with :process-symbol) (gensym)))
	 (sub-properties (or (getf with :properties-symbol) (gensym)))
	 (idiom-symbol (getf with :idiom-symbol)))
    `(defun ,(intern (string-upcase name) (package-name *package*)) (,idiom)
       (let ((,idiom-symbol ,idiom))
	 (declare (ignorable ,idiom-symbol))
	 (list ,@(loop :for param :in params
		    :collect `(list :name ,(intern (string-upcase (first param)) "KEYWORD")
				    :function (lambda (,token ,space ,process &optional ,precedent ,properties)
						(declare (ignorable ,precedent ,properties))
						(let ((,invalid nil)
						      (,sub-properties nil)
						      ,@(loop :for token :in (second param)
							   :when (not (keywordp (first token)))
							   :collect (list (first token) nil)))
						  ,@(build-composer-pattern (second param)
									    idiom-symbol token invalid properties
									    process space sub-properties)
						  (setq ,sub-properties (reverse ,sub-properties))
						  ;; reverse the sub-properties since they are consed into the list
						  (if (not ,invalid)
						      (values ,(third param)
							      ,(fourth param)
							      ,token)))))))))))

(defun build-composer-pattern (sequence idiom tokens-symbol invalid-symbol properties-symbol
			       process space sub-props)
  "Generate a pattern for language compilation from a set of specs entered as part of a grammar."
  (labels ((element-check (base-type)
	     `(funcall (gethash ,(intern (string-upcase (cond ((listp base-type)
							       (first base-type))
							      (t base-type)))
	   				 "KEYWORD")
	   			(vex::idiom-grammar-elements ,idiom))
	   	       rem ,(cond ((listp base-type) `(quote ,(rest base-type))))
		       ,process ,idiom ,space))
	   (process-item (item-symbol item-properties)
	     (let ((multiple (getf item-properties :times))
		   (optional (getf item-properties :optional))
		   (element-type (getf item-properties :element))
		   (pattern-type (getf item-properties :pattern)))
	       (cond (pattern-type
		      `(if (not ,invalid-symbol)
			   (multiple-value-bind (item item-props remaining)
			       ;; (composer ,idiom ,tokens-symbol)
			       (funcall ,process ,tokens-symbol
					,@(if (and (listp (second item-properties))
						   (getf (second item-properties) :special))
					      `((list :special ,(getf (second item-properties) :special)))))
			     ;; (print (list :composed item item-props remaining ,sub-props))
			     (setq ,sub-props (cons item-props ,sub-props))
			     (if ,(cond ((getf pattern-type :type)
					 `(loop :for type :in (list ,@(getf pattern-type :type))
					     :always (member type (getf item-props :type))))
					(t t))
				 (setq ,item-symbol item
				       ,tokens-symbol remaining)
				 (setq ,invalid-symbol t)))))
		     (element-type
		      `(if (not ,invalid-symbol)
			   (let ((matching t)
				 (collected nil)
				 (rem ,tokens-symbol)
				 (initial-remaining ,tokens-symbol))
			     (declare (ignorable initial-remaining))
			     (loop ,@(if (eq :any multiple)
					 `(:while (and matching rem))
					 `(:for x from 0 to ,(if multiple (1- multiple) 0)))
				:do (multiple-value-bind (item item-props remaining)
					,(element-check element-type)
				      ;; only push the returned properties onto the list if the item matched
				      (if (and item-props (not (getf item-props :cancel-flag)))
					  (setq ,sub-props (cons item-props ,sub-props)))
				      ;; if a cancel-flag property is returned, void the collected items
				      ;; and reset the remaining items back to the original list of tokens
				      (if (getf item-props :cancel-flag)
					  (setq rem initial-remaining
						collected nil))
				      (if item (setq collected (cons item collected)
						     rem remaining)
					  (setq matching nil))))
			     (if ,(if (not optional)
				      'collected t)
				 (setq ,item-symbol (if (< 1 (length collected))
							collected (first collected))
				       ,tokens-symbol rem)
				 (setq ,invalid-symbol t))
			     (list :out ,item-symbol ,tokens-symbol collected ,optional))))))))
    (loop :for item :in sequence
       :collect (let* ((item-symbol (first item)))
		  (if (keywordp item-symbol)
		      (cond ((eq :with-preceding-type item-symbol)
			     `(setq ,invalid-symbol (loop :for item :in (getf ,properties-symbol :type)
						       :never (eq item ,(second item)))))
			    ((eq :rest item-symbol)
			     `(setq ,invalid-symbol (< 0 (length ,tokens-symbol)))))
		      (let ((item-properties (rest item)))
			(process-item item-symbol item-properties)))))))

(defun vex-program (idiom options &optional string meta internal)
  "Compile a set of expressions, optionally drawing external variables into the program and setting configuration parameters for the system."
  (let* ((state (rest (assoc :state options)))
	 (meta (if meta meta (if (assoc :space options)
				 (symbol-value (second (assoc :space options)))
				 (make-hash-table :test #'eq))))
	 (state-persistent (rest (assoc :state-persistent options)))
	 (state-to-use nil)
	 (preexisting-vars nil))
    (labels ((assign-from (source dest)
	       (if source (progn (setf (getf dest (first source))
				       (second source))
				 (assign-from (cddr source)
					      dest))
		   dest))
	     (process-lines (lines &optional output)
	       (if (= 0 (length lines))
		   output (destructuring-bind (out remaining)
			      (parse lines (=vex-lines idiom meta))
			    ;;(print (list :oo out remaining))
			    (process-lines remaining (append output (list (composer idiom meta out))))))))

      (if (not (gethash :variables meta))
	  (setf (gethash :variables meta) (make-hash-table :test #'eq))
	  (setq preexisting-vars (loop :for vk :being :the :hash-values :of (gethash :variables meta)
				    :collect vk)))
      
      (if (not (gethash :values meta))
	  (setf (gethash :values meta) (make-hash-table :test #'eq)))

      (if (not (gethash :functions meta))
	  (setf (gethash :functions meta) (make-hash-table :test #'eq)))

      (setf state-to-use
	    (assign-from state (assign-from state-persistent (assign-from (gethash :state meta)
									  (idiom-base-state idiom)))))

      (if state-persistent (setf (idiom-state idiom)
      				 (assign-from state-persistent (idiom-base-state idiom))
				 (gethash :state meta)
				 (assign-from state-persistent (gethash :state meta))))
      
      (if string
	  (let* ((input-vars (getf state-to-use :in))
		 (output-vars (getf state-to-use :out))
		 (compiled-expressions (process-lines (funcall (of-utilities idiom :prep-code-string)
							       string)))
		 (var-symbols (loop :for key :being :the :hash-keys :of (gethash :variables meta)
				 :when (not (member (string (gethash key (gethash :variables meta)))
						    (mapcar #'first input-vars)))
				 :collect (list key (gethash key (gethash :variables meta)))))
		 (vars-declared (loop :for key-symbol :in var-symbols
				   :when (not (member (string (gethash (first key-symbol)
								       (gethash :variables meta)))
						      (mapcar #'first input-vars)))
				   :collect (let* ((sym (second key-symbol))
						   (fun-ref (gethash sym (gethash :functions meta)))
						   (val-ref (gethash sym (gethash :values meta))))
					      (list sym (if (member sym preexisting-vars)
							    (if val-ref val-ref (if fun-ref fun-ref))
							    :undefined))))))
	    (if input-vars
		(loop :for var-entry :in input-vars
		   ;; TODO: move these APL-specific checks into spec
		   :do (if (gethash (intern (lisp->camel-case (first var-entry)) "KEYWORD")
				    (gethash :variables meta))
			   (rplacd (assoc (gethash (intern (lisp->camel-case (first var-entry)) "KEYWORD")
						   (gethash :variables meta))
					  vars-declared)
				   (list (second var-entry)))
			   (setq vars-declared (append vars-declared
						       (list (list (setf (gethash (intern (lisp->camel-case
											   (first var-entry))
											  "KEYWORD")
										  (gethash :variables meta))
									 (gensym))
								   (second var-entry))))))))
	    (let ((code `(,@(if (and vars-declared (not internal))
				`(let* ,vars-declared
				   (declare (ignorable ,@(mapcar #'second var-symbols))))
				'(progn))
			    ,@(funcall (if output-vars #'values (of-utilities idiom :postprocess-compiled))
				       compiled-expressions)
			    ,@(if output-vars
				  (list (cons 'values
					      (mapcar (lambda (return-var)
							(funcall (of-utilities idiom :postprocess-value)
								 (gethash (intern (lisp->camel-case return-var)
										  "KEYWORD")
									  (gethash :variables meta))))
						      output-vars)))))))
	      (if (assoc :compile-only options)
		  `(quote ,code)
		  code)))))))
