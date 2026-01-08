param(
  [Parameter(Mandatory=$true)]
  [string]$Sessions,
  [string]$Seed = "assets/questions_seed.json",
  [string]$Tmp = "tmp_seed.json",
  [switch]$PreferNew,
  [switch]$InstallAndroid,
  [string]$AdbPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$argsList = @(
  "tools/update_seed.py",
  "--sessions", $Sessions,
  "--seed", $Seed,
  "--tmp", $Tmp
)
if ($PreferNew) { $argsList += "--prefer-new" }
if ($InstallAndroid) { $argsList += "--install-android" }
if ($AdbPath) { $argsList += @("--adb", $AdbPath) }

python @argsList
