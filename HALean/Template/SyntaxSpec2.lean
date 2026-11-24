/-
  Specifications for the non-recursive helpers of
  `HALean/Template/Syntax.lean`: name characters, string-literal unescaping,
  whitespace control, the token-stream primitives of the parser, the
  one-token statements and the compilation of static templates.
-/
import HALean.Template.Syntax

namespace HALean.Template

set_option linter.unusedSimpArgs false

/-- Unfold the parser monad (`StateT (List Tok) (Except String)`). -/
local macro "psimp" "[" ls:Lean.Parser.Tactic.simpLemma,* "]" loc:(Lean.Parser.Tactic.location)? : tactic =>
  `(tactic| simp [bind, pure, StateT.bind, StateT.pure, StateT.run, StateT.map, Functor.map, get,
      getThe, MonadStateOf.get, StateT.get, set, MonadStateOf.set, StateT.set, modify, modifyGet,
      MonadStateOf.modifyGet, StateT.modifyGet, liftM, monadLift, MonadLift.monadLift, StateT.lift,
      Except.bind, Except.pure, Except.map, throw, throwThe, MonadExceptOf.throw, $ls,*] $[$loc]?)

/-! ## Name characters -/

/-- Every character that can start a name can continue one. -/
theorem isNameStart_isNameChar (c : Char) (h : isNameStart c = true) : isNameChar c = true := by
  simp only [isNameStart, isNameChar, Char.isAlphanum, Bool.or_eq_true] at h ⊢
  rcases h with h | h
  · exact .inl (.inl h)
  · exact .inr h

/-- A digit can continue a name but not start one (Python identifiers). -/
theorem isNameChar_digit (c : Char) (h : c.isDigit = true) :
    isNameChar c = true ∧ isNameStart c = false := by
  have hne : c ≠ '_' := by
    intro hc; subst hc; revert h; decide
  simp only [isNameStart, isNameChar, Char.isAlphanum, Char.isAlpha, Char.isUpper, Char.isLower,
    Char.isDigit, UInt32.le_iff_toNat_le, ge_iff_le] at h ⊢
  simp at h ⊢
  refine ⟨.inl (.inr h), ⟨⟨?_, ?_⟩, hne⟩⟩ <;> intro <;> omega

/-- The underscore is a name character in both positions. -/
theorem isNameStart_underscore : isNameStart '_' = true ∧ isNameChar '_' = true := by decide

/-- The only name characters that cannot start a name are the digits. -/
theorem isNameChar_iff (c : Char) : isNameChar c = true ↔ isNameStart c = true ∨ c.isDigit = true := by
  simp only [isNameStart, isNameChar, Char.isAlphanum, Bool.or_eq_true]
  constructor
  · rintro ((h | h) | h)
    · exact .inl (.inl h)
    · exact .inr h
    · exact .inl (.inr h)
  · rintro ((h | h) | h)
    · exact .inl (.inl h)
    · exact .inr h
    · exact .inl (.inr h)

/-! ## String-literal escapes -/

private theorem unescape_go_plain (cs : List Char) (acc : String) (h : ∀ c ∈ cs, c ≠ '\\') :
    unescape.go cs acc = .ok (acc ++ String.ofList cs) := by
  induction cs generalizing acc with
  | nil => simp [unescape.go, pure, Except.pure]
  | cons c cs ih =>
    have hc : c ≠ '\\' := h c (by simp)
    rw [unescape.go.eq_def]
    split
    · rename_i heq; cases heq
    · rename_i heq; simp at heq
      first | exact absurd heq hc | exact absurd heq.1 hc | exact absurd heq.1.1 hc
    · rename_i acc0 _ _ c' rest _ heq
      simp at heq
      obtain ⟨rfl, rfl⟩ := heq
      rw [ih _ (fun c hm => h c (by simp [hm]))]
      congr 1
      apply String.toList_inj.mp
      simp

/-- A literal without backslashes is taken as it is. -/
theorem unescape_plain (cs : List Char) (h : ∀ c ∈ cs, c ≠ '\\') :
    unescape cs = .ok (String.ofList cs) := by
  unfold unescape
  rw [unescape_go_plain cs "" h]
  simp

/-- The Python escapes Jinja's lexer handles: `\n`, `\t`, `\\`, `\'`, `\"`,
and `\xhh`; an unknown escape keeps its backslash. -/
theorem unescape_escapes :
    unescape ['a', '\\', 'n', 'b'] = .ok "a\nb" ∧
    unescape ['\\', 't'] = .ok "\t" ∧
    unescape ['\\', '\\'] = .ok "\\" ∧
    unescape ['\\', '\''] = .ok "'" ∧
    unescape ['\\', '"'] = .ok "\"" ∧
    unescape ['\\', 'x', '4', '1'] = .ok "A" ∧
    unescape ['\\', 'q'] = .ok "\\q" := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> rfl

