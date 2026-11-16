# One-time setup on Windows (run in PowerShell from the yourviral7 folder). Requires Python 3.11+ and winget.
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
Set-Location $Dir
winget install -e --id Gyan.FFmpeg --accept-source-agreements --accept-package-agreements
winget install -e --id UB-Mannheim.TesseractOCR --accept-source-agreements --accept-package-agreements
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
New-Item -ItemType Directory -Force CONFIG\voices | Out-Null
$V = "CONFIG\voices\en_GB-alan-medium.onnx"
if (!(Test-Path $V)) { Invoke-WebRequest "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alan/medium/en_GB-alan-medium.onnx" -OutFile $V }
if (!(Test-Path "$V.json")) { Invoke-WebRequest "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alan/medium/en_GB-alan-medium.onnx.json" -OutFile "$V.json" }
if (!(Test-Path CONFIG\secrets.env)) { Copy-Item CONFIG\secrets.env.example CONFIG\secrets.env }
$Action = New-ScheduledTaskAction -Execute "$Dir\.venv\Scripts\python.exe" -Argument "-m yv7 start" -WorkingDirectory $Dir
$Trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName "YOURVIRAL7" -Action $Action -Trigger $Trigger -Force
Start-ScheduledTask -TaskName "YOURVIRAL7"
.\.venv\Scripts\python -m yv7 health
