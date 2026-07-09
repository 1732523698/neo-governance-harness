# orch_schema.ps1 - NEO 4.0-P3-B (B1) governance-critical schema + hashing library.
# ASCII-only (D10). Dot-source it; it defines functions, runs nothing on load.
#
# Provides:
#   Get-NeoSchemaIndex   - index the installed spine schemas by their "$id"
#   Test-NeoSchema       - $ref-resolving JSON-Schema validator (FAIL-CLOSED)
#   Get-NeoCanonicalJson - deterministic canonical serialization (sorted keys)
#   Get-NeoBodyHash      - sha256 of an artifact body with named keys excluded
#   Get-NeoSha256File    - sha256 hex of an on-disk file
#
# FAIL-CLOSED DESIGN (crown jewel #6): the validator implements exactly the
# keywords the installed spine uses. Any schema keyword it does NOT implement,
# any unknown "$id", or any unresolvable "$ref" produces a BLOCK violation --
# it NEVER silently ignores a validating keyword, so it can never under-validate.

# ---- keyword governance -----------------------------------------------------
$script:NeoAnnotationKeys = @(
  '$schema','$id','title','description','default','examples','$comment',
  '_status','_home','_reconcile','_comment','_blocking_reconciliation_gate'
)
$script:NeoSupportedKeys = @(
  'type','required','properties','additionalProperties','items','enum','const',
  'minLength','minItems','maxItems','minimum','$ref','allOf','if','then','else','pattern'
)

# ---- low-level JSON value helpers -------------------------------------------
function Test-NeoIsObject($v) {
  if ($null -eq $v) { return $false }
  if ($v -is [array]) { return $false }
  return (($v -is [System.Management.Automation.PSCustomObject]) -or ($v -is [hashtable]))
}

function Test-NeoHasProp($o, $name) {
  if ($o -is [hashtable]) { return $o.ContainsKey($name) }
  return ($null -ne $o.PSObject.Properties[$name])
}

# Get-NeoProp: natural access for SCHEMA-KEYWORD reads. Multi-element arrays
# (enum, required, allOf, type-unions) return intact; callers wrap scalar/single
# results with @(...) where they iterate. Do NOT use this for instance DATA that
# must preserve single-element-array shape -- use Get-NeoVal for that.
function Get-NeoProp($o, $name) {
  if ($o -is [hashtable]) { return $o[$name] }
  $p = $o.PSObject.Properties[$name]
  if ($p) { return $p.Value }
  return $null
}

# Get-NeoVal: shape-preserving access for INSTANCE DATA. Write-Output -NoEnumerate
# keeps a single-element array as an array (PowerShell would otherwise unwrap it
# on return), so type:array validation and round-trip hashing stay faithful.
function Get-NeoVal($o, $name) {
  if ($o -is [hashtable]) {
    if (-not $o.ContainsKey($name)) { return }
    Write-Output -NoEnumerate $o[$name]; return
  }
  $p = $o.PSObject.Properties[$name]
  if ($null -eq $p) { return }
  Write-Output -NoEnumerate $p.Value
}

function Get-NeoPropNames($o) {
  if ($o -is [hashtable]) { return @($o.Keys) }
  # Enumerate the property objects explicitly. `.PSObject.Properties.Name` on an
  # EMPTY PSCustomObject (e.g. ConvertFrom-Json of `{}`) yields a phantom single
  # null/empty name; iterating the collection returns a true-empty list instead.
  $names = @()
  foreach ($p in $o.PSObject.Properties) { $names += $p.Name }
  return $names
}

function Test-NeoType($v, $type) {
  switch ($type) {
    'object'  { return (Test-NeoIsObject $v) }
    'array'   { return ($v -is [array]) }
    'string'  { return ($v -is [string]) }
    'boolean' { return ($v -is [bool]) }
    'integer' {
      if ($v -is [bool]) { return $false }
      if ($v -is [int] -or $v -is [long]) { return $true }
      if ($v -is [double] -and ([math]::Floor($v) -eq $v)) { return $true }
      return $false
    }
    'number'  {
      if ($v -is [bool]) { return $false }
      return ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal])
    }
    'null'    { return ($null -eq $v) }
    default   { return $false }
  }
}

