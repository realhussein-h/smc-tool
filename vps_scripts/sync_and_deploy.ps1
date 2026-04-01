# ============================================================
# DATA SYNC + AUTO-DEPLOY SCRIPT
# Runs every 5 minutes on VPS
# Syncs bot data to GitHub + deploys approved changes
# ============================================================

$DESKTOP = "C:\Users\Administrator\Desktop"
$REPO = "C:\Users\Administrator\Desktop\TradingFirm"
$LOG = "$REPO\sync_log.txt"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts | $msg" | Tee-Object -FilePath $LOG -Append
}

while ($true) {
    try {
        # --- SYNC DATA FILES TO REPO ---
        Copy-Item "$DESKTOP\rsi_status_v4.json" "$REPO\data\rsi_status_v4.json" -Force
        Copy-Item "$DESKTOP\rsi_trades_v4.json" "$REPO\data\rsi_trades_v4.json" -Force

        # Copy SMC/moving files if they exist
        if (Test-Path "$DESKTOP\moving_status.json") {
            Copy-Item "$DESKTOP\moving_status.json" "$REPO\data\status.json" -Force
        }
        if (Test-Path "$DESKTOP\moving_trades.json") {
            Copy-Item "$DESKTOP\moving_trades.json" "$REPO\data\trades.json" -Force
        }

        # --- PUSH TO GITHUB ---
        Set-Location $REPO
        git add data/*.json 2>&1 | Out-Null
        $changes = git status --porcelain
        if ($changes) {
            git commit -m "auto-sync bot data 2026-04-01 20:43" 2>&1 | Out-Null
            git push origin main 2>&1 | Out-Null
            Log "SYNCED: data pushed to GitHub"
        }

        # --- CHECK FOR APPROVED DEPLOYMENTS ---
        git pull origin main 2>&1 | Out-Null
        $deploys = Get-ChildItem "$REPO\approved\*.deploy" -ErrorAction SilentlyContinue

        foreach ($trigger in $deploys) {
            $cfg = Get-Content $trigger.FullName -Raw | ConvertFrom-Json

            if ($cfg.approved -ne "CEO") {
                Log "SKIPPED: $($trigger.Name) - not CEO-approved"
                continue
            }

            $target = $cfg.target
            $source = $cfg.source
            Log "DEPLOYING: $source -> $target"

            # Backup current
            $backupName = "$target.backup_20260401_204340"
            Copy-Item "$DESKTOP\$target" "$REPO\backups\$backupName" -Force
            Log "BACKUP: $backupName"

            # Stop bot
            $procs = Get-Process python* -ErrorAction SilentlyContinue |
                     Where-Object { $_.CommandLine -like "*$target*" }
            if ($procs) {
                $procs | Stop-Process -Force
                Log "STOPPED: $target (PID: $($procs.Id -join ', '))"
                Start-Sleep -Seconds 3
            }

            # Replace file on Desktop (where bot runs from)
            Copy-Item "$REPO\$source" "$DESKTOP\$target" -Force
            Log "REPLACED: $target"

            # Restart bot
            Start-Process python -ArgumentList "$DESKTOP\$target" -WorkingDirectory $DESKTOP -WindowStyle Hidden
            Log "RESTARTED: $target"

            # Archive trigger
            Rename-Item $trigger.FullName "$($trigger.FullName).done"
            Log "COMPLETE: deployment done"
        }

    } catch {
        Log "ERROR: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 300
}
