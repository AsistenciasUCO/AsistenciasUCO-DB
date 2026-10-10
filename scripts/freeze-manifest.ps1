# Deterministic freeze manifest for the DB develop baseline (DB-GP-001C).
#
# Generate (after an authorized contract/freeze decision only):
#   ./scripts/freeze-manifest.ps1 -Mode Generate
# Verify (used by test_summary.ps1, gate id GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED):
#   ./scripts/freeze-manifest.ps1 -Mode Verify
#
# Post-freeze extensions (UTC-D06-POST-FREEZE) do NOT rewrite the DB-GP-001C manifest. They are recorded in
# docs/contracts/DB_UTC_D06_POST_FREEZE_MANIFEST.sha256 with one of two line forms:
#   <sha256>  <path>  SUPERSEDES <db-gp-001c-sha256>   frozen file changed by the approved work item
#   <sha256>  <path>  WORK_ITEM                         source added or extended by the work item (outside the frozen list)
# Verify accepts a frozen file's new hash ONLY when the supersession names the exact DB-GP-001C hash.
#   ./scripts/freeze-manifest.ps1 -Mode GeneratePostFreeze   (only after the post-freeze work item is approved)
#
# The addendum is intentionally NOT hashed: it records the final commit SHA, which cannot include itself.
# Hashes are SHA-256 over the file content with CRLF normalized to LF, so the manifest is identical
# on Windows (core.autocrlf=true) and Linux checkouts. The result is sha256sum-compatible for LF files:
#   sha256sum <path>   ==   the hash recorded here for that path.
param (
    [ValidateSet('Generate', 'Verify', 'GeneratePostFreeze')][string]$Mode = 'Verify',
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$manifestRel = 'docs/contracts/DB_DEVELOP_FREEZE_MANIFEST.sha256'
$postFreezeManifestRel = 'docs/contracts/DB_UTC_D06_POST_FREEZE_MANIFEST.sha256'
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
# UTC-D06-POST-FREEZE: frozen files the work item is authorized to supersede, and the sources it adds.
$postFreezeSuperseded = @(
    'schema/stored-procedures/usp_crear_sesion.sql',
    'schema/stored-procedures/usp_actualizar_sesion.sql',
    'schema/stored-procedures/usp_generar_sesiones_grupo.sql'
)
$postFreezeNew = @( # added or extended (Sesion.sql gains the provenance column outside the frozen list)
    'schema/tables/Sesion.sql',
    'schema/tables/SesionProcedenciaClasificacion.sql',
    'schema/triggers/tr_Sesion_procedencia_temporal.sql',
    'schema/views/uv_sesion_v2.sql',
    'schema/stored-procedures/usp_crear_sesion_interno.sql',
    'schema/stored-procedures/usp_crear_sesion_v2.sql',
    'schema/stored-procedures/usp_actualizar_sesion_interno.sql',
    'schema/stored-procedures/usp_actualizar_sesion_v2.sql',
    'schema/stored-procedures/usp_clasificar_procedencia_sesion.sql',
    'schema/security/rol_asistencias_runtime.sql'
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

function Read-BaseManifest {
    param([string]$Path)
    $map = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^([0-9a-f]{64})  (.+)$') { $map[$Matches[2]] = $Matches[1] }
    }
    return $map
}

$manifestPath = Join-Path $Root $manifestRel
$postFreezeManifestPath = Join-Path $Root $postFreezeManifestRel
if ($Mode -eq 'Generate') {
    $lines = foreach ($f in $frozenFiles) { "$(Get-NormalizedSha256 -Path (Join-Path $Root $f))  $f" }
    [System.IO.File]::WriteAllText($manifestPath, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Host "Manifest written: $manifestRel ($($frozenFiles.Count) entries)"
    exit 0
}
if ($Mode -eq 'GeneratePostFreeze') {
    $base = Read-BaseManifest -Path $manifestPath
    $lines = @()
    foreach ($f in $postFreezeSuperseded) {
        $lines += "$(Get-NormalizedSha256 -Path (Join-Path $Root $f))  $f  SUPERSEDES $($base[$f])"
    }
    foreach ($f in $postFreezeNew) {
        $lines += "$(Get-NormalizedSha256 -Path (Join-Path $Root $f))  $f  WORK_ITEM"
    }
    [System.IO.File]::WriteAllText($postFreezeManifestPath, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Host "Post-freeze manifest written: $postFreezeManifestRel ($($lines.Count) entries)"
    exit 0
}

$problems = @()
$superseded = @{}
$postNew = @{}
if (Test-Path $postFreezeManifestPath) {
    foreach ($line in [System.IO.File]::ReadAllLines($postFreezeManifestPath)) {
        if ($line -match '^([0-9a-f]{64})  (\S+)  SUPERSEDES ([0-9a-f]{64})$') {
            $superseded[$Matches[2]] = @{ Sha = $Matches[1]; Previous = $Matches[3] }
        }
        elseif ($line -match '^([0-9a-f]{64})  (\S+)  WORK_ITEM$') { $postNew[$Matches[2]] = $Matches[1] }
        elseif ($line.Trim()) { $problems += "POST_FREEZE_MANIFEST_INVALID_LINE:$line" }
    }
}
if (-not (Test-Path $manifestPath)) { $problems += "MANIFEST_MISSING:$manifestRel" }
else {
    $recorded = Read-BaseManifest -Path $manifestPath
    foreach ($f in $frozenFiles) {
        $full = Join-Path $Root $f
        if (-not $recorded.ContainsKey($f)) { $problems += "NOT_IN_MANIFEST:$f"; continue }
        if (-not (Test-Path $full)) { $problems += "FILE_MISSING:$f"; continue }
        $expected = $recorded[$f]
        if ($superseded.ContainsKey($f)) {
            if ($f -notin $postFreezeSuperseded) { $problems += "SUPERSESSION_NOT_AUTHORIZED:$f" }
            if ($superseded[$f].Previous -ne $recorded[$f]) { $problems += "SUPERSESSION_CHAIN_BROKEN:$f" }
            $expected = $superseded[$f].Sha
        }
        if ((Get-NormalizedSha256 -Path $full) -ne $expected) { $problems += "HASH_MISMATCH:$f" }
    }
    foreach ($f in $postNew.Keys) {
        $full = Join-Path $Root $f
        if (-not (Test-Path $full)) { $problems += "FILE_MISSING:$f"; continue }
        if ((Get-NormalizedSha256 -Path $full) -ne $postNew[$f]) { $problems += "HASH_MISMATCH:$f" }
    }
    if ($recorded['docs/contracts/DB_BASELINE_CONTRACT.md'] -ne $expectedContractSha) { $problems += 'CONTRACT_SHA_NOT_BASELINE' }
}
if ($problems.Count -gt 0) { $problems | ForEach-Object { Write-Host $_ }; exit 1 }
Write-Host "FREEZE_MANIFEST_OK entries=$($frozenFiles.Count) post_freeze_superseded=$($superseded.Count) post_freeze_work_item=$($postNew.Count)"
exit 0