# ---- canonical serialization + hashing --------------------------------------
function ConvertTo-NeoJsonString([string]$s) {
  if ($null -eq $s) { $s = '' }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append([char]0x22)
  foreach ($c in $s.ToCharArray()) {
    $code = [int]$c
    if     ($c -eq [char]0x22) { [void]$sb.Append('\"') }
    elseif ($c -eq [char]0x5C) { [void]$sb.Append('\\') }
    elseif ($code -eq 8)  { [void]$sb.Append('\b') }
    elseif ($code -eq 12) { [void]$sb.Append('\f') }
    elseif ($code -eq 10) { [void]$sb.Append('\n') }
    elseif ($code -eq 13) { [void]$sb.Append('\r') }
    elseif ($code -eq 9)  { [void]$sb.Append('\t') }
    elseif ($code -lt 32) { [void]$sb.Append(('\u{0:x4}' -f $code)) }
    else   { [void]$sb.Append($c) }
  }
  [void]$sb.Append([char]0x22)
  return $sb.ToString()
}

function Get-NeoCanonicalJson($v) {
  if ($null -eq $v) { return 'null' }
  if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
  if ($v -is [string]) { return (ConvertTo-NeoJsonString $v) }
  if ($v -is [int] -or $v -is [long]) { return ([string]$v) }
  if ($v -is [double] -or $v -is [decimal]) {
    return ([double]$v).ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
  }
  if ($v -is [array]) {
    $parts = @()
    foreach ($it in $v) { $parts += (Get-NeoCanonicalJson $it) }
    return '[' + ($parts -join ',') + ']'
  }
  if (Test-NeoIsObject $v) {
    $names = @(Get-NeoPropNames $v)
    if ($names.Count -gt 1) { [Array]::Sort($names, [System.StringComparer]::Ordinal) }
    $parts = @()
    foreach ($n in $names) {
      $parts += ((ConvertTo-NeoJsonString ([string]$n)) + ':' + (Get-NeoCanonicalJson (Get-NeoVal $v $n)))
    }
    return '{' + ($parts -join ',') + '}'
  }
  return (ConvertTo-NeoJsonString ([string]$v))
}

# Structure-preserving pretty JSON writer. Unlike ConvertTo-Json (PS 5.1), this
# NEVER unwraps single-element arrays and never coerces types, so every evidence
# file round-trips (write -> ConvertFrom-Json) with arrays intact -- which both
# schema validation (type:array) and the body-hash depend on.
function ConvertTo-NeoPrettyJson($v, [int]$Indent = 0) {
  $pad  = ' ' * ($Indent * 2)
  $pad2 = ' ' * (($Indent + 1) * 2)
  if ($null -eq $v) { return 'null' }
  if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
  if ($v -is [string]) { return (ConvertTo-NeoJsonString $v) }
  if ($v -is [int] -or $v -is [long]) { return ([string]$v) }
  if ($v -is [double] -or $v -is [decimal]) {
    return ([double]$v).ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
  }
  if ($v -is [array]) {
    if ($v.Count -eq 0) { return '[]' }
    $items = @()
    foreach ($it in $v) { $items += ($pad2 + (ConvertTo-NeoPrettyJson $it ($Indent + 1))) }
    return "[`n" + ($items -join ",`n") + "`n$pad]"
  }
  if (Test-NeoIsObject $v) {
    $names = @(Get-NeoPropNames $v)
    if ($names.Count -eq 0) { return '{}' }
    $items = @()
    foreach ($n in $names) {
      $items += ($pad2 + (ConvertTo-NeoJsonString ([string]$n)) + ': ' + (ConvertTo-NeoPrettyJson (Get-NeoVal $v $n) ($Indent + 1)))
    }
    return "{`n" + ($items -join ",`n") + "`n$pad}"
  }
  return (ConvertTo-NeoJsonString ([string]$v))
}

function Get-NeoStringSha256([string]$s) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($s)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $hash = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
  return (-join ($hash | ForEach-Object { $_.ToString('x2') }))
}

function Get-NeoBodyHash($obj, [string[]]$ExcludeKeys) {
  $clone = @{}
  foreach ($n in (Get-NeoPropNames $obj)) {
    if ($ExcludeKeys -and ($ExcludeKeys -contains $n)) { continue }
    $clone[$n] = (Get-NeoVal $obj $n)
  }
  return (Get-NeoStringSha256 (Get-NeoCanonicalJson $clone))
}

function Get-NeoSha256File([string]$path) {
  return ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower())
}

