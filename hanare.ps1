#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent (Resolve-Path $PSCommandPath)
$ImageBase = 'hanare'
$ContainerPrefix = 'hanare'
$TmuxSession = 'main'

# デフォルト値（hanare.conf → 環境変数 → CLI フラグの順で上書き）
$ConfImage = 'default'
$ConfShell = 'zsh'
$ConfDockerOpts = ''

# 設定ファイルの読み込み
$confPath = "$ScriptDir\hanare.conf"
if (Test-Path $confPath -PathType Leaf) {
    Get-Content $confPath | ForEach-Object {
        $line = ($_ -replace '#.*$', '').Trim()
        if ($line) {
            $eqIdx = $line.IndexOf('=')
            if ($eqIdx -gt 0) {
                $key = $line.Substring(0, $eqIdx).Trim()
                $val = $line.Substring($eqIdx + 1).Trim()
                switch ($key) {
                    'IMAGE'       { $script:ConfImage = $val }
                    'SHELL'       { $script:ConfShell = $val }
                    'DOCKER_OPTS' { $script:ConfDockerOpts = $val }
                }
            }
        }
    }
}

# 環境変数で上書き
$envImage = [Environment]::GetEnvironmentVariable('HANARE_IMAGE')
$envShell = [Environment]::GetEnvironmentVariable('HANARE_SHELL')
$envDockerOpts = [Environment]::GetEnvironmentVariable('HANARE_DOCKER_OPTS')
if (-not [string]::IsNullOrEmpty($envImage)) { $ConfImage = $envImage }
if (-not [string]::IsNullOrEmpty($envShell)) { $ConfShell = $envShell }
if (-not [string]::IsNullOrEmpty($envDockerOpts)) { $ConfDockerOpts = $envDockerOpts }

function Die($Message) {
    Write-Error "Error: $Message"
    exit 1
}

function Require-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Die 'docker is not installed'
    }
    docker info *>$null
    if ($LASTEXITCODE -ne 0) {
        Die 'docker daemon is not running or current user lacks permission'
    }
}

function Require-DockerEngine {
    if (-not (Test-Path '\\.\pipe\docker_engine')) {
        Die 'Docker Desktop is not running (\\.\pipe\docker_engine not found)'
    }
}

function Container-Name($DirName) {
    return "$ContainerPrefix-$DirName"
}

