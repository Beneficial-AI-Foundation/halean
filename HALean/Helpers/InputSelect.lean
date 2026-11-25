/-
  `input_select`: translated from
  `homeassistant/components/input_select/__init__.py` (`CONFIG_SCHEMA`,
  `_cv_input_select`, `_remove_duplicates`, `InputSelect`, the
  `select_option` / `select_first` / `select_last` / `select_next` /
  `select_previous` / `set_options` entity services) and the parts of
  `SelectEntity` (`components/select/__init__.py`) it uses: `state`,
  `capability_attributes`, `async_first` / `async_last` / `async_next` /
  `async_previous` (`_async_offset_index`, `_async_select_index`).

  `input_select.select_option` calls `InputSelect.async_select_option`
  directly (not `SelectEntity.async_handle_select_option`), so an unknown
  option is a `HomeAssistantError`, not a `ServiceValidationError`.

  The current option is always one of the options, and the options are
  never empty (`Proofs.lean`).
-/
import HALean.Helpers.Common

namespace HALean.Helpers.InputSelect
open HALean.Core HALean.Template HALean.Helpers

def DOMAIN : String := "input_select"

structure Config where
  id : String
  name : Option String := none
  /-- after `_remove_duplicates` -/
  options : List String
  initial : Option String := none
  icon : Option String := none
  deriving Inhabited

/-- `vol.All(vol.EnsureList(), vol.Length(min=1), [cv.string])` -/
def optionsSchema : Validator := .all [.ensureList, .length (some 1) none, .seq [vString]]

def fields : List Field :=
  [opt "name" vString, req "options" optionsSchema, opt "initial" vString, opt "icon" vIcon]

def strList : Option Value → List String
  | some (.list xs) => xs.filterMap fun x => match x with | .str s => some s | _ => none
  | _ => []

/-- `list(dict.fromkeys(options))` -/
def dedup (xs : List String) : List String := xs.eraseDups

/-- `_cv_input_select`: `initial` must be an option (checked before
duplicates are removed); duplicates are removed with a warning. -/
def decode (id : String) (v : Value) : Except VErr (Config × Option String) := do
  let kvs ← runDict fields v
  let options := strList (lk kvs "options")
  let initial := lkStr kvs "initial"
  if let some i := initial then
    if !options.contains i then
      invalid s!"initial state {i} is not part of the options: {",".intercalate options}"
  let name := lkStr kvs "name"
  let uniq := dedup options
  let warn := if uniq.length != options.length then
      some s!"Input select '{name.getD "<unnamed>"}' with options {(pyRepr (.list (options.map .str))).toOption.getD "?"} had duplicated options, the duplicates have been removed"
    else none
  return ({ id, name, options := uniq, initial, icon := lkStr kvs "icon" }, warn)

def decodeConfig (cfg : Value) : Except ConfigError (List (Config × Option String)) :=
  slugKeys DOMAIN cfg decode

structure Entity where
  cfg : Config
  /-- `_attr_options` -/
  options : List String
  /-- `_attr_current_option` (set from the start: `async_added_to_hass`
  falls back to the first option) -/
  current : String
  deriving Inhabited

def Entity.entityId (e : Entity) : String := s!"{DOMAIN}.{e.cfg.id}"

/-- `__init__` then `async_added_to_hass`: `initial`, else the last state if
it is an option, else the first option. -/
def Entity.create (cfg : Config) (lastState : Option String) : Entity :=
  let first := cfg.options.headD ""
  match cfg.initial with
  | some i => { cfg, options := cfg.options, current := i }
  | none =>
    match lastState with
    | some s => { cfg, options := cfg.options, current := if cfg.options.contains s then s else first }
    | none => { cfg, options := cfg.options, current := first }

/-- `SelectEntity.state`: the current option when it is one of the options,
else `None` (`unknown`). -/
def Entity.state (e : Entity) : String :=
  if e.options.contains e.current then e.current else STATE_UNKNOWN

/-- `capability_attributes` (`options`), `editable`, `icon`, `friendly_name`. -/
def Entity.attrs (e : Entity) : Attrs :=
  [("options", .list (e.options.map .str)), ("editable", .bool false)] ++
    tailAttrs none e.cfg.icon e.cfg.name

def write : HM Entity Unit := do
  let e ← getEnt
  emit (.write e.entityId e.state e.attrs false)

/-- `InputSelect.async_select_option` -/
def selectOption (e : Entity) (option : String) : Except PyErr Entity :=
  if e.options.contains option then .ok { e with current := option }
  else .error (pyErr "HomeAssistantError"
    s!"Invalid option: {option} (possible options: {", ".intercalate e.options})")

/-- Python's `options[i % len(options)]` for a non-empty list. -/
def atMod (xs : List String) (i : Int) : String :=
  xs.getD (i % (xs.length : Int)).toNat ""

/-- `_async_select_index` (the options are never empty for an input select,
so `_options_or_raise` never raises). -/
def selectIndex (e : Entity) (idx : Int) : Except PyErr Entity :=
  selectOption e (atMod e.options idx)

/-- `_async_offset_index` -/
def offsetIndex (e : Entity) (offset : Int) (cycle : Bool) : Except PyErr Entity :=
  let n : Int := e.options.length
  let cur : Int := if e.options.contains e.current then (e.options.idxOf e.current : Nat) else 0
  let i := cur + offset
  let i := if cycle then i % n else if i < 0 then 0 else if i ≥ n then n - 1 else i
  selectOption e (e.options.getD i.toNat "")

/-- `InputSelect.async_set_options`: duplicates are a
`HomeAssistantError`; when the current option is gone, the first option is
selected (with a warning). -/
def setOptions (e : Entity) (options : List String) : Except PyErr (Entity × Option String) :=
  if (dedup options).length != options.length then
    .error (pyErr "HomeAssistantError"
      s!"Duplicated options: {(pyRepr (.list (options.map .str))).toOption.getD "?"}")
  else if options.contains e.current then .ok ({ e with options }, none)
  else .ok ({ e with options, current := options.headD "" },
    some s!"Current option: {e.current} no longer valid (possible options: {", ".intercalate options})")

def services : List (String × List Field) :=
  [("select_first", []), ("select_last", []),
   ("select_next", [opt "cycle" (.type .bool) (some (.bool true))]),
   ("select_option", [req "option" vString]),
   ("select_previous", [opt "cycle" (.type .bool) (some (.bool true))]),
   ("set_options", [req "options" optionsSchema])]

def handle (service : String) (args : List (String × Value)) : HM Entity Unit := do
  let e ← getEnt
  let cycle := match lk args "cycle" with | some (.bool b) => b | _ => true
  if service == "set_options" then
    match setOptions e (strList (lk args "options")) with
    | .ok (e', warn) =>
      if let some w := warn then emit (.log "warning" w)
      setEnt e'
      write
    | .error err => throw err
  else
    let r := match service with
      | "select_first" => selectIndex e 0
      | "select_last" => selectIndex e (-1)
      | "select_next" => offsetIndex e 1 cycle
      | "select_previous" => offsetIndex e (-1) cycle
      | _ => selectOption e ((lkStr args "option").getD "")
    match r with
    | .ok e' => setEnt e'; write
    | .error err => throw err

end HALean.Helpers.InputSelect
