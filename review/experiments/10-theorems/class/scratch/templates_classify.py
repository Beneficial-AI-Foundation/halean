import sys,collections
D={}
def add(mod,txt):
    for line in txt.strip().split('\n'):
        line=line.strip()
        if not line: continue
        n,c,r=line.split('|',2)
        assert c in 'COEH'
        if len(r.split())>15: print('LONG',mod,n,len(r.split()))
        assert (mod,n) not in D,(mod,n)
        D[(mod,n)]=(c,r)
add('CvBooleanSpec','''
cvBooleanText_iff|C|cvBooleanText s = some b iff lowered s is a true/false word between whitespace
words_ends|H|each true/false word is non-empty and has no whitespace at its ends
''')
add('ParseTimeSpec','''
parseTimeSeconds_iff|C|parseTimeSeconds s = some t iff split parts satisfy PyIntSpec and time ranges
''')
add('Proofs','''
cvBoolean_bool|E|cvBoolean of a bool is that bool (rfl, one constructor)
iif_none|E|iif of None with if_none given returns if_none (rfl)
iif_truthy|O|without if_none, iif picks a branch by truthy (case split restated)
render_static|E|render of a Tmpl with isStatic and parse=false returns its src
resultAsBoolean_none|E|resultAsBoolean of None is false (rfl)
''')
add('PyIntSpec','''
digit_not_space|H|a digit character is not pySpace
digitsUs_cc|H|unfolding of digitsUs on a two-character prefix
digitsUs_head|H|a DigitsUs list starts with a digit
digitsUs_head_nonspace|H|first character of a DigitsUs list is not whitespace
digitsUs_iff|H|boolean digitsUs decides the inductive grammar DigitsUs
digitsUs_last|H|a DigitsUs list ends with a digit
digitsUs_last_nonspace|H|last character of a DigitsUs list is not whitespace
digitsUs_ne_nil|H|a DigitsUs list is non-empty
digitsUs_not_sign|H|a DigitsUs list does not start with a sign
dropWhile_prefix|H|dropWhile removes a prefix of p-characters before a non-p head
parseIntChars_iff|C|parseIntChars cs = some n iff cs matches the int() grammar PyIntSpec with value n
signSplit_of|H|signSplit of sign ++ digits returns the sign flag and the digits
signSplit_spec|H|signSplit splits off an optional sign
stripBy_eq|H|stripBy of padding ++ core ++ padding is the core
stripBy_split|H|every list is padding ++ stripBy result ++ padding
stripPy_eq|H|stripBy_eq instantiated at pySpace
stripPy_split|H|stripBy_split instantiated at pySpace
takeWhile_all|H|members of takeWhile p satisfy p
''')
add('RegexSpec','''
Rx.Caps.get?_append_of_isSome|H|appending captures does not change a group value already present
Rx.Caps.get?_cons_of_ne|H|a capture under another name does not change the lookup
Rx.Caps.get?_cons_self|H|the most recent capture of a name is returned
Rx.Caps.get?_eq_none_iff|H|lookup is none iff no capture has that name
Rx.Caps.get?_isSome_of_mem|H|a captured name has a value
Rx.Caps.get?_nil|H|lookup in the empty capture list is none (rfl)
Rx.Caps.mem_of_get?_eq_some|H|a returned group value is in the capture list
''')
add('SyntaxSpec','''
hasJinjaOpen_iff|H|hasJinjaOpen cs iff cs contains "{" followed by %, { or #
isTemplateString_iff|C|isTemplateString s iff "{" in s and one of "{%", "{{", "{#" occurs
''')
add('ValueSpec','''
boolStr_eq_False|H|boolStr b = "False" iff b = false
boolStr_eq_True|H|boolStr b = "True" iff b = true
cmpIntFloat_inf|E|comparing an int with an infinity gives lt or gt by its sign
decodeFloat_bounds|H|decoded mantissa below 2^53 and exponent within -1074..972
floatFrac_den_pos|H|floatFrac denominator is positive
floatFrac_of_exp_nonneg|H|floatFrac with non-negative exponent has denominator 1
floatRepr_inf|E|floatRepr of an infinity is "inf" or "-inf"
floatRepr_nan|E|floatRepr of a NaN is "nan"
floatToInt?_eq_none_iff|O|floatToInt? fails exactly for NaN and infinities; value not stated
floatToJson_not_finite|E|floatToJson of a non-finite float is an error
foldl_plain|H|folding a push-only function appends the characters
hexDigit_spec|H|hexDigit n is the lower-case hex digit for n < 16
intToFloat_zero|E|intToFloat 0 = 0.0
lt_ceil_iff|H|arithmetic: i below ceiling division iff c*i < n
mem_rangeItems_neg|O|membership in rangeItems for a negative step; order not stated
mem_rangeItems_one|O|membership in rangeItems a b 1 iff a <= x < b
mem_rangeItems_pos|O|membership in rangeItems for a positive step; order not stated
natDigits_pos|H|natDigits n is positive
num?_bool|E|a bool's number equals the int 1 or 0
numEq_int_comm|O|numEq on two ints is symmetric
numEq_int_float_comm|O|numEq int/float equals numEq float/int (rfl)
numLt_int_trichotomy|O|on ints exactly one of numLt, numEq, reversed numLt holds
num_nan|E|numEq and numLt between an int and NaN are false
numberTextModelled_append|H|numberTextModelled of a concatenation is the conjunction
numberTextModelled_iff|H|numberTextModelled s iff every character is below 128
parseIntStr_iff|C|parseIntStr s = some n iff PyIntSpec s.toList n (wrapper of parseIntChars_iff)
printable_of_pyRepr_ok|H|pyRepr v ok implies Printable v
pyRepr_empty|E|pyRepr of empty list, tuple, dict
pyRepr_list|E|pyRepr of a list is the bracketed join of item reprs
pyRepr_ok_iff|O|pyRepr succeeds exactly on Printable values; output text not stated
pyRepr_ok_of_printable|H|Printable v implies pyRepr v ok
pyRepr_range_one|E|pyRepr of range with step 1 omits the step
pyRepr_tuple_singleton|E|pyRepr of a one-element tuple has a trailing comma
pyStr_consts|E|pyStr of None, True, False
pyStr_datetime|E|pyStr of a datetime is isoformat; pyRepr of it is an error
pyStr_eq_pyRepr|O|pyStr = pyRepr unless the value is str, datetime or timedelta
pyStr_list_str|E|pyStr of a one-string list uses strRepr inside brackets
pyStr_str|E|pyStr of a string is itself; pyRepr is strRepr
pyStr_timedelta|E|pyStr and pyRepr of a timedelta are tdStr and tdRepr
pyStr_undef|E|pyStr of undef is the empty string
rangeItems_eq_nil_iff|O|rangeItems is empty iff step 0 or start already past stop
rangeItems_one_length|O|length of rangeItems a b 1 is (b - a).toNat
rangeItems_step_zero|E|rangeItems with step 0 is empty
ratToFloat_zero|E|ratToFloat of numerator 0 is signed zero
reprDict_ok_iff|H|reprDict succeeds iff every key and value reprs
reprList_eq_mapM|H|reprList equals mapM pyRepr
reprList_ok_iff|H|reprList succeeds iff every item reprs
stateEq_fields|O|stateEq true implies equal entity id and state string
strRepr_apostrophe|E|strRepr "it's" uses double quotes
strRepr_empty|E|strRepr "" is two single quotes
strRepr_plain|O|strRepr of a string without quote, backslash, control chars is it single-quoted
truthy_range|E|truthy of a range iff it has an item (one constructor)
typeName_of_num|H|values with num? have typeName bool, int or float
''')
add('TimeSpec','''
Civil.valid_eq_none_iff|C|Civil.valid c = none iff all fields are in datetime's ranges
cast_aux|H|Nat to Int cast of a sum-product equation
civilFromDays_daysFromCivil|O|civilFromDays inverts daysFromCivil on valid month/day
civilFromDays_valid|O|civilFromDays returns month 1..12 and a day existing in it
civilFromDays_zero|E|civilFromDays 0 = (1970,1,1)
civil_eq|H|civilFromDays unfolded through private gg/ff
civil_of_parts|H|civilFromDays from era, year-of-era and day-of-year
civil_spec|H|existence of era/yoe/doy decomposition for civilFromDays
daysFromCivil_add_400|O|daysFromCivil shifts by 146097 per 400 years
daysFromCivil_civilFromDays|O|daysFromCivil inverts civilFromDays for every day number
daysFromCivil_epoch|E|daysFromCivil 1970 1 1 = 0
daysFromCivil_inj|O|daysFromCivil is injective on valid dates
daysFromCivil_next_month|O|first of next month is daysInMonth days later
daysFromCivil_next_year|O|1 January follows 31 December
daysFromCivil_succ_day|O|next day of month is next day number
daysFromCivil_year_length|O|a year is 366 days if isLeap else 365
daysInMonth_bounds|O|daysInMonth is between 28 and 31
daysInMonth_facts|H|bounds on a day within daysInMonth by month kind
daysInMonth_feb|O|February has 29 days iff isLeap
daysInMonth_of_ne_feb|O|month length does not depend on year except February
fdivmod_day|H|fdivmod by the day length equals Int / and %
fdivmod_spec|O|for b > 0: a = q*b + r and 0 <= r < b
fdivmod_unique|C|b > 0: fdivmod is the unique (q,r) with a = q*b+r, 0<=r<b
ff_hi|H|bounds on private ff
fromCivil_inj|O|fromCivil is injective on valid Civil values
fromCivil_toCivil|O|fromCivil (toCivil w) = w for every w
gg_ends|H|private gg at first and last day of each year of era (decide)
gg_mono|H|private gg is monotone
gg_step|H|private gg does not decrease in one step
isLeap_add_400|O|isLeap is periodic with period 400
isLeap_iff|C|isLeap y iff divisible by 4 and not 100, or by 400
isLeap_of_not_century|O|for non-century years isLeap is divisibility by 4
isoformat_epoch|E|isoformat of 0, naive and UTC (decide)
isoformat_some|O|aware isoformat is naive isoformat of the wall clock plus offsetStr
lp_iff|H|private leap predicate lp unfolded
month_inv|H|arithmetic: month index recovered from day of year
name_tables|E|abbreviated names are first three letters of full names (decide)
offsetStr_sign|H|offsetStr starts with - for negative offsets, + otherwise
offsetStr_zero|E|offsetStr 0 is "+00:00" / "+0000"
pad0_length|H|length of pad0 n w is max w and digit count
pad0_of_le|H|pad0 leaves a number that fills the width unchanged
pad0_toList|H|pad0 n w is zeros followed by decimal n
padYear_length|H|padYear of non-negative year has at least 4 characters
padYear_of_nonneg|H|padYear of non-negative year is pad0 to width 4
tdParts_neg_one|E|tdParts (-1) = (-1, 86399, 999999)
tdParts_spec|O|tdParts gives seconds < 86400, micros < 10^6, parts sum to input
tdParts_unique|C|tdParts of d*86400e6 + s*1e6 + u with s, u in range is (d,s,u)
tdRepr_neg_one|E|tdRepr (-1) literal
tdRepr_zero|E|tdRepr 0 literal
tdStr_neg_one|E|tdStr (-1) literal
tdStr_zero|E|tdStr 0 literal
time_join|H|arithmetic on seconds*10^6 + micros
time_split|H|arithmetic: time-of-day fields recombine (Nat)
time_split_int|H|arithmetic: time-of-day fields recombine (Int)
toCivil_fromCivil|O|toCivil (fromCivil c) = c when month, day, time fields are in range
toCivil_fromCivil_of_valid|O|toCivil (fromCivil c) = c when c.valid = none
toCivil_ranges|O|toCivil fields other than year are always in range
toCivil_valid|O|toCivil w is valid when its year is in 1..9999
toCivil_zero|E|toCivil 0 is 1970-01-01 00:00:00
toList_pushn|H|toList of String.pushn
us_day|H|US_PER_DAY = 86400000000
us_sec|H|US_PER_SEC = 1000000
wallOf_none|H|wallOf of a naive datetime is its microseconds
wallOf_some|H|wallOf of an aware datetime adds offset seconds
weekdayOf_add_week|O|weekdayOf is periodic with 7 days
weekdayOf_epoch|E|weekdayOf 0 = 3
weekdayOf_eq_of_day|O|weekdayOf depends only on the day
weekdayOf_fromCivil|O|weekdayOf (fromCivil c) = (daysFromCivil + 3) mod 7
weekdayOf_lt|O|weekdayOf w < 7
weekdayOf_next_day|O|next day has the next weekday mod 7
yoe_ex|H|every day of era lies in one of 400 years (private ff)
yoe_of|H|year of era recovered from day of era (private gg)
''')
add('DateParseSpec','''
dateOk_day_le|O|dateOk implies day <= 31
dateOk_iff|C|dateOk y m d iff year 1..9999, month 1..12, day 1..daysInMonth
dateOk_iff_valid|O|dateOk agrees with Civil.valid at midnight
dayNum_epoch|E|dayNum 1970 1 1 = 0
dayNum_succ|O|dayNum of day + 1 is dayNum + 1
dropWhile_space|H|a list is spaces followed by its dropWhile-space rest
emod_eq|H|Int.emod a b = a % b (rfl)
fromIsoCalendar_bad_week|O|week <= 0 or >= 54 with valid year gives "Invalid week" error
fromIsoCalendar_bad_weekday|O|weekday outside 1..7 with week 1..52 gives "Invalid weekday" error
fromIsoCalendar_bad_year|O|year outside 1..9999 gives "Year is out of range" error
fromIsoCalendar_ok|O|a successful result is the date at Monday-of-week-1 + 7(week-1) + day-1
getTimestring_zero|E|getTimestring 0 p = "0 seconds" (rfl)
isAscii_append|H|isAscii of a concatenation is the conjunction
isAscii_eq_numberTextModelled|H|isAscii and numberTextModelled are the same function
isAscii_iff|H|isAscii s iff every character is below 128
isPyWsAscii_iff|H|isPyWsAscii c iff code 32, 9..13 or 28..31
locale_names|E|strptime name tables are lower-cased strftime tables (decide)
rstripSpaces_idem|O|rstripSpaces is idempotent
rstripSpaces_of_no_trailing|O|rstripSpaces leaves text not ending in a space unchanged
rstripSpaces_spec|C|rstripSpaces s is s minus trailing spaces and does not end in a space
seqToRE_shape|O|seqToRE gives one named group with one alternative per non-empty name
tdChecked_eq_ok|O|tdChecked returns its argument when ok
tdChecked_ok_iff|C|tdChecked us = ok us iff us within timedelta's microsecond range
timeRE_aliases|E|timeRE entries for e/d, k/H, l/I, P/p are equal (rfl)
timeRE_isSome_iff|O|timeRE k is defined iff k is in a 45-key list; values not stated
timeRE_unsupported|E|16 listed locale/zone directives map to an error
timedeltaNew_inf|E|timedeltaNew with an infinite first float component is an OverflowError
timedeltaNew_nan|E|timedeltaNew with a NaN first float component is a valueError
timedeltaNew_str|E|timedeltaNew with a string first component is a valueError
us_day|H|US_PER_DAY = 86400000000
''')
add('SyntaxSpec2','''
advance_run|H|parser primitive advance drops one token (rfl)
compile_isStatic|O|a compiled Tmpl has isStatic = !isTemplateString raw and src = raw.trim
compile_static|E|compile of text without Jinja opening is the static Tmpl with one text node
dropLeadingWs_fix|H|dropLeadingWs leaves text with a non-whitespace head unchanged
dropLeadingWs_head|H|dropLeadingWs result does not start with whitespace
dropLeadingWs_idem|H|dropLeadingWs is idempotent
dropLeadingWs_suffix|H|dropLeadingWs result is a suffix of the input
dropWhile_head|H|head of dropWhile p does not satisfy p
dropWhile_idem|H|dropWhile is idempotent
expectKw_op|H|expectKw on an operator token is an error
expectKw_run|H|expectKw consumes the matching name token
expectName_iff|H|expectName succeeds iff next token is a name; consumes it
expectOp_iff|H|expectOp o succeeds iff next token is operator o; consumes it
expect_eof|H|expectOp and expectName fail on an empty token list
isNameChar_digit|H|a digit is a name character but not a name start
isNameChar_iff|H|isNameChar iff isNameStart or digit
isNameStart_isNameChar|H|a name-start character is a name character
isNameStart_underscore|H|underscore is a name start and a name character
isName_run|H|isName returns a Bool and consumes nothing
isOp_run|H|isOp returns a Bool and consumes nothing
parseStmt_invalid|E|parseStmt of [] or of an operator-first block is a fixed error (rfl)
parseStmt_keywords|E|parseStmt of the five one-word tags (rfl on literal token lists)
peek2_run|H|peek2 returns the second token without consuming (rfl)
peek_run|H|peek returns the first token without consuming (rfl)
runExpr_error|H|runExpr passes a parser error on
runExpr_iff|H|runExpr p succeeds iff p succeeds with no tokens left
startsPrimary_literal|H|startsPrimary on str/int/float tokens true, on none/close false
startsPrimary_name|H|startsPrimary on a name iff not else/or/and
startsPrimary_op|H|startsPrimary on an operator iff it is (, [ or {
stripRight_idem|H|stripRight is idempotent
stripRight_last|H|stripRight result does not end with whitespace
stripRight_prefix|H|stripRight result is a prefix of the input
unescape_bad_hex|E|two literal bad \\x escapes are errors
unescape_escapes|E|seven literal escape examples
unescape_go_plain|H|unescape.go on backslash-free text appends it
unescape_plain|O|unescape of backslash-free characters is the same text
''')
add('RenderSpec','''
ceilF_some|O|ceilF result is floatToInt? value or one above
cvBoolean_int|E|cvBoolean of an int is some true iff non-zero
cvBoolean_isSome|O|cvBoolean is defined only on bool, int, float, str
cvBoolean_str|E|cvBoolean of a string is cvBooleanText (rfl)
filterLifecycle_iff|C|RInfo.filterLifecycle iff static, exception, allStatesLifecycle or domain in domainsLifecycle
filter_all|O|static, exception or allStates makes RInfo.filter true
filter_iff|C|RInfo.filter iff static, exception, allStates, entity recorded or domain recorded
filter_of_mem|O|a recorded entity passes RInfo.filter
floorF_ceilF|O|floorF and ceilF are defined on the same floats
floorF_some|O|floorF result is floatToInt? value or one below
fracOf_int|H|fracOf of an int has denominator 1 and its sign/magnitude
iif_default|E|iif with no branches returns bool of truthy
iif_none_falsy|E|iif of None without if_none returns the false branch
iif_not_none|O|for non-None values if_none is ignored
isComplexOrStr_iff|H|isComplexOrStr iff string or opaque "complex"
isIterable_scalar|O|isIterable excludes None, bool, int, float, datetime, timedelta
isOpaqueOrUndef_iff|H|isOpaqueOrUndef iff undef or opaque
listens_mono|O|listens while rate limited implies listens otherwise
listens_of_filter|O|non-static non-exception info: filter or filterLifecycle implies listens
listens_rateLimited|O|while rate limited listens iff entity recorded
lookupKV_cons|H|lookupKV on cons unfolds to a pyEq test (pyEq opaque)
lookupKV_none_iff|H|lookupKV none iff no key is pyEq to the key (pyEq opaque)
lookupKV_some|H|lookupKV result belongs to an entry whose key is pyEq (pyEq opaque)
parseTime_none_iff|O|parseTime fails iff parseTimeSeconds fails
parseTime_some|O|parseTime (h,m,s) recombines to parseTimeSeconds total, m,s < 60
rateLimit_eq_all_iff|C|rateLimit = 60 iff non-static and (allStates or exception)
rateLimit_eq_domain_iff|C|rateLimit = 1 iff non-static, no allStates/exception, some domain recorded
rateLimit_eq_none_iff|C|rateLimit = none iff static or nothing but entities recorded
rateLimit_static|E|static info has no rate limit
rateLimit_values|O|a rate limit is 60 or 1
resultAsBoolean_bool|E|resultAsBoolean of a bool is that bool
resultAsBoolean_iff|C|resultAsBoolean v iff cvBoolean v = some true
resultAsBoolean_list|E|resultAsBoolean of a list is false (rfl)
roundHalfEven_iff|H|roundHalfEven n d = r iff IsRoundHalfEven n d r (internal helper)
roundHalfEven_mul|H|roundHalfEven of an exact multiple is the quotient
roundHalfEven_one|H|roundHalfEven n 1 = n
roundHalfEven_spec|H|roundHalfEven satisfies IsRoundHalfEven
roundHalfEven_unique|H|IsRoundHalfEven determines roundHalfEven
scaledUs_bool|H|scaledUs of a bool equals scaledUs of int 1 or 0
scaledUs_int|H|scaledUs of an int with denominator 1 is the product
scaledUs_isSome|H|scaledUs is defined only on bool, int, float
scaledUs_neg|H|scaledUs of -i is the negation of scaledUs of i
seqIndex_eq|C|seqIndex xs i by sign of i with bounds (restates the definition)
seqIndex_isSome_iff|O|seqIndex is defined iff -len <= i < len
seqIndex_last|E|seqIndex xs (-1) is getLast?
seqIndex_mem|O|an indexed item is a member of the list
seqIndex_neg|O|seqIndex xs (-k) = xs[len-k]? for 0 < k <= len
seqIndex_nonneg|O|seqIndex at a natural index is xs[i]?
statesOf_all|O|statesOf none maps every state to a non-collecting state value
statesOf_length_le|O|statesOf yields at most all states
statesOf_mem|O|members of statesOf (some d) are states of domain d
utcFromTimestamp_int|E|utcFromTimestamp of an int, when defined, is i*10^6 microseconds UTC
utcFromTimestamp_some|O|a utcFromTimestamp result is scaledUs microseconds UTC with year 1..9999
utcFromTimestamp_str|E|utcFromTimestamp of a string is none (rfl)
''')
add('RenderSpec2','''
compile_render_static|E|text without Jinja opening compiles and renders unparsed to raw.trim
dropWhile_fix|H|dropWhile leaves a list whose head fails p unchanged
dropWhile_head|H|head of dropWhile p does not satisfy p
dropWhile_idem|H|dropWhile is idempotent
dropWhile_rstrip|H|right-stripping keeps the left end stripped
drop_takeWhile_length|H|drop of takeWhile length is dropWhile
filterMap_congr'|H|filterMap congruence on members
isAlpha_toLower|H|toLower preserves isAlpha
isAlpha_toUpper|H|toUpper preserves isAlpha
isNumericStr_eq|H|isNumericStr is private numBody after an optional sign
isNumericStr_iff|C|isNumericStr s iff s matches the grammar IsNumericSpec (ASCII digits)
join_chars|H|joining single-character strings gives the string
mem_takeWhile_true|H|members of takeWhile p satisfy p
numBody_iff|H|private numBody iff digits, optional fraction, no leading zero
parseResult_str|O|if parseResult r is a string then it is r
prefix_head|H|a prefix shares the head
pyCapitalize_cons|C|pyCapitalize of a non-empty string: first toUpper, rest toLower
pyCapitalize_idem|O|pyCapitalize is idempotent
pyCapitalize_length|O|pyCapitalize keeps the length
pyReplace_empty_all|E|pyReplace with empty pattern and negative count interleaves new
pyReplace_empty_empty|E|pyReplace "" "" new (-1) = new
pyReplace_empty_zero|E|pyReplace with empty pattern and count 0 is identity
pyStrip_both|O|strip both ends equals lstrip then rstrip
pyStrip_fix|O|pyStrip leaves text with unstrippable ends unchanged
pyStrip_head|O|after left strip the first character is not in the strip set
pyStrip_idem|O|pyStrip is idempotent
pyStrip_infix|O|pyStrip result is a contiguous part of the input
pyStrip_last|O|after right strip the last character is not in the strip set
pyStrip_neither|E|pyStrip with neither end is identity
pyStrip_toList|C|pyStrip characters equal dropWhile of stripSet from the chosen ends
pyTitle_eq|C|pyTitle equals the reference recursion titleSpec
pyTitle_idem|O|pyTitle is idempotent
pyTitle_length|O|pyTitle keeps the length
pyTitle_no_alpha|O|pyTitle leaves text without letters unchanged
range_getElem_take|H|filterMap over a range equals drop then take
range_rev|H|filterMap over reversed indices equals reverse
renderString_static|E|renderString of a static Tmpl is its src
renderWithInfo_error|O|an erroring renderWithInfo sets exception, so filter is always true
renderWithInfo_fst|O|first component of renderWithInfo equals render
renderWithInfo_static|E|static Tmpl: result src, info static, no rate limit
render_parsed|O|render with parse = map parseResult over renderString
render_unparsed|O|render without parse = map Value.str over renderString
replaceGo_all|H|pyReplace.go with enough count interleaves new
replaceGo_zero|H|pyReplace.go with count 0 joins the parts
sliceList_all|E|sliceList with no bounds returns the list
sliceList_last|E|sliceList from -k is the last k items
sliceList_nat|O|sliceList with natural bounds is take b then drop a
sliceList_reverse|E|sliceList with step -1 and no bounds is reverse
sliceList_step_one|O|sliceList without step is take/drop at clamped bounds
sliceList_step_zero|E|sliceList with step 0 is an error (rfl)
sliceList_subset|O|slice items are members of the list
sliceList_total|O|sliceList succeeds for every non-zero step
takeWhile_digits|H|takeWhile isDigit on digits ++ fraction is the digits
titleSpec_idem|H|reference recursion titleSpec is idempotent
titleSpec_length|H|titleSpec keeps the length
title_loop|H|the forIn loop of pyTitle equals titleSpec
toLower_idem|H|Char.toLower is idempotent
toUpper_idem|H|Char.toUpper is idempotent
''')
add('RenderSpec3','''
Args_checkStrict_pos|H|Args.checkStrict passes without keywords and few enough positionals
Args_check_pos|H|Args.check without keywords passes iff positionals fit
Args_get_kw|H|Args.get past the positionals is the keyword lookup
Args_get_kw_mem|H|a returned keyword argument was passed under that name
Args_get_pos|H|Args.get within the positionals returns the positional
arith_concat|E|arith "+" on two strings or two lists concatenates (rfl)
arith_int|E|arith +, -, * on two ints (rfl)
arith_int_div_zero|E|arith //, %, / of an int by int 0 is an error (rfl)
arith_int_divmod|E|arith // and % on ints with non-zero divisor are fdiv and fmod
arith_naive_aware|E|subtracting aware from naive datetime is an error (rfl)
arith_timedelta|E|arith on two timedeltas or two aware datetimes (rfl)
arith_undef|E|arith with an undef left operand is an error (rfl)
asLocal_aware|E|asLocal of an aware datetime keeps the instant, sets engine offset (rfl)
asLocal_error|E|asLocal of a string is an error (rfl)
asLocal_idem|O|asLocal applied twice to a datetime equals once
asciiOnly_iff|H|asciiOnly passes iff all characters are below 128
attrParts_cases|E|attrParts of None is [] and of an int is that int
attrPath_nil|E|attrPath with an empty path returns the item (rfl)
checkDate_iff|H|checkDate accepts iff the wall-clock year is in 1..9999
cmpOp_ne|O|cmpOp "!=" is the negation of cmpOp "=="
cmpOp_notin|E|cmpOp in/notin on a list is any pyEq / its negation (pyEq opaque)
cmpOp_opaque|E|cmpOp with an opaque left operand is an error (rfl)
collectAll_filter|H|after collectAll false every entity passes RInfo.filter
collectAll_spec|H|collectAll sets the matching all-states flag
collectDomain_spec|H|collectDomain appends the domain to the matching list only
collectTime_spec|H|collectTime sets hasTime
collect_frame|H|collect changes only the entity list
collect_idem|H|collect twice equals once
collect_mem|H|collect succeeds and the entity is recorded
collect_mono|H|collect keeps earlier entities
collect_nodup|H|collect keeps the entity list duplicate-free
collect_of_mem|H|collect of a recorded entity changes nothing
containsV_dict|E|containsV on a dict is lookupKV isSome (rfl)
containsV_list|E|containsV on a list is any pyEq (rfl; pyEq opaque)
containsV_str|E|"" in any string is true; int in string is an error
containsV_undef|E|containsV on undef is false (rfl)
datetimeAsString_passthrough|E|datetimeAsString of a string returns it and sets hasTime (rfl)
doInt_int|E|doInt of an int or bool (rfl)
doInt_none|E|doInt of None or a list is none (rfl)
doSort_nil|E|doSort of [] is the empty list
doUnique_nil|E|doUnique of [] is an empty generator (rfl)
forgivingBool_default|O|forgivingBool with a default: cvBoolean result or the default, non-opaque input
forgivingBool_no_default|O|forgivingBool without default errors when cvBoolean rejects
forgivingFloat_default|O|forgivingFloat with a default returns a float or the default
forgivingFloat_float|E|forgivingFloat of a float is itself (rfl)
forgivingFloat_none|E|forgivingFloat of None without default is an error
forgivingInt_bool|E|forgivingInt of a bool is 1 or 0 (rfl)
forgivingInt_int|E|forgivingInt of an int is itself (rfl)
forgivingInt_none|E|forgivingInt of None is the default, or an error without one
forgivingRound_bad_precision|E|forgivingRound with a string precision is an error (rfl)
getitemV_dict|E|getitemV on a dict returns the lookupKV value when present
getitemV_list|E|getitemV on a list by int is seqIndex or undef (rfl)
getitemV_none|E|None[k] is undef; undef[k] is an error (rfl)
hasValue_collects|O|hasValue with a string id records the entity
hasValue_iff|C|hasValue of a string id is ok true iff state exists, not unavailable/unknown
hasValue_nonstr|O|hasValue of a non-string is false, state unchanged
hassStatesGet_some|O|hassStatesGet returns a state stored under exactly that id
ignoreCase_nonstr|O|ignoreCase leaves non-strings unchanged
isNumber_none|E|isNumber of None or a list is false
isNumber_total|O|isNumber does not error on non-undef, non-opaque values
isState_collects|O|isState with a string id records the entity
isState_list|O|isState is true when a list item is pyEq to the state (pyEq opaque)
isState_missing|O|isState of a missing entity is false
isState_nonstr|O|isState of a non-string id is false, nothing recorded
isState_true|O|isState is true when pyEq (state string) v holds (pyEq opaque)
iterVList_domain|E|iterVList of a domain yields its states and records both domain lists
iterVList_list|E|iterVList of a list is the list (rfl)
iterV_allStates|E|iterV of allStates yields all states and sets allStates
iterV_dict|E|iterV of a dict yields its keys (rfl)
iterV_domain|E|iterV of a domain yields its states and records the domain
iterV_list|E|iterV of list, tuple, undef (rfl)
iterV_scalar|E|iterV of an int or None is an error (rfl)
lenV_eq_iterV_length|O|for list, tuple, dict, str, range, undef lenV equals iterV length
liftExcept_eq|H|liftExcept keeps result and state
minOrMax_empty|E|minOrMax of [] is a fixed undef (rfl)
needStr_iff|H|needStr returns t iff the value is the string t
noDefault_error|H|noDefault always errors (rfl)
pyRound_nonfinite|E|pyRound leaves NaN and infinities unchanged
pySplit_empty_sep|E|pySplit with empty separator is a ValueError (rfl)
pySplit_length_le|O|pySplit with separator and maxsplit m gives at most m+1 parts
pySplit_unlimited|O|pySplit with non-empty separator and negative maxsplit is String.splitOn
sortKey_caseSensitive|H|case-sensitive sortKey is attrPath
stateAttrFn_missing|O|stateAttrFn of a missing entity is None and records the entity
stateAttrFn_nonstr|O|stateAttrFn of a non-string id is None
stateAttr_no_collect|E|stateAttr "state" on a non-collecting state returns it, state unchanged (rfl)
stateAttr_state|E|stateAttr "state" on a collecting state returns it and records the entity
stateIfValid_invalid|O|stateIfValid of a missing, invalid id is an error
stateIfValid_some|O|stateIfValid of an existing id is its collecting state value
strOf_eq|H|strOf is pyStr lifted into R
tick_bound|H|tick keeps steps <= MAX_STEPS
tick_error|H|tick at the budget is a fixed error
tick_ok|H|tick under the budget increments steps
tick_ok_iff|H|tick succeeds iff steps < MAX_STEPS
timestampOf_error|E|timestampOf of a naive datetime or an int is an error (rfl)
toFloat_cases|E|toFloat? per constructor: float, int, str, None, list, dict
toFloat_total|O|toFloat? does not error on non-undef, non-opaque values
undefErr_error|H|undefErr always errors
''')
rows=[l.rstrip('\n').split('\t') for l in open('logs/theorems.tsv')]
mine=[r for r in rows if r[0].startswith('HALean.Template.')]
out=[];used=set()
for r in mine:
    mod=r[0].split('.')[-1]; n=r[1][len('HALean.Template.'):]
    if (mod,n) not in D: print('MISSING',mod,n); continue
    c,rs=D[(mod,n)]; used.add((mod,n)); out.append(f"{r[0]}\t{r[1]}\t{c}\t{rs}")
for k in D:
    if k not in used: print('EXTRA',k)
open('class/templates.tsv','w').write('\n'.join(out)+'\n')
print(len(mine),len(out),collections.Counter(l.split('\t')[2] for l in out))
pm=collections.defaultdict(collections.Counter)
for l in out:
    f=l.split('\t'); pm[f[0].split('.')[-1]][f[2]]+=1
for m in sorted(pm): print(m,dict(pm[m]),sum(pm[m].values()))
print([l.split('\t')[1].replace('HALean.Template.','') for l in out if l.split('\t')[2]=='C'])