$ProxyVarNames = @('HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'no_proxy')

function Get-ProxyBuildArgs {
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($var in $ProxyVarNames) {
        $val = [Environment]::GetEnvironmentVariable($var)
        if (-not [string]::IsNullOrEmpty($val)) {
            $result.AddRange([string[]]@('--build-arg', "$var=$val"))
        }
    }
    return $result
}

function Get-ProxyEnvFlags {
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($var in $ProxyVarNames) {
        $val = [Environment]::GetEnvironmentVariable($var)
        if (-not [string]::IsNullOrEmpty($val)) {
            $result.AddRange([string[]]@('-e', "$var=$val"))
        }
    }
    return $result
}

function Is-ContainerRunning($Name) {
    $result = $null
    try { $result = docker container inspect -f '{{.State.Running}}' $Name 2>&1 } catch {}
    return ($LASTEXITCODE -eq 0 -and $result -eq 'true')
}

function Cmd-Build {
    param([string[]]$Params = @())
    if ($null -eq $Params) { $Params = @() }

    Require-Docker

    $tag = if ($Params.Count -gt 0) { $Params[0] } else { $ConfImage }

    if ($tag -eq 'default') {
        $dockerfile = "$ScriptDir\docker\Dockerfile"
    } else {
        $dockerfile = "$ScriptDir\docker\Dockerfile.$tag"
    }

    if (-not (Test-Path $dockerfile -PathType Leaf)) { Die "Dockerfile not found: $dockerfile" }

    $imageName = "${ImageBase}:${tag}"
    $proxyArgs = Get-ProxyBuildArgs
    $buildArgs = @('build', '-f', $dockerfile)
    $buildArgs += $proxyArgs
    $buildArgs += @('-t', $imageName, $ScriptDir)

    Write-Host "Building image '$imageName' from $dockerfile..."
    & docker @buildArgs
    if ($LASTEXITCODE -ne 0) { Die 'docker build failed' }
}

function Cmd-Start {
    param([string[]]$Params = @())
    if ($null -eq $Params) { $Params = @() }

    $shell = "/bin/$ConfShell"
    $imageTag = $ConfImage
    $i = 0
    while ($i -lt $Params.Count) {
        if ($Params[$i] -eq '--shell') {
            if ($i + 1 -ge $Params.Count) { Die '--shell requires an argument (bash or zsh)' }
            switch ($Params[$i + 1]) {
                'bash' { $shell = '/bin/bash' }
                'zsh'  { $shell = '/bin/zsh' }
                default { Die "Unsupported shell: $($Params[$i + 1]) (bash or zsh)" }
            }
            $i += 2; continue
        }
        if ($Params[$i] -eq '--image') {
            if ($i + 1 -ge $Params.Count) { Die '--image requires an argument' }
            $imageTag = $Params[$i + 1]
            $i += 2; continue
        }
        break
    }

    if ($i -ge $Params.Count) {
        Die 'Usage: hanare start [--image <name>] [--shell bash|zsh] <directory>...'
    }

    $imageName = "${ImageBase}:${imageTag}"

    $targetDirs = [System.Collections.Generic.List[string]]::new()
    $dirNames = [System.Collections.Generic.List[string]]::new()
    while ($i -lt $Params.Count) {
        $td = $Params[$i]
        if (-not (Test-Path $td)) { Die "Path does not exist: $td" }
        if (-not (Test-Path $td -PathType Container)) { Die "Not a directory: $td" }
        $td = (Resolve-Path $td).Path
        $dn = Split-Path -Leaf $td
        if ([string]::IsNullOrEmpty($dn)) { Die 'Cannot mount root directory' }
        if ($dirNames -contains $dn) { Die "Duplicate directory basename: $dn" }
        $targetDirs.Add($td)
        $dirNames.Add($dn)
        $i++
    }

    $containerName = Container-Name $dirNames[0]

    Require-Docker
    Require-DockerEngine

    if (Is-ContainerRunning $containerName) {
        Write-Host "Container '$containerName' is already running. Attaching tmux session..."
        & docker exec -it -e TERM=xterm-256color $containerName tmux new-session -A -s $TmuxSession $shell
        exit $LASTEXITCODE
    }

    # 停止済みコンテナが残っていれば削除
    try { docker container inspect $containerName *>$null } catch {}
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Removing stopped container '$containerName'..."
        docker rm $containerName *>$null
    }

    if (-not (Test-Path "$ScriptDir\config")) { Die "$ScriptDir\config directory not found" }
    if (-not (Test-Path "$ScriptDir\ssh"))    { Die "$ScriptDir\ssh directory not found" }

    try { docker image inspect $imageName *>$null } catch {}
    if ($LASTEXITCODE -ne 0) {
        Die "Image '$imageName' not found. Run 'hanare build $imageTag' first."
    }

    $optionalMounts = [System.Collections.Generic.List[string]]::new()

    if (Test-Path "$HOME\.claude") {
        $optionalMounts.AddRange([string[]]@('-v', "$HOME\.claude:/home/ubuntu/.claude"))
    }
    if (Test-Path "$HOME\.claude.json" -PathType Leaf) {
        $optionalMounts.AddRange([string[]]@('-v', "$HOME\.claude.json:/home/ubuntu/.claude.json"))
    }
    if (Test-Path "$HOME\.codex") {
        $optionalMounts.AddRange([string[]]@('-v', "$HOME\.codex:/home/ubuntu/.codex"))
    }

    if ($shell -eq '/bin/zsh') {
        $zshenv = "$ScriptDir\config\zsh\.zshenv"
        if (-not (Test-Path $zshenv -PathType Leaf)) { Die "$zshenv not found" }
        $optionalMounts.AddRange([string[]]@('-v', "${zshenv}:/home/ubuntu/.zshenv:ro"))
    }

    $miseData = "$ScriptDir\mise-data"
    if (-not (Test-Path $miseData)) { New-Item -ItemType Directory -Path $miseData | Out-Null }

    $proxyEnv = Get-ProxyEnvFlags

    $extraOpts = @()
    if (-not [string]::IsNullOrEmpty($ConfDockerOpts)) {
        $extraOpts = $ConfDockerOpts -split '\s+'
    }

    Write-Host "Starting container '$containerName' (image: $imageName) in background..."
    $dockerArgs = @(
        'run', '-d',
        '--name', $containerName,
        '--add-host', 'host.docker.internal:host-gateway',
        '-e', 'MISE_TRUSTED_CONFIG_PATHS=/workspace'
    )
    $dockerArgs += $proxyEnv
    $dockerArgs += $extraOpts
    $dockerArgs += @(
        '-v', '/var/run/docker.sock:/var/run/docker.sock',
        '-v', "$ScriptDir\config:/home/ubuntu/.config/",
        '-v', "$ScriptDir\ssh:/home/ubuntu/.ssh:ro",
        '-v', "${miseData}:/home/ubuntu/.local/share/mise"
    )
    $dockerArgs += $optionalMounts
    for ($vi = 0; $vi -lt $targetDirs.Count; $vi++) {
        $dockerArgs += @('-v', "$($targetDirs[$vi]):/workspace/$($dirNames[$vi])")
    }
    $dockerArgs += @($imageName, 'sleep', 'infinity')
    & docker @dockerArgs *>$null
    if ($LASTEXITCODE -ne 0) { Die 'docker run failed' }

    # コンテナが起動しているか確認（Docker Desktop は起動に時間がかかる場合がある）
    Start-Sleep -Seconds 1
    if (-not (Is-ContainerRunning $containerName)) {
        Write-Host "Container '$containerName' exited. Logs:" -ForegroundColor Red
        docker logs $containerName
        docker rm $containerName *>$null
        Die 'container failed to start (see logs above)'
    }

    Write-Host "Initializing tools..."
    & docker exec $containerName init.sh
    if ($LASTEXITCODE -ne 0) { Die 'init.sh failed' }

    Write-Host "Attaching tmux session..."
    & docker exec -it -e TERM=xterm-256color $containerName tmux new-session -A -s $TmuxSession $shell
    exit $LASTEXITCODE
}

