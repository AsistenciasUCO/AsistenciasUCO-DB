# Secret hygiene helpers for the DB quality gate (gate id: NO_HARDCODED_DB_PASSWORD).
# Findings NEVER include the secret value: only file, line and finding type.
#
# Dot-source this file:  . (Join-Path $PSScriptRoot 'scripts/secret-hygiene.ps1')

$script:SecretNameRx = '(?i)(?<![A-Za-z0-9])(MSSQL_SA_PASSWORD|SQL_CONTAINER_PASSWORD|SA_PASSWORD|DB_PASSWORD|DATABASE_PASSWORD|Password|Pwd)["'']?\s*[:=]\s*(?<value>.*)$'
$script:SecretCliRx = '(?<![A-Za-z0-9])-P\s+(?<value>["'']?[^\s"''$][^\s"'']*)'
$script:SecretSafeValueRx = '^(?i:(CHANGE_?ME|REPLACE_?ME|YOUR_.*|PLACEHOLDER|TEST_ONLY.*|<.*>|\*+|x{3,}))$'
$script:SecretEnvLikeRx = '(?i)(^\.env(\..+)?$|\.env$|\.properties$|\.ini$|\.cfg$|\.conf$|\.ya?ml$|\.json$)'
$script:SecretScannableRx = '(?i)(^\.env(\..+)?$|\.env$|\.ps1$|\.psm1$|\.sh$|\.cmd$|\.ya?ml$|\.json$|\.properties$|\.ini$|\.cfg$|\.conf$|\.config$|\.sqlproj$)'

function Test-SecretValueIsSafe {
    param([string]$Value, [bool]$WasQuoted)
    $v = $Value.Trim().TrimEnd(',', ';').Trim()
    if ($v.Length -ge 2 -and (($v[0] -eq '"' -and $v[-1] -eq '"') -or ($v[0] -eq "'" -and $v[-1] -eq "'"))) { $v = $v.Substring(1, $v.Length - 2) }
    elseif ($v.Length -ge 1 -and ($v[0] -eq '"' -or $v[0] -eq "'")) { $v = $v.Substring(1) }
    if ($v.Length -eq 0) { return $true }
    if ($v[0] -eq '$' -or $v[0] -eq '%') { return $true }   # variable / secret reference (${{ secrets.X }}, $env:X, $X)
    if ($v -match $script:SecretSafeValueRx) { return $true }
    return $false
}

function Find-HardcodedDbPassword {
    <#
      Scans one file. Returns objects with File, Line, Type (never the value).
      - Quoted literals are flagged in every scanned file type.
      - Unquoted values are flagged only in env-like/config files (.env*, yaml, json, properties, ini),
        because in scripts an unquoted right-hand side is code, not a literal.
    #>
    param([Parameter(Mandatory)][string]$Path, [string]$DisplayName)
    if (-not $DisplayName) { $DisplayName = $Path }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $leaf = Split-Path -Leaf $Path
    $envLike = $leaf -match $script:SecretEnvLikeRx
    $findings = @()
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $lineNo++
        $m = [regex]::Match($line, $script:SecretNameRx)
        if ($m.Success) {
            $raw = $m.Groups['value'].Value.Trim()
            $quoted = $raw.StartsWith('"') -or $raw.StartsWith("'")
            if (($quoted -or $envLike) -and -not (Test-SecretValueIsSafe -Value $raw -WasQuoted $quoted)) {
                $findings += [pscustomobject]@{ File = $DisplayName; Line = $lineNo; Type = 'HARDCODED_PASSWORD_LITERAL' }
                continue
            }
        }
        $c = [regex]::Match($line, $script:SecretCliRx)
        if ($c.Success -and -not (Test-SecretValueIsSafe -Value $c.Groups['value'].Value -WasQuoted $false)) {
            $findings += [pscustomobject]@{ File = $DisplayName; Line = $lineNo; Type = 'CLI_PASSWORD_ARGUMENT' }
        }
    }
    return $findings
}

function Get-SecretScanFiles {
    <# Files always scanned + every versioned file of a scannable type (git ls-files). Returns relative paths. #>
    param([Parameter(Mandatory)][string]$Root)
    $always = @('deploy_schema.ps1', 'test_summary.ps1', '.env.template', '.env.example', '.vscode/settings.json', 'sonar-project.properties')
    $set = [System.Collections.Generic.SortedSet[string]]::new()
    foreach ($f in $always) { [void]$set.Add($f) }
    $workflowDir = Join-Path $Root '.github/workflows'
    if (Test-Path $workflowDir) {
        foreach ($f in Get-ChildItem $workflowDir -File -Recurse) {
            [void]$set.Add($f.FullName.Substring($Root.TrimEnd('\', '/').Length + 1).Replace('\', '/'))
        }
    }
    $tracked = @()
    try { $tracked = @(git -C $Root ls-files 2>$null) } catch { $tracked = @() }
    foreach ($f in $tracked) {
        if ((Split-Path -Leaf $f) -match $script:SecretScannableRx) { [void]$set.Add($f) }
    }
    return @($set)
}

function Invoke-SecretHygieneScan {
    param([Parameter(Mandatory)][string]$Root)
    $findings = @()
    foreach ($rel in (Get-SecretScanFiles -Root $Root)) {
        $findings += @(Find-HardcodedDbPassword -Path (Join-Path $Root $rel) -DisplayName $rel)
    }
    # A tracked real .env is itself a finding.
    $tracked = @(); try { $tracked = @(git -C $Root ls-files -- .env 2>$null) } catch { }
    foreach ($t in $tracked) { $findings += [pscustomobject]@{ File = $t; Line = 0; Type = 'TRACKED_ENV_FILE' } }
    return $findings
}

function Test-SecretGateSelfCheck {
    <# Causal regression check: the gate must detect an unsafe template and accept a safe placeholder. #>
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "secret_gate_selfcheck_$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $dir | Out-Null
    try {
        $fake = 'TEST_ONLY_' + [guid]::NewGuid().ToString('N') + 'aZ9#'
        $name = 'SQL_CONTAINER' + '_PASSWORD'
        $unsafe = Join-Path $dir '.env.template'
        $safe = Join-Path $dir '.env.example'
        $ps1 = Join-Path $dir 'sample.ps1'
        Set-Content -LiteralPath $unsafe -Value @('# template', "$name=$($fake.Replace('TEST_ONLY_', 'Zq'))") -Encoding ascii
        Set-Content -LiteralPath $safe -Value @('# template', "$name=CHANGE_ME", 'SQL_CONTAINER_NAME=sqlserver') -Encoding ascii
        $pwName = 'Pass' + 'word'
        $unsafeValue = $fake.Replace('TEST_ONLY_', 'Zq')
        Set-Content -LiteralPath $ps1 -Value @("`$$pwName = `$env:X", "`$$pwName = '$unsafeValue'") -Encoding ascii
        [pscustomobject]@{
            DetectsUnsafeEnvTemplate = (@(Find-HardcodedDbPassword -Path $unsafe).Count -eq 1)
            AcceptsPlaceholder       = (@(Find-HardcodedDbPassword -Path $safe).Count -eq 0)
            DetectsQuotedScriptLiteral = (@(Find-HardcodedDbPassword -Path $ps1).Count -eq 1)
        }
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}
