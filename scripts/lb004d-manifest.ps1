# Manifest determinista de LB-004D (vinculo soporte <-> solicitud de revision, ONE_TABLE).
#
#   ./scripts/lb004d-manifest.ps1 -Mode Generate   (solo tras un cambio aprobado del contrato LB-004D)
#   ./scripts/lb004d-manifest.ps1 -Mode Verify     (falla si alguno de los archivos listados cambio)
#
# Es independiente de DB_DEVELOP_FREEZE_MANIFEST y de DB_UTC_D06_POST_FREEZE_MANIFEST: no toca el Golden Path.
# Hash: SHA-256 del contenido con CRLF normalizado a LF (identico en Windows con autocrlf y en Linux;
# compatible con `sha256sum <ruta>` para archivos LF).
param (
    [ValidateSet('Generate', 'Verify')][string]$Mode = 'Verify',
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$manifestRel = 'docs/contracts/DB_LB004D_SUPPORT_BINDING_MANIFEST.sha256'
$files = @(
    'schema/tables/ArchivoSoporte.sql',
    'schema/seed/15_lb004d_archivo_soporte.sql',
    'schema/security/rol_asistencias_runtime_lb004d.sql',
    'schema/stored-procedures/usp_registrar_archivo_soporte.sql',
    'schema/stored-procedures/usp_radicar_solicitud_revision_asistencia_v2.sql',
    'schema/stored-procedures/usp_consultar_archivo_soporte_autorizado.sql',
    'schema/stored-procedures/usp_consultar_solicitudes_revision_docente.sql',
    'test/test_lb004d_support_binding.sql',
    'test/test_lb004d_concurrency.ps1'
)

function Get-NormalizedSha256([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes).Replace("`r`n", "`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))) -replace '-', '').ToLowerInvariant()
}

$manifestPath = Join-Path $Root $manifestRel
if ($Mode -eq 'Generate') {
    $lines = foreach ($f in $files) { "$(Get-NormalizedSha256 (Join-Path $Root $f))  $f" }
    [System.IO.File]::WriteAllText($manifestPath, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "LB004D_MANIFEST_GENERATED entries=$($files.Count)"
    exit 0
}

if (-not (Test-Path $manifestPath)) { Write-Host "LB004D_MANIFEST_MISSING $manifestRel"; exit 1 }
$expected = @{}
foreach ($line in (Get-Content $manifestPath)) {
    if ($line -match '^([0-9a-f]{64})  (.+)$') { $expected[$Matches[2]] = $Matches[1] }
    elseif ($line.Trim()) { Write-Host "LB004D_MANIFEST_INVALID_LINE:$line"; exit 1 }
}
$problems = @()
foreach ($f in $files) {
    if (-not $expected.ContainsKey($f)) { $problems += "NOT_LISTED:$f"; continue }
    $path = Join-Path $Root $f
    if (-not (Test-Path $path)) { $problems += "MISSING:$f"; continue }
    if ((Get-NormalizedSha256 $path) -ne $expected[$f]) { $problems += "HASH_MISMATCH:$f" }
}
foreach ($k in $expected.Keys) { if ($k -notin $files) { $problems += "UNEXPECTED_ENTRY:$k" } }
if ($problems.Count -gt 0) { $problems | ForEach-Object { Write-Host $_ }; Write-Host 'LB004D_MANIFEST_FAILED'; exit 1 }
Write-Host "LB004D_MANIFEST_OK entries=$($files.Count)"
exit 0