function Cmd-Attach {
    param([string[]]$Params = @())
    if ($null -eq $Params) { $Params = @() }

    $shell = "/bin/$ConfShell"
    $i = 0
    while ($i -lt $Params.Count) {
        if ($Params[$i] -eq '--shell') {
            if ($i + 1 -ge $Params.Count) { Die '--shell requires an argument (bash or zsh)' }
            switch ($Params[$i + 1]) {
                'bash' { $shell = '/bin/bash' }
                'zsh'  { $shell = '/bin/zsh' }
                default { Die "Unsupported shell: $($Params[$i + 1]) (bash or zsh)" }
            }
            $i += 2; continue
        }
        break
    }

    Require-Docker

    if ($i -ge $Params.Count) {
        $containers = docker ps --filter "name=^${ContainerPrefix}-" --format '{{.Names}}'
        if ($LASTEXITCODE -ne 0) { Die 'docker ps failed' }

        if ([string]::IsNullOrEmpty($containers)) {
            Die 'No running hanare containers'
        }

        $list = @($containers -split "`n" | Where-Object { -not [string]::IsNullOrEmpty($_) })
        if ($list.Count -eq 1) {
            $containerName = $list[0]
        } else {
            Write-Host 'Multiple running containers. Specify one:'
            foreach ($name in $list) {
                Write-Host "  $($name.Substring($ContainerPrefix.Length + 1))"
            }
            exit 1
        }
    } else {
        $containerName = Container-Name $Params[$i]
    }

    if (-not (Is-ContainerRunning $containerName)) {
        Die "Container '$containerName' is not running"
    }

    & docker exec -it -e TERM=xterm-256color $containerName tmux new-session -A -s $TmuxSession $shell
    exit $LASTEXITCODE
}

