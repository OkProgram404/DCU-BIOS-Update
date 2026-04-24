----------------------------------------------------------------------------------------------------------

ConfigMgr Install Command:

powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File ".\DCU_BIOS_Update.ps1"

----------------------------------------------------------------------------------------------------------

Current (BIOS only):

$DCUArgs = "/applyUpdates -silent -reboot=disable -updateType=bios,firmware"

----------------------------------------------------------------------------------------------------------

If we want to change to ALL drivers in the future:

$DCUArgs = "/applyUpdates -silent -reboot=disable -updateType=bios,firmware,driver"

----------------------------------------------------------------------------------------------------------

Update type:

bios - BIOS updates

firmware - Dock, Thunderbolt, NIC firmware

driver - Chipset, display, audio, NIC drivers

application - Dell apps (SupportAssist, etc.) — omit if you don't want this

----------------------------------------------------------------------------------------------------------

We can update the registry key names and log messages so they make sense for a broader scope:

Change these in the Configuration region

$RegName = "UpdatesStaged"        # Currnetly BIOSUpdateStaged

And update the $DCUArgs log line - it will reflect automatically


----------------------------------------------------------------------------------------------------------
