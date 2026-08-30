[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$SessionId)
$session = Join-Path $Root ('sessions\{0}' -f $SessionId)
if (-not (Test-Path -LiteralPath $session -PathType Container)) { throw "Session not found: $SessionId" }
Set-Content -LiteralPath (Join-Path $session 'CANCEL.REQUESTED') -Value (Get-Date).ToString('o') -Encoding ascii
Write-Host "Cancellation requested: $SessionId"