function Cmd-Stop {
    param([string[]]$Params = @())
    if ($null -eq $Params) { $Params = @() }

    if ($Params.Count -eq 0) { Die 'Usage: hanare stop <directory>' }

    $targetDir = $Params[0]
    if (-not (Test-Path $targetDir)) { Die "Path does not exist: $targetDir" }
    if (-not (Test-Path $targetDir -PathType Container)) { Die "Not a directory: $targetDir" }
    $targetDir = (Resolve-Path $targetDir).Path

    $dirName = Split-Path -Leaf $targetDir
    $containerName = Container-Name $dirName

    Require-Docker

    try { docker container inspect $containerName *>$null } catch {}
    if ($LASTEXITCODE -ne 0) {
        Die "Container '$containerName' does not exist"
    }

    Write-Host "Stopping container '$containerName'..."
    docker rm -f $containerName *>$null
    if ($LASTEXITCODE -ne 0) { Die 'docker rm failed' }
    Write-Host 'Stopped.'
}

function Cmd-Clean {
    Require-Docker

    $containers = docker ps -a --filter "name=^${ContainerPrefix}-" --format '{{.Names}}'
    if ($LASTEXITCODE -ne 0) { Die 'docker ps failed' }

    if (-not [string]::IsNullOrEmpty($containers)) {
        Write-Host 'Stopping and removing all hanare containers...'
        $containers -split "`n" | ForEach-Object {
            if (-not [string]::IsNullOrEmpty($_)) {
                docker rm -f $_ *>$null
                Write-Host "  Removed $_"
            }
        }
    } else {
        Write-Host 'No hanare containers to remove.'
    }

    $images = docker images $ImageBase --format '{{.Repository}}:{{.Tag}}'
    if ($LASTEXITCODE -ne 0) { Die 'docker images failed' }

    if (-not [string]::IsNullOrEmpty($images)) {
        Write-Host 'Removing hanare images...'
        $images -split "`n" | ForEach-Object {
            if (-not [string]::IsNullOrEmpty($_)) {
                docker rmi $_ *>$null
                Write-Host "  Removed $_"
            }
        }
    } else {
        Write-Host 'No hanare images to remove.'
    }
}

function Cmd-Status {
    Require-Docker

    $containers = docker ps --filter "name=^${ContainerPrefix}-" --format '{{.Names}}\t{{.Status}}\t{{.Image}}'
    if ($LASTEXITCODE -ne 0) { Die 'docker ps failed' }

    if ([string]::IsNullOrEmpty($containers)) {
        Write-Host 'No running hanare containers.'
    } else {
        Write-Host 'Running hanare containers:'
        $containers -split "`n" | ForEach-Object {
            $parts = $_ -split "`t"
            Write-Host "  $($parts[0])  ($($parts[1]))  [$($parts[2])]"
        }
    }
}

function Cmd-Help {
    Write-Host @"
Usage: hanare <command>

Commands:
    build [<name>]   Build a container image (default: docker/Dockerfile)
                     With <name>: build from docker/Dockerfile.<name>
    start [--image <name>] [--shell bash|zsh] <dir>...
                     Start a new container for <dir>
                     Multiple directories can be mounted at once
    attach [--shell bash|zsh] [<name>]
                     Attach to a running container by name
                     Without <name>: auto-select if only one is running
    stop <dir>       Stop and remove the container for <dir>
    clean            Stop all containers and remove all hanare images
    status           Show running hanare containers
    help             Show this help

Images:
    hanare build            -> hanare:default  (from docker/Dockerfile)
    hanare build myenv      -> hanare:myenv    (from docker/Dockerfile.myenv)
    hanare start --image myenv <dir>  (use hanare:myenv)

Defaults:
    Create hanare.conf to change defaults:
        IMAGE=myenv
        SHELL=bash
    Or use environment variables: HANARE_IMAGE, HANARE_SHELL
    CLI flags (--image, --shell) take highest priority.

Proxy:
    Set HTTP_PROXY, HTTPS_PROXY, NO_PROXY environment variables
    before running build/start. They are passed to Docker automatically.
"@
}

# メインディスパッチ
$command = if ($args.Count -gt 0) { $args[0] } else { 'help' }
$remaining = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

switch ($command) {
    'build'  { Cmd-Build -Params $remaining }
    'start'  { Cmd-Start -Params $remaining }
    'attach' { Cmd-Attach -Params $remaining }
    'stop'   { Cmd-Stop -Params $remaining }
    'clean'  { Cmd-Clean }
    'status' { Cmd-Status }
    { $_ -in 'help', '--help', '-h' } { Cmd-Help }
    default  {
        Write-Error "Unknown command: $command"
        Cmd-Help
        exit 1
    }
}
