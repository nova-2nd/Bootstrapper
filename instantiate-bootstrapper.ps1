$param1 = $args[0]

$tmpfolder = "${PSScriptRoot}\tmp"

switch ($param1)
{
    'create' {
        New-VM `
            -Name 'Bootstrapper' `
            -MemoryStartupBytes 8GB `
            -Path 'C:\Code\Bootstrapper\VMconfig' `
            -NoVHD `
            -Generation 2 `
            -SwitchName 'Default Bridge'
        Set-VM `
            -VMName 'Bootstrapper' `
            -ProcessorCount 8 `
            -AutomaticCheckpointsEnabled $false `
            -AutomaticStartAction 'Nothing' `
            -AutomaticStopAction 'ShutDown' `
            -CheckpointType 'ProductionOnly'
        New-VHD `
            -Path 'C:\Code\Bootstrapper\VMdisk\Bootstrapper-System.vhdx' `
            -Dynamic `
            -SizeBytes 20GB
        Add-VMHardDiskDrive `
            -VMName 'Bootstrapper' `
            -ControllerType 'SCSI' `
            -ControllerNumber 0 `
            -ControllerLocation 0 `
            -Path 'C:\Code\Bootstrapper\VMdisk\Bootstrapper-System.vhdx'
        Add-VMHardDiskDrive `
            -VMName 'Bootstrapper' `
            -ControllerType 'SCSI' `
            -ControllerNumber 0 `
            -ControllerLocation 1 `
            -Path 'C:\Code\Bootstrapper\VMdisk\Bootstrapper-Install.vhdx'
        Set-VMFirmware `
            -VMName 'Bootstrapper' `
            -SecureBootTemplateId '272e7447-90a4-4563-a4b9-8e4ab00526ce' `
            -BootOrder (Get-VMHardDiskDrive -VMName 'Bootstrapper' | Where-Object {$_.ControllerLocation -eq 1})
        Enable-VMIntegrationService `
            -VMName 'Bootstrapper' `
            -Name 'Guest Service Interface'
        Set-VMhost -EnableEnhancedSessionMode $true
    }
    'destroy' {
        Remove-VM -Name Bootstrapper -Force
        Remove-Item -Path 'C:\Code\Bootstrapper\VMdisk\Bootstrapper-System.vhdx' -Force
        Remove-Item -Path 'C:\Code\Bootstrapper\VMconfig\Bootstrapper' -Force -Recurse
    }
    'installinit'{
        Remove-Item -Path 'C:\Code\Bootstrapper\VMdisk\Bootstrapper-Install.vhdx' -Force
        
        $iso = Get-ChildItem -Path "$($tmpfolder)\*" -Include 'debian-11.*-amd64-netinst.iso'
        $isohandle = Mount-DiskImage -ImagePath $iso
        $isodrletter = ($isohandle | Get-Volume).DriveLetter

        $instdisk = New-VHD `
            -Path 'C:\Code\Bootstrapper\VMdisk\Bootstrapper-Install.vhdx' `
            -Dynamic `
            -SizeBytes 1GB `
        | Mount-VHD -Passthru `
        | Initialize-Disk -Passthru `
        | New-Partition `
            -AssignDriveLetter `
            -UseMaximumSize `
        | Format-Volume `
            -FileSystem FAT `
            -Confirm:$false `
            -Force
        Set-Volume -DriveLetter $instdisk.DriveLetter -NewFileSystemLabel INSTALLDISK
        New-Item -ItemType Directory -Force -Path "$($instdisk.DriveLetter):\files"
        Copy-Item `
            -Path "${PSScriptRoot}\*" `
            -Include 'preseed.cfg', 'base-prov.sh' `
            -Destination "$($instdisk.DriveLetter):\files\"
        Copy-Item `
            -Path "$($tmpfolder)\debian-11.*-amd64-netinst.iso" `
            -Destination "$($instdisk.DriveLetter):\files\"
        Copy-Item `
            -Path "${PSScriptRoot}\*" `
            -Include 'prov' `
            -Destination "$($instdisk.DriveLetter):\files\" `
            -Recurse
        Copy-Item `
            -Path "$($isodrletter):\*" `
            -Include 'boot', 'EFI' `
            -Destination "$($instdisk.DriveLetter):\" `
            -Recurse
        Copy-Item `
            -Path "$($tmpfolder)\*" `
            -Include 'vmlinuz', 'initrd.gz' `
            -Destination "$($instdisk.DriveLetter):\boot\"
        Copy-Item `
            -Path "${PSScriptRoot}\grub.cfg" `
            -Destination "$($instdisk.DriveLetter):\boot\grub" `
            -Force
        
        Dismount-VHD 'C:\Code\Bootstrapper\VMdisk\Bootstrapper-Install.vhdx'
        Dismount-DiskImage $iso
        # write-host $instdisk.path
        # $Disk = New-VHD `
        #     -Path 'C:\Code\Bootstrapper\VMdisk\Bootstrapper-Install.vhdx' `
        #     -Dynamic `
        #     -SizeBytes 1GB `
        # | Mount-VHD -Passthru | get-disk 
        # Write-Host $Disk.Path
    }
    'fetchdebian' {
        if (!(test-path -path $tmpfolder)) {new-item -path $tmpfolder -itemtype directory}
        Invoke-WebRequest -Uri 'https://deb.debian.org/debian/dists/bullseye/main/installer-amd64/current/images/hd-media/vmlinuz' `
            -OutFile "$($tmpfolder)\vmlinuz"
        Invoke-WebRequest -Uri 'https://deb.debian.org/debian/dists/bullseye/main/installer-amd64/current/images/hd-media/initrd.gz' `
            -OutFile "$($tmpfolder)\initrd.gz"
        Invoke-WebRequest -Uri 'https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.7.0-amd64-netinst.iso' `
            -OutFile "$($tmpfolder)\debian-11.7.0-amd64-netinst.iso"
    }
}