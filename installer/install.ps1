[CmdletBinding()]
param([string]$Components = 'ide,cli,esp32,pico,mbed,cp210x,ch340,ftdi,libraries', [switch]$SelfTest)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$script:LogFile = $null
$script:RestartRequired = $false
$script:Cli = $null
$script:Config = $null
$script:Headers = @{ 'User-Agent' = 'OneClick-UNIVAP/1.0'; Accept = 'application/vnd.github+json' }
$script:BoardUrls = @('https://espressif.github.io/arduino-esp32/package_esp32_index.json', 'https://github.com/earlephilhower/arduino-pico/releases/download/global/package_rp2040_index.json')
$script:Libraries = @('DHT sensor library', 'Adafruit Unified Sensor', 'PubSubClient', 'ArduinoJson', 'LiquidCrystal I2C', 'Servo')
$script:Allowed = @('ide','cli','esp32','pico','mbed','cp210x','ch340','ftdi','libraries')

function Write-Log([string]$Message) {
    [Console]::WriteLine($Message)
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $Message -Encoding UTF8 }
}

function Get-Selection([string]$Value) {
    $items = @($Value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if ($items.Count -eq 0) { throw 'Selecione pelo menos um componente.' }
    foreach ($id in $items) { if ($script:Allowed -notcontains $id) { throw "Componente desconhecido: $id" } }
    return $items
}

function Invoke-Program([string]$File, [string[]]$Arguments, [switch]$Capture, [int[]]$SuccessCodes = @(0)) {
    Write-Log ('> ' + [IO.Path]::GetFileName($File) + ' ' + ($Arguments -join ' '))
    $lines = [Collections.Generic.List[string]]::new()
    # Native stderr is diagnostic output, not a PowerShell terminating error.
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $File @Arguments 2>&1 | ForEach-Object { $line = $_.ToString(); $lines.Add($line); Write-Log $line }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if ($SuccessCodes -notcontains $code) { throw "Falha em $([IO.Path]::GetFileName($File)) (codigo $code). Consulte as linhas acima." }
    if ($code -eq 3010 -or $code -eq 1641) { $script:RestartRequired = $true }
    if ($Capture) { return ($lines -join [Environment]::NewLine) }
}

function Get-Download([string]$Url, [string]$Destination, [string]$Digest = '') {
    if (-not $Url.StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) { throw 'Somente downloads HTTPS sao permitidos.' }
    $partial = $Destination + '.partial'
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Write-Log "Download ($attempt/3): $Url"
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $partial -TimeoutSec 600 -Headers @{ 'User-Agent' = 'OneClick-UNIVAP/1.0' }
            if ((Get-Item -LiteralPath $partial).Length -lt 1024) { throw 'Download vazio ou incompleto.' }
            $actual = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($Digest -match '^sha256:([a-fA-F0-9]{64})$' -and $actual -ne $Matches[1].ToLowerInvariant()) { throw 'O SHA-256 nao corresponde ao publicado pelo fornecedor.' }
            Move-Item -LiteralPath $partial -Destination $Destination -Force
            Write-Log "SHA-256: $actual"
            return
        } catch {
            if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
            if ($attempt -eq 3) { throw }
            Write-Log "Tentativa falhou: $($_.Exception.Message)"
            Start-Sleep -Seconds 2
        }
    }
}

function Get-ReleaseAsset([string]$Repo, [string]$Pattern) {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $script:Headers -TimeoutSec 90
    $asset = @($release.assets | Where-Object { $_.name -match $Pattern })
    if ($asset.Count -ne 1) { throw "Nao foi encontrado um unico instalador compativel em $Repo. Consulte https://github.com/$Repo/releases/latest" }
    Write-Log "Versao publicada pelo fornecedor: $($release.tag_name)"
    return $asset[0]
}

function Get-AssetDigest($Asset) {
    if ($Asset.PSObject.Properties.Name -contains 'digest' -and $Asset.digest) { return [string]$Asset.digest }
    return ''
}