/-- A truncated or non-hex `\x` escape is an error. -/
theorem unescape_bad_hex :
    unescape ['\\', 'x'] = .error "invalid \\x escape in string literal" ∧
    unescape ['\\', 'x', 'g', '0'] = .error "invalid \\x escape in string literal" := by
  constructor <;> rfl

/-! ## Whitespace control (`-}}`, `{{-`) -/

private theorem dropWhile_head (p : α → Bool) (l : List α) (x : α)
    (h : (l.dropWhile p).head? = some x) : p x = false := by
  induction l with
  | nil => simp at h
  | cons a l ih =>
    by_cases ha : p a = true
    · rw [List.dropWhile_cons_of_pos ha] at h; exact ih h
    · rw [List.dropWhile_cons_of_neg ha] at h
      simp at h; subst h; simpa using ha

private theorem dropWhile_idem (p : α → Bool) (l : List α) :
    (l.dropWhile p).dropWhile p = l.dropWhile p := by
  cases h : l.dropWhile p with
  | nil => rfl
  | cons a t =>
    exact List.dropWhile_cons_of_neg (by simp [dropWhile_head p l a (by simp [h])])

/-- Dropping leading whitespace leaves no leading whitespace. -/
theorem dropLeadingWs_head (cs : List Char) (c : Char) (h : (dropLeadingWs cs).head? = some c) :
    c.isWhitespace = false := dropWhile_head _ cs c h

/-- ... is idempotent ... -/
theorem dropLeadingWs_idem (cs : List Char) : dropLeadingWs (dropLeadingWs cs) = dropLeadingWs cs :=
  dropWhile_idem _ cs

/-- ... and only removes characters from the front. -/
theorem dropLeadingWs_suffix (cs : List Char) : dropLeadingWs cs <:+ cs :=
  List.dropWhile_suffix _

/-- Text that does not start with whitespace is unchanged. -/
theorem dropLeadingWs_fix (c : Char) (cs : List Char) (h : c.isWhitespace = false) :
    dropLeadingWs (c :: cs) = c :: cs := List.dropWhile_cons_of_neg (by simp [h])

/-- Stripping the right end leaves no trailing whitespace. -/
theorem stripRight_last (s : String) (c : Char) (h : (stripRight s).toList.getLast? = some c) :
    c.isWhitespace = false := by
  simp only [stripRight, String.toList_ofList, List.getLast?_reverse] at h
  exact dropWhile_head _ _ c h

/-- `stripRight` is idempotent. -/
theorem stripRight_idem (s : String) : stripRight (stripRight s) = stripRight s := by
  simp [stripRight, dropWhile_idem]

/-- `stripRight` keeps a prefix of the text. -/
theorem stripRight_prefix (s : String) : (stripRight s).toList <+: s.toList := by
  simp only [stripRight, String.toList_ofList]
  have := List.dropWhile_suffix Char.isWhitespace (l := s.toList.reverse)
  simpa using List.reverse_prefix.mpr this

/-! ## Token-stream primitives -/

/-- `peek` and `peek2` look at the next tokens without consuming them. -/
theorem peek_run (toks : List Tok) : peek.run toks = .ok (toks.head?, toks) := rfl

theorem peek2_run (toks : List Tok) : peek2.run toks = .ok ((toks.drop 1).head?, toks) := rfl

/-- `advance` consumes exactly one token (and is harmless at the end). -/
theorem advance_run (toks : List Tok) : advance.run toks = .ok ((), toks.drop 1) := rfl

/-- `isOp` and `isName` never consume or fail. -/
theorem isOp_run (o : String) (toks : List Tok) :
    ∃ b, (isOp o).run toks = .ok (b, toks) := ⟨_, rfl⟩

theorem isName_run (n : String) (toks : List Tok) :
    ∃ b, (isName n).run toks = .ok (b, toks) := ⟨_, rfl⟩

/-- **`expectOp`** succeeds exactly when the next token is that operator,
and then consumes just it. -/
theorem expectOp_iff (o : String) (toks rest : List Tok) :
    (expectOp o).run toks = .ok ((), rest) ↔ toks = .op o :: rest := by
  cases toks with
  | nil => psimp [expectOp, peek]
  | cons t toks =>
    cases t <;> psimp [expectOp, peek, advance]
    rename_i x
    by_cases hx : x = o
    · psimp [hx]
    · psimp [hx]

