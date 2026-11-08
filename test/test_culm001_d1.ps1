param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# CULM-001 D.1 (CONTRACT §2.2 D1-11, §14.2 D-RB-01): casos que necesitan sqlcmd con variables y :r de migrations/.
#   CULM001_D1_11_UP_DOWN_UP     test_culm001_d1_migraciones.sql (transaccion revertida)
#   CULM001_D1_RB_01_DOWN_GUARD  test_culm001_d1_down_guard.sql (el down aborta con 50020 si D.2 esta aplicada)
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_culm001_d1.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/culm001_d1_$tag"
$dbRoot = Split-Path -Parent $PSScriptRoot
$failures = @()
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations" 2>&1
$copy = @(& docker cp (Join-Path $dbRoot 'migrations/.') "${ContainerName}:$remoteDir/migrations" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy migrations: $($copy -join '; ')" }
foreach ($f in @('test_culm001_d1_migraciones.sql', 'test_culm001_d1_down_guard.sql')) {
    $copy = @(& docker cp (Join-Path $PSScriptRoot $f) "${ContainerName}:$remoteDir/$f" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "could not copy ${f}: $($copy -join '; ')" }
}
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1

function Invoke-Sqlcmd-File([string]$file) {
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
                 '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", '-i', "$remoteDir/$file")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $lines; Text = ($lines -join "`n") }
}

try {
    $r = Invoke-Sqlcmd-File 'test_culm001_d1_migraciones.sql'
    $missing = @(@('MIG_D1_DOWN_OK', 'MIG_D1_UP1_OK', 'MIG_D1_UP2_OK', 'MIG_D1_DOWN_UP_OK', 'MIG_D1_ROLLBACK_OK') | Where-Object { $r.Text -notmatch "(?m)^$_$" })
    if ($missing.Count -eq 0 -and $r.ExitCode -eq 0) { Write-Output 'TEST_PASS:CULM001_D1_11_UP_DOWN_UP' }
    else { $failures += "CULM001_D1_11_UP_DOWN_UP missing $($missing -join ',') (exit $($r.ExitCode)): $(($r.Lines | Where-Object { $_ -match 'Msg |MIG_|TEST' }) -join ' / ')" }

    $g = Invoke-Sqlcmd-File 'test_culm001_d1_down_guard.sql'
    if ($g.Text -match '(?m)^DOWN_GUARD_STUB_OK$' -and $g.Text -notmatch 'DOWN_GUARD_NOT_ENFORCED' -and $g.Text -match '50020') { Write-Output 'TEST_PASS:CULM001_D1_RB_01_DOWN_GUARD' }
    else { $failures += "CULM001_D1_RB_01_DOWN_GUARD (exit $($g.ExitCode)): $(($g.Lines | Where-Object { $_ -match 'Msg |DOWN_GUARD|CULM001|50020' }) -join ' / ')" }
}
catch { $failures += "CULM001_D1_RUNNER $($_.Exception.Message)" }
finally { $null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1 }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "TEST FAILED: $_" }
    exit 1
}
exit 0
