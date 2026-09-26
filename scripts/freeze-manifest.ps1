# Deterministic freeze manifest for the DB develop baseline (DB-GP-001C).
#
# Generate (after an authorized contract/freeze decision only):
#   ./scripts/freeze-manifest.ps1 -Mode Generate
# Verify (used by test_summary.ps1, gate id GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED):
#   ./scripts/freeze-manifest.ps1 -Mode Verify
#
# The addendum is intentionally NOT hashed: it records the final commit SHA, which cannot include itself.
# Hashes are SHA-256 over the file content with CRLF normalized to LF, so the manifest is identical
# on Windows (core.autocrlf=true) and Linux checkouts. The result is sha256sum-compatible for LF files:
#   sha256sum <path>   ==   the hash recorded here for that path.
param (
    [ValidateSet('Generate', 'Verify')][string]$Mode = 'Verify',
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$manifestRel = 'docs/contracts/DB_DEVELOP_FREEZE_MANIFEST.sha256'
$frozenFiles = @(
    'docs/contracts/DB_BASELINE_CONTRACT.md',
    'schema/views/uv_horario_docente.sql',
    'schema/views/uv_sesion.sql',
    'schema/views/uv_estudiante_grupo.sql',
    'schema/views/uv_asistencia.sql',
    'schema/views/uv_detalle_asistencia.sql',
    'schema/stored-procedures/usp_crear_sesion.sql',
    'schema/stored-procedures/usp_actualizar_sesion.sql',
    'schema/stored-procedures/usp_generar_sesiones_grupo.sql',
    'schema/stored-procedures/usp_registrar_asistencias_sesion.sql'
)
$expectedContractSha = '45e48c5a0ab321d0c8cbffb55ee224e3b6fd29febc39a62ca723b2b209945aec'

function Get-NormalizedSha256 {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $ms = [System.IO.MemoryStream]::new()
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 13 -and ($i + 1) -lt $bytes.Length -and $bytes[$i + 1] -eq 10) { continue }
        $ms.WriteByte($bytes[$i])
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return ([System.BitConverter]::ToString($sha.ComputeHash($ms.ToArray())).Replace('-', '')).ToLowerInvariant()
}

$manifestPath = Join-Path $Root $manifestRel
if ($Mode -eq 'Generate') {
    $lines = foreach ($f in $frozenFiles) { "$(Get-NormalizedSha256 -Path (Join-Path $Root $f))  $f" }
    [System.IO.File]::WriteAllText($manifestPath, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Host "Manifest written: $manifestRel ($($frozenFiles.Count) entries)"
    exit 0
}

$problems = @()
if (-not (Test-Path $manifestPath)) { $problems += "MANIFEST_MISSING:$manifestRel" }
else {
    $recorded = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($manifestPath)) {
        if ($line -match '^([0-9a-f]{64})  (.+)$') { $recorded[$Matches[2]] = $Matches[1] }
    }
    foreach ($f in $frozenFiles) {
        $full = Join-Path $Root $f
        if (-not $recorded.ContainsKey($f)) { $problems += "NOT_IN_MANIFEST:$f"; continue }
        if (-not (Test-Path $full)) { $problems += "FILE_MISSING:$f"; continue }
        if ((Get-NormalizedSha256 -Path $full) -ne $recorded[$f]) { $problems += "HASH_MISMATCH:$f" }
    }
    if ($recorded['docs/contracts/DB_BASELINE_CONTRACT.md'] -ne $expectedContractSha) { $problems += 'CONTRACT_SHA_NOT_BASELINE' }
}
if ($problems.Count -gt 0) { $problems | ForEach-Object { Write-Host $_ }; exit 1 }
Write-Host "FREEZE_MANIFEST_OK entries=$($frozenFiles.Count)"
exit 0