function Assert-Signature([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid') { throw "Assinatura digital invalida ou nao verificavel: $Path ($($signature.Status)). Nenhuma protecao do Windows sera desativada." }
    Write-Log "Assinatura valida: $($signature.SignerCertificate.Subject)"
}

function Install-Ide {
    $asset = Get-ReleaseAsset 'arduino/arduino-ide' 'Windows_64bit\.exe$'
    $file = Join-Path $script:RunDir $asset.name
    Get-Download $asset.browser_download_url $file (Get-AssetDigest $asset)
    Assert-Signature $file
    Invoke-Program $file @('/S') -SuccessCodes @(0,3010)
    $paths = @((Join-Path $env:ProgramFiles 'Arduino IDE\Arduino IDE.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\Arduino IDE\Arduino IDE.exe'))
    if (-not @($paths | Where-Object { Test-Path -LiteralPath $_ }).Count) { throw 'O instalador terminou, mas Arduino IDE.exe nao foi encontrado nos locais padrao.' }
}

function Install-Cli {
    if ($script:Cli -and (Test-Path -LiteralPath $script:Cli)) { return }
    $asset = Get-ReleaseAsset 'arduino/arduino-cli' 'Windows_64bit\.zip$'
    $file = Join-Path $script:RunDir $asset.name
    Get-Download $asset.browser_download_url $file (Get-AssetDigest $asset)
    $extract = Join-Path $script:RunDir 'cli-extracted'
    Expand-Archive -LiteralPath $file -DestinationPath $extract -Force
    $found = @(Get-ChildItem -LiteralPath $extract -Filter 'arduino-cli.exe' -Recurse -File)
    if ($found.Count -ne 1) { throw 'O pacote oficial nao contem um unico arduino-cli.exe.' }
    $toolsDir = Join-Path $script:BaseDir 'tools'
    [IO.Directory]::CreateDirectory($toolsDir) | Out-Null
    $cliPath = Join-Path $toolsDir 'arduino-cli.exe'
    Copy-Item -LiteralPath $found[0].FullName -Destination $cliPath -Force
    Invoke-Program $cliPath @('version')
    $script:Cli = $cliPath
}

function Update-ConfigSafely([string]$Path, [scriptblock]$Edit) {
    $folder = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $temporary = Join-Path $folder ('.oneclick-' + [Guid]::NewGuid().ToString('N') + '.yaml')
    $backup = $null
    try {
        if (Test-Path -LiteralPath $Path) {
            $backup = $Path + '.oneclick-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-ffff') + '.bak'
            Copy-Item -LiteralPath $Path -Destination $backup
            Copy-Item -LiteralPath $Path -Destination $temporary
        }
        & $Edit $temporary
        if (-not (Test-Path -LiteralPath $temporary)) { throw 'A configuracao temporaria nao foi criada.' }
        # Replace only after every CLI edit succeeds; keep a byte-for-byte backup.
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
        if ($backup) { Write-Log "Configuracao anterior preservada em: $backup" }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}

function Initialize-ArduinoConfig {
    Install-Cli
    if ($script:Config) { return }
    $path = Join-Path $env:USERPROFILE '.arduinoIDE\arduino-cli.yaml'
    Update-ConfigSafely $path {
        param($temporary)
        if (-not (Test-Path -LiteralPath $temporary)) {
            Invoke-Program $script:Cli @('config','init','--dest-file',$temporary)
            # Match the IDE default sketchbook for this Windows account.
            $sketchbook = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Arduino'
            Invoke-Program $script:Cli @('--config-file',$temporary,'config','set','directories.user',$sketchbook)
        }
        foreach ($url in $script:BoardUrls) {
            Invoke-Program $script:Cli @('--config-file',$temporary,'config','add','board_manager.additional_urls',$url)
        }
        Invoke-Program $script:Cli @('--config-file',$temporary,'config','dump')
    }
    Write-Log "Arduino IDE 2 e CLI usam a mesma configuracao: $path"
    Invoke-Program $script:Cli @('--config-file',$path,'core','update-index')
    $script:Config = $path
}

function Install-Core([string]$Id) {
    Initialize-ArduinoConfig
    Invoke-Program $script:Cli @('--config-file',$script:Config,'core','install',$Id)
    Invoke-Program $script:Cli @('--config-file',$script:Config,'core','list')
}

function Install-Libraries {
    Initialize-ArduinoConfig
    Invoke-Program $script:Cli @('--config-file',$script:Config,'lib','update-index')
    $failed = [Collections.Generic.List[string]]::new()
    foreach ($name in $script:Libraries) {
        try { Invoke-Program $script:Cli @('--config-file',$script:Config,'lib','install',$name) }
        catch { $failed.Add($name); Write-Log "ERRO: $name - $($_.Exception.Message)" }
    }
    if ($failed.Count) { throw ('Bibliotecas que falharam: ' + ($failed -join ', ')) }
}

function Get-FtdiUrl {
    try {
        $page = Invoke-WebRequest -UseBasicParsing -Uri 'https://ftdichip.com/drivers/vcp-drivers/' -TimeoutSec 90
        $links = @($page.Links | ForEach-Object { $_.href } | Where-Object { $_ -match '^https://(?:www\.)?ftdichip\.com/.*CDM[^"<>]*WHQL[^"<>]*\.zip$' -and $_ -notmatch 'ARM|Universal' } | Select-Object -Unique)
        if ($links.Count -gt 0) { return $links[0] }
    } catch { Write-Log "Nao foi possivel consultar o catalogo FTDI: $($_.Exception.Message)" }
    Write-Log 'Usando pacote FTDI 2.12.36.20, publicado no catalogo oficial em 04/03/2025. Se o fornecedor bloquear o download, este item sera marcado como falha.'
    return 'https://ftdichip.com/wp-content/uploads/2025/03/CDM-v2.12.36.20-WHQL-Certified.zip'
}

function Get-WchUrl {
    $metadata = Invoke-RestMethod -Uri 'https://www.wch-ic.com/api/official/website/common/relationFiles?fileName=CH341SER_ZIP.html' -TimeoutSec 90
    if ($metadata.code -ne 0 -or $metadata.data.name -ne 'CH341SER.ZIP' -or $metadata.data.id -notmatch '^\d+$') { throw 'O catalogo oficial WCH nao retornou o pacote CH341SER.ZIP esperado.' }
    Write-Log "WCH CH341SER.ZIP: versao $($metadata.data.version), publicada em $($metadata.data.uploadTime)."
    return ('https://www.wch-ic.com/download/file?id=' + $metadata.data.id)
}

function Install-Driver([string]$Id, [string]$Url) {
    $archive = Join-Path $script:RunDir ($Id + '.zip')
    Get-Download $Url $archive
    $folder = Join-Path $script:RunDir ($Id + '-driver')
    Expand-Archive -LiteralPath $archive -DestinationPath $folder -Force
    if ($Id -eq 'ch340') {
        # WCH includes old Windows 9x/XP drivers too. Use its Windows 10/11 set.
        $modern = @(Get-ChildItem -LiteralPath $folder -Directory -Recurse | Where-Object { $_.Name -eq 'WIN 1X' })
        if ($modern.Count -ne 1) { throw 'A estrutura do pacote WCH mudou: pasta WIN 1X nao encontrada. Consulte https://www.wch-ic.com/downloads/CH341SER_ZIP.html' }
        $folder = $modern[0].FullName
    }
    $infs = @(Get-ChildItem -LiteralPath $folder -Filter '*.inf' -Recurse -File)
    $catalogs = @(Get-ChildItem -LiteralPath $folder -Filter '*.cat' -Recurse -File)
    if (-not $infs.Count -or -not $catalogs.Count) { throw "Pacote $Id nao contem arquivos INF/CAT. Nao sera executado nenhum EXE desconhecido." }
    foreach ($cat in $catalogs) { Assert-Signature $cat.FullName }
    # PnPUtil verifies catalog signatures and adds matching packages to the driver store.
    Invoke-Program (Join-Path $env:WINDIR 'System32\pnputil.exe') @('/add-driver',(Join-Path $folder '*.inf'),'/subdirs','/install') -SuccessCodes @(0,3010)
    Write-Log 'Driver adicionado ao Windows. A deteccao da porta exige conectar uma placa compativel.'
}

function Invoke-SelfTest {
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ('oneclick-test-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null
    try {
        $selection = @(Get-Selection 'ide,esp32,ide')
        if ($selection.Count -ne 2) { throw 'Selection deduplication failed.' }
        $rejected = $false
        try { Get-Selection 'invalid' | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw 'Invalid component was accepted.' }
        $config = Join-Path $testRoot 'arduino-cli.yaml'
        [IO.File]::WriteAllText($config, "board_manager:`n  additional_urls: []`ncustom_setting: preserve-me`n")
        $before = [IO.File]::ReadAllBytes($config)
        $threw = $false
        try { Update-ConfigSafely $config { param($f) [IO.File]::WriteAllText($f, 'partial edit'); throw 'expected test failure' } } catch { $threw = $true }
        if (-not $threw -or [Convert]::ToBase64String($before) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes($config))) { throw 'Failed update changed the original configuration.' }
        Update-ConfigSafely $config { param($f) [IO.File]::AppendAllText($f, "# added`n") }
        if (-not [IO.File]::ReadAllText($config).Contains('custom_setting: preserve-me')) { throw 'Configuration preservation failed.' }
        $backups = @(Get-ChildItem -LiteralPath $testRoot -Filter '*.bak')
        if (-not $backups.Count) { throw 'Backup was not created.' }
        $newConfig = Join-Path $testRoot 'new.yaml'
        Update-ConfigSafely $newConfig { param($f) [IO.File]::WriteAllText($f, 'new: value') }
        if (-not (Test-Path -LiteralPath $newConfig)) { throw 'New config was not committed.' }
        Write-Log 'SELF-TEST OK: selection, rejection, backup, rollback, preservation and new configuration. No download or installation.'
    } finally { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

if ($SelfTest) {
    try { Invoke-SelfTest; exit 0 } catch { [Console]::Error.WriteLine($_.Exception.ToString()); exit 1 }
}

try {
    $selected = @(Get-Selection $Components)
    if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -notin @('AMD64')) { throw 'Este instalador requer Windows x64 (Intel/AMD). ARM64 nao e suportado.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Execute o instalador como administrador para instalar os drivers.' }
    if (@(Get-Process -Name 'Arduino IDE','arduino-ide' -ErrorAction SilentlyContinue).Count) { throw 'Feche o Arduino IDE antes de instalar ou alterar a configuracao.' }
    $script:BaseDir = Join-Path $env:LOCALAPPDATA 'OneClick-UNIVAP'
    $script:RunDir = Join-Path $script:BaseDir ('runs\' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    [IO.Directory]::CreateDirectory($script:RunDir) | Out-Null
    $script:LogFile = Join-Path $script:RunDir 'instalacao.log'
    Write-Log "Conta de instalacao: $($identity.Name)"
    Write-Log "Log: $script:LogFile"
    Write-Log 'Os programas sao baixados dos fornecedores. As bibliotecas selecionadas sao um conjunto didatico; a compatibilidade depende da placa e do projeto.'
    $results = [Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($id in $selected) {
        $index++
        Write-Log "@@PROGRESS:$([int](100 * ($index - 1) / $selected.Count))"
        Write-Log "=== $id ($index/$($selected.Count)) ==="
        try {
            switch ($id) {
                'ide' { Install-Ide }
                'cli' { Install-Cli }
                'esp32' { Install-Core 'esp32:esp32' }
                'pico' { Install-Core 'rp2040:rp2040' }
                'mbed' { Install-Core 'arduino:mbed_rp2040' }
                'libraries' { Install-Libraries }
                'cp210x' { Install-Driver 'cp210x' 'https://www.silabs.com/documents/public/software/CP210x_Universal_Windows_Driver.zip' }
                'ch340' { Install-Driver 'ch340' (Get-WchUrl) }
                'ftdi' { Install-Driver 'ftdi' (Get-FtdiUrl) }
            }
            $results.Add([pscustomobject]@{ component = $id; success = $true; error = '' })
            Write-Log "OK: $id"
        } catch {
            $results.Add([pscustomobject]@{ component = $id; success = $false; error = $_.Exception.Message })
            Write-Log "ERRO: $id - $($_.Exception.Message)"
        }
    }
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:RunDir 'resultado.json') -Encoding UTF8
    $failed = @($results | Where-Object { -not $_.success })
    Write-Log '@@PROGRESS:100'
    if ($script:RestartRequired) { Write-Log 'Reinicie o Windows quando for conveniente para concluir a instalacao de drivers.' }
    if ($failed.Count) { Write-Log ('CONCLUIDO COM FALHAS: ' + (($failed | ForEach-Object { $_.component }) -join ', ') + '. Consulte o log e tente novamente os itens com erro.'); exit 1 }
    Write-Log 'CONCLUIDO: todos os componentes selecionados foram instalados. Conecte uma placa e teste um exemplo no Arduino IDE.'
    exit 0
} catch { Write-Log ('ERRO: ' + $_.Exception.Message); exit 1 }
