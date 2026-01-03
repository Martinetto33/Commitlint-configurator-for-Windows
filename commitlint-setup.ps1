# Interactive PowerShell installer for global commitlint hooks (single prompt)
# - Asks once for the target directory (YOUR_DIRECTORY)
# - Installs / verifies Node + commitlint if possible
# - Creates commitlint.config.js, .githooks\commit-msg.ps1 and .githooks\commit-msg
# - Configures `git config --global core.hooksPath "<YOUR_DIRECTORY>\.githooks"`
# - Uses ASCII-friendly hook output to avoid encoding issues in IntelliJ
# Note: This script performs actions without any further prompts after the directory input.

Write-Host ""
Write-Host "This script may install the following tools if they are not already present:"
Write-Host ""
Write-Host "  - Scoop: a lightweight Windows package manager (used to install developer tools safely)"
Write-Host "  - Node.js: JavaScript runtime required to run commitlint"
Write-Host "  - commitlint: enforces consistent, high-quality Git commit messages"
Write-Host ""
Write-Host "No system-wide changes are made; everything is installed for the current user only."
Write-Host ""


# Ask the user once for the base directory to put the global hooks and config
$BaseDir = Read-Host "Enter full path for global commitlint directory (e.g. C:\Users\you\OneDrive - YourDir\Development)"
if ([string]::IsNullOrWhiteSpace($BaseDir)) {
    Write-Error "No directory provided. Exiting."
    exit 1
}

# Normalize user-provided base directory
$BaseDir = $BaseDir.Trim()

# Remove surrounding quotes if user pasted a quoted path
if (
    ($BaseDir.StartsWith('"') -and $BaseDir.EndsWith('"')) -or
    ($BaseDir.StartsWith("'") -and $BaseDir.EndsWith("'"))
) {
    $BaseDir = $BaseDir.Substring(1, $BaseDir.Length - 2)
}

# Expand environment variables (e.g. %USERPROFILE%)
$BaseDir = [Environment]::ExpandEnvironmentVariables($BaseDir)

# Resolve to absolute path (fails early if invalid)
try {
    $ResolvedBaseDir = (Resolve-Path -Path $BaseDir -ErrorAction Stop).Path
}
catch {
    Write-Error "Invalid base directory path: $BaseDir"
    exit 1
}

$ResolvedBaseDir = (Resolve-Path $BaseDir).Path

# Prepare hooks directory
$HooksDir = Join-Path $ResolvedBaseDir ".githooks"

# Helper: write text as UTF-8 without BOM (works for PowerShell 5.1+ and Core)
function Write-TextUtf8NoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content,
        [switch]$EnsureDir
    )
    if ($EnsureDir) {
        $dir = [System.IO.Path]::GetDirectoryName($Path)
        if (-not [string]::IsNullOrEmpty($dir) -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell Core supports UTF8NoBOM directly
        Set-Content -Path $Path -Value $Content -Encoding UTF8NoBOM -Force
    } else {
        # PowerShell 5.1 fallback: write bytes without BOM
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $bytes = $utf8NoBom.GetBytes($Content)
        [System.IO.File]::WriteAllBytes($Path, $bytes)
    }
}

# Check prerequisites: Git is required
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Git not found in PATH. Please install Git for Windows and re-run this script."
    exit 1
}

# Ensure base directories exist
if (-not (Test-Path $BaseDir)) {
    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
}
if (-not (Test-Path $HooksDir)) {
    New-Item -ItemType Directory -Path $HooksDir -Force | Out-Null
}

# Attempt to ensure Node/npm + commitlint are available.
# If Node is missing, attempt to install via Scoop (non-interactive). If Scoop missing,
# install Scoop automatically (user consent implied by running this script).
function Ensure-NodeAndCommitlint {
    # Check node
    if (Get-Command node -ErrorAction SilentlyContinue) {
        Write-Host "Node detected: $(node --version)"
    } else {
        # Try scoop
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            Write-Host "Scoop not found. Installing Scoop for the current user..."
            try {
                # Allow RemoteSigned for current user so scoop install doesn't fail (no prompt)
                Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            } catch {
                # ignore failures to set execution policy
            }
            try {
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh'))
            } catch {
                Write-Warning "Failed to install Scoop automatically. Please install Node.js manually and re-run the script."
                return $false
            }
            # Add scoop shims to current PATH if present
            $scoopShims = Join-Path $env:USERPROFILE "scoop\shims"
            if (Test-Path $scoopShims) {
                $env:Path = "$scoopShims;$env:Path"
            }
        }

        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Host "Installing node (via scoop)..."
            try {
                scoop install nodejs | Out-Null
            } catch {
                Write-Warning "scoop install nodejs failed. Please install Node.js manually and re-run the script."
                return $false
            }
            # ensure shims path in current session
            $scoopShims = Join-Path $env:USERPROFILE "scoop\shims"
            if (Test-Path $scoopShims) {
                $env:Path = "$scoopShims;$env:Path"
            }
        } else {
            Write-Warning "Scoop not available and automatic install failed. Please install Node.js manually and re-run."
            return $false
        }

        if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
            Write-Warning "Node still not found after attempted installation. Please ensure Node.js is in PATH and re-run."
            return $false
        }
    }

    # Ensure npm present
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warning "npm not found even though node exists. Please ensure npm is installed and available in PATH."
        return $false
    }

    # Install commitlint globally (idempotent)
    try {
        Write-Host "Installing/updating commitlint CLI and config globally via npm..."
        & npm install -g @commitlint/cli @commitlint/config-conventional | Out-Null
    } catch {
        Write-Warning "Global npm install failed. You may need to run this script in a shell with appropriate permissions, or install commitlint manually:"
        Write-Warning "  npm install -g @commitlint/cli @commitlint/config-conventional"
        return $false
    }

    # Confirm npx available
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        # npx ships with npm 5.2+, but newer Node might have npx at npx.cmd
        Write-Warning "npx not found. commitlint runs may fail. Please ensure npx is available (npm >=5.2)."
    }

    return $true
}

