[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$OutputPath,[string]$Version='dev')

$ErrorActionPreference='Stop'
Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$staging = Join-Path ([IO.Path]::GetTempPath()) ('WinPortableLab-{0}-{1}' -f $Version,[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging -Force | Out-Null
foreach ($file in @('WinPortableLab.ps1','Start.cmd','README.md','SECURITY.md','CONTRIBUTING.md','CHANGELOG.md','THIRD_PARTY_NOTICES.md')) {
    $source=Join-Path $Root $file
    if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination $staging -Force}
}
foreach($directory in @('catalog','config','docs','profiles','scripts','src','manifests')){
    Copy-Item -LiteralPath (Join-Path $Root $directory) -Destination $staging -Recurse -Force
}
foreach($runtime in @('tools','downloads','reports','recommendations','sessions','logs')){
    New-Item -ItemType Directory -Path (Join-Path $staging $runtime) -Force | Out-Null
}
$zip=Join-Path $OutputPath ('WinPortableLab-Core-{0}.zip' -f $Version)
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip -CompressionLevel Optimal -Force
$hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
"$hash  $([IO.Path]::GetFileName($zip))" | Set-Content -LiteralPath "$zip.sha256" -Encoding ascii
$components=@(Get-WplPackageDefinitions -Root $Root | ForEach-Object {
    [ordered]@{type='application';name=$_.displayName;version=$_.version;'bom-ref'="pkg:generic/$($_.packageId)@$($_.version)";hashes=@([ordered]@{alg='SHA-256';content=$_.source.sha256})}
})
$sbom=[ordered]@{bomFormat='CycloneDX';specVersion='1.5';serialNumber="urn:uuid:$([guid]::NewGuid())";version=1;metadata=[ordered]@{timestamp=(Get-Date).ToUniversalTime().ToString('o');component=[ordered]@{type='application';name='WinPortableLab';version=$Version}};components=$components}
$sbom | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputPath 'winportablelab.cdx.json') -Encoding utf8
[pscustomobject]@{Zip=$zip;Sha256=$hash;Sbom=(Join-Path $OutputPath 'winportablelab.cdx.json')}