/-- **`expectName`** succeeds exactly when the next token is a name: it
returns the name and consumes the token. -/
theorem expectName_iff (toks rest : List Tok) (n : String) :
    expectName.run toks = .ok (n, rest) ↔ toks = .name n :: rest := by
  cases toks with
  | nil => psimp [expectName, peek]
  | cons t toks => cases t <;> psimp [expectName, peek, advance]

/-- At the end of the block both report an error. -/
theorem expect_eof (o : String) :
    (∃ e, (expectOp o).run [] = .error e) ∧ (∃ e, expectName.run [] = .error e) :=
  ⟨⟨_, rfl⟩, ⟨_, rfl⟩⟩

/-- `expectKw` consumes the keyword it finds. -/
theorem expectKw_run (k : String) (rest : List Tok) :
    (expectKw k).run (.name k :: rest) = .ok ((), rest) := by
  have : (Tok.name k == Tok.name k) = true := by simp [BEq.beq, instBEqTok.beq]
  psimp [expectKw, isName, peek, advance, this]

/-- `expectKw` fails on anything that is not a name. -/
theorem expectKw_op (k o : String) (rest : List Tok) :
    ∃ e, (expectKw k).run (.op o :: rest) = .error e := ⟨_, rfl⟩

/-- `runExpr` accepts a parse only when it consumed every token. -/
theorem runExpr_iff (p : PS α) (toks : List Tok) (a : α) :
    runExpr p toks = .ok a ↔ p.run toks = .ok (a, []) := by
  unfold runExpr
  cases h : p.run toks with
  | error e => simp [bind, Except.bind]
  | ok r =>
    obtain ⟨a', rest⟩ := r
    cases rest with
    | nil => simp [bind, Except.bind, pure, Except.pure]
    | cons t ts => simp [bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-- A parser error is passed on unchanged. -/
theorem runExpr_error (p : PS α) (toks : List Tok) (e : String) (h : p.run toks = .error e) :
    runExpr p toks = .error e := by
  simp [runExpr, h, bind, Except.bind]

/-! ## Test arguments without parentheses -/

/-- A name starts a test argument unless it is `else`, `or` or `and`
(`x is divisibleby 3 else ...`). -/
theorem startsPrimary_name (n : String) :
    startsPrimary (some (.name n)) = true ↔ n ≠ "else" ∧ n ≠ "or" ∧ n ≠ "and" := by
  simp [startsPrimary]

/-- Literals start an argument; the end of the block does not. -/
theorem startsPrimary_literal (s : String) (i : Int) (f : Float) :
    startsPrimary (some (.str s)) = true ∧ startsPrimary (some (.int i)) = true ∧
      startsPrimary (some (.float f)) = true ∧ startsPrimary none = false ∧
      startsPrimary (some .close) = false := ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- Among operators only the opening brackets start an argument. -/
theorem startsPrimary_op (o : String) :
    startsPrimary (some (.op o)) = true ↔ o = "(" ∨ o = "[" ∨ o = "{" := by
  simp [startsPrimary]

/-! ## Statements -/

/-- The one-word tags. -/
theorem parseStmt_keywords :
    parseStmt [.name "else"] = .ok .elseS ∧ parseStmt [.name "endif"] = .ok .endifS ∧
    parseStmt [.name "endfor"] = .ok .endforS ∧ parseStmt [.name "break"] = .ok .brkS ∧
    parseStmt [.name "continue"] = .ok .contS := ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- An empty `{% %}`, or one that does not start with a name, is rejected. -/
theorem parseStmt_invalid (o : String) (rest : List Tok) :
    parseStmt [] = .error "empty or invalid statement" ∧
      parseStmt (.op o :: rest) = .error "empty or invalid statement" := ⟨rfl, rfl⟩

/-! ## Compiling static templates -/

/-- Text without `{{`, `{%` or `{#` compiles, without lexing, to a static
template whose only node is the stripped text. -/
theorem compile_static (raw : String) (h : isTemplateString raw = false) :
    compile raw = .ok { src := raw.trim, isStatic := true, nodes := [.text raw.trim] } := by
  simp [compile, h, pure, Except.pure]

/-- A template that compiles is static exactly when its text has no Jinja
opening (`Template.is_static`). -/
theorem compile_isStatic (raw : String) (t : Tmpl) (h : compile raw = .ok t) :
    t.isStatic = !isTemplateString raw ∧ t.src = raw.trim := by
  cases hs : isTemplateString raw
  · rw [compile_static raw hs] at h
    cases h; exact ⟨rfl, rfl⟩
  · unfold compile at h
    simp only [hs, bind, Except.bind, pure, Except.pure] at h
    simp at h
    split at h
    · cases h
    · split at h
      · cases h
      · cases h; exact ⟨rfl, rfl⟩

end HALean.Template
