# Creates a self-signed HTTPS certificate for camera AIR on the LAN.
# Output: camera-cert.pfx (used by the bridge) and camera-cert.cer (install on the phone/iPad to trust it).
param(
    [string]$Password = 'brokenithm'
)

$ErrorActionPreference = 'Stop'
try {
    $ips = @(Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
        ForEach-Object { $_.IPAddress })
    $names = @('localhost', $env:COMPUTERNAME)
    $entries = @($names | ForEach-Object { "DNS=$_" }) + @($ips | ForEach-Object { "IPAddress=$_" }) + @('IPAddress=127.0.0.1')
    $san = '2.5.29.17={text}' + ($entries -join '&')
    # iOS rejects TLS certificates valid for more than 825 days, so keep it shorter.
    $cert = New-SelfSignedCertificate -Subject 'CN=Brokenithm Camera AIR' -FriendlyName 'Brokenithm Camera AIR' `
        -TextExtension @($san, '2.5.29.37={text}1.3.6.1.5.5.7.3.1', '2.5.29.19={text}ca=true') `
        -CertStoreLocation 'Cert:\CurrentUser\My' -KeyExportPolicy Exportable -KeyAlgorithm RSA -KeyLength 2048 `
        -HashAlgorithm SHA256 -NotAfter (Get-Date).AddDays(800)
    $secure = ConvertTo-SecureString $Password -AsPlainText -Force
    $pfx = Join-Path $PSScriptRoot 'camera-cert.pfx'
    $cer = Join-Path $PSScriptRoot 'camera-cert.cer'
    Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $secure | Out-Null
    Export-Certificate -Cert $cert -FilePath $cer | Out-Null
    Remove-Item -LiteralPath ('Cert:\CurrentUser\My\' + $cert.Thumbprint)
    Write-Host "Created $pfx"
    Write-Host "Created $cer  (install this on the phone/iPad to remove the certificate warning)"
    Write-Host ('Valid for: ' + ($entries -join ', '))
    Write-Host 'If the PC IP address changes, run this script again.'
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
}
Read-Host 'Press Enter to close'