$ok = Ensure-NodeAndCommitlint
if (-not $ok) {
    Write-Warning "Continuing with hook files creation, but commitlint may not run until Node/npm/commitlint are available."
}

# Create commitlint.config.js in base directory
$commitlintConfigPath = Join-Path $ResolvedBaseDir "commitlint.config.js"
$commitlintConfigContent = @'
// Global commitlint configuration (conventional commits)
module.exports = {
  extends: ["@commitlint/config-conventional"]
};
'@.Trim()
Write-TextUtf8NoBom -Path $commitlintConfigPath -Content $commitlintConfigContent -EnsureDir

# Prepare commit-msg.ps1 content (ASCII-friendly, uses explicit config path)
# We'll inject the absolute config path into the generated PS1 file.
$escapedConfigPath = $commitlintConfigPath -replace "'", "''"
$ps1Template = @'
param(
    [Parameter(Mandatory = $true)]
    [string]$CommitMsgFile
)

# Ensure commit message file exists
if (-not (Test-Path $CommitMsgFile)) {
    Write-Error "commitlint: commit message file not found: $CommitMsgFile"
    exit 1
}

$ConfigPath = __CONFIG_PATH__

# Ensure config exists
if (-not (Test-Path $ConfigPath)) {
    Write-Error "commitlint: config file not found at $ConfigPath"
    exit 1
}

# Run commitlint (npx.cmd on Windows ensures the .cmd shim is used)
& npx.cmd --yes @commitlint/cli `
    --edit "$CommitMsgFile" `
    --config "$ConfigPath" `
    --verbose `
    --color

$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
	# Clear line, print a clear ASCII banner (avoids Unicode encoding issues)
	Write-Host ""
	Write-Host "!! Commit message rejected by commitlint !!" -ForegroundColor Red
	Write-Host "-------------------------------------------"
	Write-Host ""
    Write-Host ""
    Write-Host "Expected format:"
    Write-Host "  <type>(<scope>): <subject>"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  feat(auth): add login endpoint"
    Write-Host "  fix(api): handle null response"
    Write-Host "  build: update dependencies"
    Write-Host ""
}

exit $exitCode
'@

# Replace placeholder with a single-quoted path literal
$ps1Content = $ps1Template -replace "__CONFIG_PATH__", "'$escapedConfigPath'"

$ps1Path = Join-Path $HooksDir "commit-msg.ps1"
Write-TextUtf8NoBom -Path $ps1Path -Content $ps1Content -EnsureDir

# Create the shell-compatible hook wrapper (LF line endings, no BOM)
$shellScriptContent = @'
#!/bin/sh
# Minimal POSIX wrapper to call the PowerShell hook on Windows.

# Ensure we are running from the hooks directory
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# Ensure this file uses LF line endings and no BOM.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$0")/commit-msg.ps1" "$1"
exit $?
'@.TrimEnd() + "`n"  # ensure final LF

# Write the shell script with UTF-8 no BOM and LF line endings
# Use raw bytes to guarantee no BOM and LF endings even on PS5.1
$shellScriptPath = Join-Path $HooksDir "commit-msg"
Write-TextUtf8NoBom -Path $shellScriptPath -Content $shellScriptContent -EnsureDir

# On Git for Windows, ensure the shell script is not blocked (attempt to set executable bit for Git's index)
# Note: On Windows file system the executable bit is not meaningful, but Git's MSYS will run the script.
try {
    # If git is available, try to set the exec bit in the index for this file (so it is recognized as executable by Git)
    & git update-index --add --chmod=+x "$shellScriptPath" 2>$null
} catch {
    # ignore - this is best-effort
}

# Configure Git to use the global hooksPath
try {
    & git config --global core.hooksPath $HooksDir
    Write-Host ""
    Write-Host "Global hooks path set to: $HooksDir"
} catch {
    Write-Warning "Failed to set global core.hooksPath. You can set it manually with:"
    Write-Warning "  git config --global core.hooksPath `"$HooksDir`""
}

# Final status summary (ASCII)
Write-Host ""
Write-Host "Setup complete (or partially complete if prerequisites failed)."
Write-Host "Created files:"
Write-Host "  - $commitlintConfigPath"
Write-Host "  - $ps1Path"
Write-Host "  - $shellScriptPath"
Write-Host ""
Write-Host "To verify quickly:"
Write-Host ('  cd "{0}"' -f $env:TEMP)
Write-Host "  mkdir commitlint-test ; cd commitlint-test"
Write-Host "  git init"
Write-Host "  git config user.email \"test@example.com\""
Write-Host "  git config user.name \"Test User\""
Write-Host "  git commit --allow-empty -m \"bad message\"   # should be rejected"
Write-Host "  git commit --allow-empty -m \"feat: good message\"  # should succeed"
Write-Host ""
Write-Host "If commitlint rejects commits in IntelliJ with a clear ASCII banner, the setup is working."
Write-Host ""