# ---- bundle-member path safety (F2) -----------------------------------------
# A bundle member `rel` is root-relative and CONTAINED. Reject rooted, drive-
# qualified, UNC, backslash-bearing, empty, or `..`-traversing values BEFORE any
# Join-Path/read, at BOTH assembly and every independent re-hash (engine + auditor).
# Throws NEO-BLOCK directly so this stays usable wherever orch_schema is loaded.
function Assert-NeoSafeRel([string]$rel) {
  if ([string]::IsNullOrWhiteSpace($rel)) { throw "NEO-BLOCK: unsafe bundle member path (empty)" }
  if ($rel -match '\\')        { throw "NEO-BLOCK: unsafe bundle member path (backslash/UNC): '$rel'" }
  if ($rel -match '^/')        { throw "NEO-BLOCK: unsafe bundle member path (rooted): '$rel'" }
  if ($rel -match '^[A-Za-z]:'){ throw "NEO-BLOCK: unsafe bundle member path (drive-qualified): '$rel'" }
  $probe = $rel -replace '^\./', ''
  foreach ($seg in ($probe -split '/')) {
    if ($seg -eq '..') { throw "NEO-BLOCK: unsafe bundle member path (parent traversal): '$rel'" }
  }
}

# Defense-in-depth: after Assert-NeoSafeRel, resolve the joined path and assert it
# stays under the bundle root. Returns the safe full path.
function Assert-NeoContained([string]$BundleDir, [string]$rel) {
  $probe = $rel -replace '^\./', ''
  $root = [System.IO.Path]::GetFullPath((Join-Path $BundleDir '.'))
  $full = [System.IO.Path]::GetFullPath((Join-Path $BundleDir $probe))
  $rootWithSep = $root.TrimEnd([char]0x5C, [char]0x2F) + [System.IO.Path]::DirectorySeparatorChar
  if (-not $full.StartsWith($rootWithSep, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "NEO-BLOCK: bundle member escapes bundle root: '$rel' -> '$full' not under '$root'"
  }
  return $full
}

# ---- value equality (enum / const) ------------------------------------------
function Test-NeoIsNumber($v) {
  if ($v -is [bool]) { return $false }
  return (($v -is [int]) -or ($v -is [long]) -or ($v -is [double]) -or ($v -is [decimal]))
}

# JSON-TYPE-AWARE equality (F3). Unlike JSON types are NEVER equal: string "5" is not
# number 5. No [double] coercion is ever applied to a non-number (which would both
# equate unlike types and throw a raw exception on a non-numeric string). Any
# unavoidable numeric-coercion failure surfaces as NEO-BLOCK, never a raw throw.
function Test-NeoJsonEqual($a, $b) {
  if (($null -eq $a) -and ($null -eq $b)) { return $true }
  if (($null -eq $a) -or  ($null -eq $b)) { return $false }

  $aBool = ($a -is [bool]); $bBool = ($b -is [bool])
  if ($aBool -or $bBool) { return ($aBool -and $bBool -and ($a -eq $b)) }

  $aStr = ($a -is [string]); $bStr = ($b -is [string])
  if ($aStr -or $bStr) { return ($aStr -and $bStr -and ($a -ceq $b)) }

  $aComplex = ((Test-NeoIsObject $a) -or ($a -is [array]))
  $bComplex = ((Test-NeoIsObject $b) -or ($b -is [array]))
  if ($aComplex -or $bComplex) {
    if (-not ($aComplex -and $bComplex)) { return $false }
    return ((Get-NeoCanonicalJson $a) -ceq (Get-NeoCanonicalJson $b))
  }

  if ((Test-NeoIsNumber $a) -and (Test-NeoIsNumber $b)) {
    try { return ([double]$a -eq [double]$b) }
    catch { throw "NEO-BLOCK: numeric equality coercion failed in enum/const compare" }
  }
  return $false   # any remaining mixed/unknown JSON type => not equal
}

# ---- schema index -----------------------------------------------------------
function Get-NeoSchemaIndex([string]$SchemaDir) {
  if (-not (Test-Path -LiteralPath $SchemaDir)) { throw "NEO-BLOCK: schema dir not found: $SchemaDir" }
  $idx = @{}
  foreach ($f in (Get-ChildItem -LiteralPath $SchemaDir -Filter *.json -File)) {
    $doc = $null
    try { $doc = (Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { continue }
    if ($null -ne $doc -and $doc.PSObject.Properties['$id']) {
      $id = $doc.'$id'
      if ($id) { $idx[$id] = $doc }
    }
  }
  return $idx
}

# ---- preflight: schema well-formedness (F1, instance-INDEPENDENT) -----------
# Walks the WHOLE schema graph (following $ref with a cycle guard; into properties
# values, items, additionalProperties-as-schema, allOf[], and if/then/else) and
# returns a BLOCK for any non-object node, unsupported keyword, or unresolvable
# $ref -- regardless of instance or which branch an instance would take. Running
# this ONCE before instance evaluation guarantees a malformed/unsupported schema
# can never be mistaken for "instance did not match the if-condition" and thereby
# silently pass. Returns an array of violation strings; empty => well-formed.
function Test-NeoSchemaSupport {
  param($Schema, $Index, [string]$Path = '$', $Seen)
  if ($null -eq $Seen) { $Seen = @{} }
  $errs = New-Object System.Collections.ArrayList

  if (-not (Test-NeoIsObject $Schema)) {
    [void]$errs.Add("$Path : schema node is not an object => BLOCK")
    return @($errs.ToArray())
  }
  $keys = @(Get-NeoPropNames $Schema)

  if ($keys -contains '$ref') {
    $ref = Get-NeoProp $Schema '$ref'
    if (-not $Index.ContainsKey($ref)) {
      [void]$errs.Add("$Path : unresolvable `$ref '$ref' (unknown schema id) => BLOCK")
      return @($errs.ToArray())
    }
    if ($Seen.ContainsKey($ref)) { return @() }   # cycle guard: id already validated
    $Seen[$ref] = $true
    foreach ($ce in @(Test-NeoSchemaSupport -Schema $Index[$ref] -Index $Index -Path $Path -Seen $Seen)) { [void]$errs.Add($ce) }
    return @($errs.ToArray())                       # $ref: siblings ignored (draft-07)
  }

  foreach ($k in $keys) {
    if ($script:NeoAnnotationKeys -contains $k) { continue }
    if ($script:NeoSupportedKeys  -contains $k) { continue }
    [void]$errs.Add("$Path : unsupported schema keyword '$k' => fail-closed BLOCK")
  }

  if ($keys -contains 'properties') {
    $ps = Get-NeoProp $Schema 'properties'
    if (Test-NeoIsObject $ps) {
      foreach ($pn in @(Get-NeoPropNames $ps)) {
        foreach ($ce in @(Test-NeoSchemaSupport -Schema (Get-NeoProp $ps $pn) -Index $Index -Path "$Path.$pn" -Seen $Seen)) { [void]$errs.Add($ce) }
      }
    } else { [void]$errs.Add("$Path.properties : not an object => BLOCK") }
  }
  if ($keys -contains 'items') {
    foreach ($ce in @(Test-NeoSchemaSupport -Schema (Get-NeoProp $Schema 'items') -Index $Index -Path "$Path.items" -Seen $Seen)) { [void]$errs.Add($ce) }
  }
  if ($keys -contains 'additionalProperties') {
    $ap = Get-NeoProp $Schema 'additionalProperties'
    if ($ap -is [bool]) { }
    elseif (Test-NeoIsObject $ap) {
      foreach ($ce in @(Test-NeoSchemaSupport -Schema $ap -Index $Index -Path "$Path.additionalProperties" -Seen $Seen)) { [void]$errs.Add($ce) }
    }
    else { [void]$errs.Add("$Path.additionalProperties : must be a boolean or a schema object => BLOCK") }
  }
  if ($keys -contains 'allOf') {
    $i = 0
    foreach ($sub in @(Get-NeoProp $Schema 'allOf')) {
      foreach ($ce in @(Test-NeoSchemaSupport -Schema $sub -Index $Index -Path "$Path.allOf[$i]" -Seen $Seen)) { [void]$errs.Add($ce) }
      $i++
    }
  }
  foreach ($kw in @('if', 'then', 'else')) {
    if ($keys -contains $kw) {
      foreach ($ce in @(Test-NeoSchemaSupport -Schema (Get-NeoProp $Schema $kw) -Index $Index -Path "$Path.$kw" -Seen $Seen)) { [void]$errs.Add($ce) }
    }
  }

  return @($errs.ToArray())
}

# ---- the validator ----------------------------------------------------------
# Returns an array of violation strings; empty array => valid.
function Test-NeoSchema {
  param($Instance, $Schema, $Index, [string]$Path = '$', [switch]$NoPreflight, $RefChain)
  $errs = New-Object System.Collections.ArrayList
  # Residual (b): instance-pass $ref cycle guard, mirroring the preflight's $Seen guard.
  # $RefChain is the set of schema ids resolved by $ref at THIS instance node without an
  # intervening instance descent. It is reset (fresh) when we recurse into a new instance
  # node (properties/items/additionalProperties) and carried across same-node recursions
  # (allOf/if/then/else). Each $ref resolution passes a CLONE so allOf siblings cannot
  # pollute each other's chain (which would under-validate). A finite instance always
  # terminates; a pure schema $ref-cycle (no instance consumption) is broken here.
  if ($null -eq $RefChain) { $RefChain = @{} }

  # F1: preflight the WHOLE schema graph ONCE (top-level only). A malformed/
  # unsupported schema construct is a fail-closed BLOCK before any instance
  # evaluation, so it can never be swallowed as an unmet if-condition.
  if (-not $NoPreflight) {
    $support = @(Test-NeoSchemaSupport -Schema $Schema -Index $Index -Path $Path)
    if ($support.Count -gt 0) { return @($support) }
  }

  if (-not (Test-NeoIsObject $Schema)) {
    [void]$errs.Add("$Path : schema node is not an object => BLOCK")
    return @($errs.ToArray())
  }
  $keys = @(Get-NeoPropNames $Schema)

  # $ref short-circuits (draft-07: siblings ignored)
  if ($keys -contains '$ref') {
    $ref = Get-NeoProp $Schema '$ref'
    if (-not $Index.ContainsKey($ref)) {
      [void]$errs.Add("$Path : unresolvable `$ref '$ref' (unknown schema id) => BLOCK")
      return @($errs.ToArray())
    }
    if ($RefChain.ContainsKey($ref)) { return @() }   # cycle guard: $ref active on this instance node
    $next = @{}; foreach ($k in $RefChain.Keys) { $next[$k] = $true }; $next[$ref] = $true
    return @(Test-NeoSchema -Instance $Instance -Schema $Index[$ref] -Index $Index -Path $Path -NoPreflight -RefChain $next)
  }

  # FAIL-CLOSED: reject any keyword we do not implement (never under-validate)
  foreach ($k in $keys) {
    if ($script:NeoAnnotationKeys -contains $k) { continue }
    if ($script:NeoSupportedKeys  -contains $k) { continue }
    [void]$errs.Add("$Path : unsupported schema keyword '$k' => fail-closed BLOCK")
  }
  if ($errs.Count -gt 0) { return @($errs.ToArray()) }

  # type
  if ($keys -contains 'type') {
    $t = Get-NeoProp $Schema 'type'
    $types = @(); if ($t -is [array]) { $types = @($t) } else { $types = @($t) }
    $ok = $false
    foreach ($tt in $types) { if (Test-NeoType $Instance $tt) { $ok = $true; break } }
    if (-not $ok) {
      [void]$errs.Add("$Path : type mismatch (expected $($types -join '|'))")
      return @($errs.ToArray())
    }
  }

  # enum / const
  if ($keys -contains 'enum') {
    $en = @(Get-NeoProp $Schema 'enum'); $match = $false
    foreach ($e in $en) { if (Test-NeoJsonEqual $Instance $e) { $match = $true; break } }
    if (-not $match) { [void]$errs.Add("$Path : value not in enum") }
  }
  if ($keys -contains 'const') {
    if (-not (Test-NeoJsonEqual $Instance (Get-NeoProp $Schema 'const'))) {
      [void]$errs.Add("$Path : value != const")
    }
  }

  # scalar facets
  if (($keys -contains 'minLength') -and ($Instance -is [string])) {
    if ($Instance.Length -lt [int](Get-NeoProp $Schema 'minLength')) {
      [void]$errs.Add("$Path : shorter than minLength")
    }
  }
  if (($keys -contains 'pattern') -and ($Instance -is [string])) {
    if (-not [regex]::IsMatch($Instance, [string](Get-NeoProp $Schema 'pattern'))) {
      [void]$errs.Add("$Path : does not match pattern")
    }
  }
  if (($keys -contains 'minimum') -and (($Instance -is [int]) -or ($Instance -is [long]) -or ($Instance -is [double]) -or ($Instance -is [decimal]))) {
    if ([double]$Instance -lt [double](Get-NeoProp $Schema 'minimum')) {
      [void]$errs.Add("$Path : less than minimum")
    }
  }

  # object facets
  if (Test-NeoIsObject $Instance) {
    $propsSchema = $null
    if ($keys -contains 'properties') { $propsSchema = Get-NeoProp $Schema 'properties' }
    $definedNames = @(); if ($propsSchema) { $definedNames = @(Get-NeoPropNames $propsSchema) }

    if ($keys -contains 'required') {
      foreach ($rk in @(Get-NeoProp $Schema 'required')) {
        if (-not (Test-NeoHasProp $Instance $rk)) { [void]$errs.Add("$Path.$rk : required property missing") }
      }
    }
    if ($propsSchema) {
      foreach ($pn in $definedNames) {
        if (Test-NeoHasProp $Instance $pn) {
          $sub = Get-NeoProp $propsSchema $pn
          foreach ($ce in @(Test-NeoSchema -Instance (Get-NeoVal $Instance $pn) -Schema $sub -Index $Index -Path "$Path.$pn" -NoPreflight)) { [void]$errs.Add($ce) }
        }
      }
    }
    if ($keys -contains 'additionalProperties') {
      $ap = Get-NeoProp $Schema 'additionalProperties'
      foreach ($pn in @(Get-NeoPropNames $Instance)) {
        if ($definedNames -contains $pn) { continue }
        if ($ap -is [bool]) {
          if (-not $ap) { [void]$errs.Add("$Path.$pn : additional property not allowed") }
        } elseif (Test-NeoIsObject $ap) {
          foreach ($ce in @(Test-NeoSchema -Instance (Get-NeoVal $Instance $pn) -Schema $ap -Index $Index -Path "$Path.$pn" -NoPreflight)) { [void]$errs.Add($ce) }
        }
      }
    }
  }

  # array facets
  if ($Instance -is [array]) {
    if ($keys -contains 'minItems') { if ($Instance.Count -lt [int](Get-NeoProp $Schema 'minItems')) { [void]$errs.Add("$Path : fewer than minItems") } }
    if ($keys -contains 'maxItems') { if ($Instance.Count -gt [int](Get-NeoProp $Schema 'maxItems')) { [void]$errs.Add("$Path : more than maxItems") } }
    if ($keys -contains 'items') {
      $isch = Get-NeoProp $Schema 'items'
      for ($i = 0; $i -lt $Instance.Count; $i++) {
        foreach ($ce in @(Test-NeoSchema -Instance $Instance[$i] -Schema $isch -Index $Index -Path "$Path[$i]" -NoPreflight)) { [void]$errs.Add($ce) }
      }
    }
  }

  # allOf
  if ($keys -contains 'allOf') {
    foreach ($sub in @(Get-NeoProp $Schema 'allOf')) {
      foreach ($ce in @(Test-NeoSchema -Instance $Instance -Schema $sub -Index $Index -Path $Path -NoPreflight -RefChain $RefChain)) { [void]$errs.Add($ce) }
    }
  }

  # if / then / else. Preflight (above) has already guaranteed the whole schema
  # graph is well-formed, so evaluating the if-condition here can only yield
  # INSTANCE-mismatch errors -- never schema-structural ones. Count is therefore a
  # sound truth value for "instance matched the if-condition" (F1).
  if ($keys -contains 'if') {
    $ifErrs = @(Test-NeoSchema -Instance $Instance -Schema (Get-NeoProp $Schema 'if') -Index $Index -Path $Path -NoPreflight -RefChain $RefChain)
    if ($ifErrs.Count -eq 0) {
      if ($keys -contains 'then') {
        foreach ($ce in @(Test-NeoSchema -Instance $Instance -Schema (Get-NeoProp $Schema 'then') -Index $Index -Path $Path -NoPreflight -RefChain $RefChain)) { [void]$errs.Add($ce) }
      }
    } else {
      if ($keys -contains 'else') {
        foreach ($ce in @(Test-NeoSchema -Instance $Instance -Schema (Get-NeoProp $Schema 'else') -Index $Index -Path $Path -NoPreflight -RefChain $RefChain)) { [void]$errs.Add($ce) }
      }
    }
  }

  return @($errs.ToArray())
}
