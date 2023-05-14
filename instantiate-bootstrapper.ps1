#$param1 = $args[0]

$vmdiskfolder = "$PSScriptRoot\VMdisk"
$vmconfigfolder = "$PSScriptRoot\VMconfig"
$tmpfolder = "$PSScriptRoot\tmp"

function Check-VMDiskLock {
    param(
        [Parameter(Mandatory)]
        [string]$diskpath
    )
    
    $disk = Get-VM `
        | where-object {$_.State -eq 'Running'} `
        | get-vmharddiskdrive `
        | where-object {$_.Path -eq $diskpath} `

    if ($disk -ne $null) {
        write-host "VHD locked by VM $($disk.vmname) -> dying"
        exit 1
    }
}

function Create-Disk {
    param(
        [Parameter(Mandatory)]
        [string]$diskpath,
        [Parameter(Mandatory)]
        [string]$disksize
    )
    if (Test-Path -Path $diskpath -PathType Leaf) {
        Write-Host "VHD existing $diskpath"
        Check-VMDiskLock -diskpath $diskpath
        if ((Get-VHD -Path $diskpath).Attached) {
            Dismount-VHD -Path $diskpath
            Write-Host 'VHD detached'
        }
        Remove-Item -Path $diskpath -Force
        Write-Host 'VHD deleted'
    }

    $diskhandle = New-VHD `
        -Path $diskpath `
        -Dynamic `
        -SizeBytes $disksize
    Write-Host "VHD created $diskpath"
    return $diskhandle
}

function Create-Volume {
    param(
        [Parameter(Mandatory)]
        [string]$diskpath,
        [Parameter(Mandatory)]
        [string]$disklabel,
        [Parameter(Mandatory)]
        [string]$diskfs,
        [Parameter(Mandatory)]
        [string]$disksize
    )

    $diskhandle = Create-Disk -diskpath $diskpath -disksize $disksize

    $volumehandle = Mount-VHD -Passthru $diskhandle.path `
    | Initialize-Disk -Passthru `
    | Remove-Partition -Passthru -PartitionNumber 1 -Confirm:$false `
    | New-Partition `
        -AssignDriveLetter `
        -UseMaximumSize `
    | Format-Volume `
        -FileSystem $diskfs `
        -NewFileSystemLabel $disklabel `
        -Confirm:$false `
        -Force
    Write-Host 'Volume created'
    return $volumehandle
}

switch ($args[0])
{
    'cachedisk'{
        $path='C:\Code\Bootstrapper\VMdisk\Bootstrapper-Cache.vhdx'
        $label='CACHEDISK'
        $fs='FAT32'
        $size=10GB
        $diskhandle=Create-Volume -diskpath $path -disklabel $label -diskfs $fs -disksize $size
        Dismount-VHD $path
        Write-Host 'VHD detached'
    }
    'installdisk'{
        $iso = Get-ChildItem -Path "$($tmpfolder)\*" -Include 'debian-11.*-amd64-netinst.iso'
        $isohandle = Mount-DiskImage -ImagePath $iso
        $isodrletter = ($isohandle | Get-Volume).DriveLetter

        $path='C:\Code\Bootstrapper\VMdisk\Bootstrapper-Install.vhdx'
        $label='INSTALLDISK'
        $fs='FAT'
        $size=1GB
        $diskhandle=Create-Volume -diskpath $path -disklabel $label -diskfs $fs -disksize $size

        $null=New-Item -ItemType Directory -Force -Path "$($diskhandle.DriveLetter):\files"
        Copy-Item `
            -Path "${PSScriptRoot}\*" `
            -Include 'preseed.cfg', 'shellglue.sh' `
            -Destination "$($diskhandle.DriveLetter):\files\"
        Copy-Item `
            -Path "$($tmpfolder)\debian-11.*-amd64-netinst.iso" `
            -Destination "$($diskhandle.DriveLetter):\files\"
        Copy-Item `
            -Path "${PSScriptRoot}\*" `
            -Include 'prov' `
            -Destination "$($diskhandle.DriveLetter):\files\" `
            -Recurse
        Copy-Item `
            -Path "$($isodrletter):\*" `
            -Include 'boot', 'EFI' `
            -Destination "$($diskhandle.DriveLetter):\" `
            -Recurse
        Copy-Item `
            -Path "$($tmpfolder)\*" `
            -Include 'vmlinuz', 'initrd.gz' `
            -Destination "$($diskhandle.DriveLetter):\boot\"
        Copy-Item `
            -Path "${PSScriptRoot}\grub.cfg" `
            -Destination "$($diskhandle.DriveLetter):\boot\grub" `
            -Force
        Write-Host 'Files copied'
        Dismount-VHD $path
        Write-Host 'VHD detached'
        $null=Dismount-DiskImage $iso
    }
    'create' {
        $vmname = 'Bootstrapper'
        $systemdiskpath = "$vmdiskfolder\$vmname-System.vhdx"
        $systemdisksize = 20GB
        $installdiskpath = "$vmdiskfolder\$vmname-Install.vhdx"

        $vmhandle = New-VM `
            -Name $vmname `
            -MemoryStartupBytes 8GB `
            -Path $vmconfigfolder `
            -NoVHD `
            -Generation 2 `
            -SwitchName 'Default Bridge' `
        | Set-VM `
            -ProcessorCount 8 `
            -AutomaticCheckpointsEnabled $false `
            -AutomaticStartAction 'Nothing' `
            -AutomaticStopAction 'ShutDown' `
            -CheckpointType 'ProductionOnly' `
            -Passthru
        Write-Host 'VM configured'
        $systemdiskhandle = Create-Disk -diskpath $systemdiskpath -disksize $systemdisksize
        Write-Host 'VM system disk created'
        Add-VMHardDiskDrive `
            -VMName $vmhandle.name `
            -ControllerType 'SCSI' `
            -ControllerNumber 0 `
            -ControllerLocation 0 `
            -Path $systemdiskhandle.Path
        Write-Host 'VM system disk attached'
        $installdiskhandle=Add-VMHardDiskDrive `
            -VMName $vmhandle.name `
            -ControllerType 'SCSI' `
            -ControllerNumber 0 `
            -ControllerLocation 1 `
            -Path $installdiskpath `
            -Passthru
        Write-Host 'VM install disk attached'
        Add-VMHardDiskDrive `
            -VMName $vmhandle.name `
            -ControllerType 'SCSI' `
            -ControllerNumber 0 `
            -ControllerLocation 2 `
            -Path 'C:\Code\Bootstrapper\VMdisk\Bootstrapper-Cache.vhdx'
        Write-Host 'VM cache disk attached'
        Set-VMFirmware `
            -VMName $vmhandle.name `
            -SecureBootTemplateId '272e7447-90a4-4563-a4b9-8e4ab00526ce' `
            -BootOrder $installdiskhandle
        Write-Host 'VM boot options set'
        Enable-VMIntegrationService `
            -VMName $vmhandle.name `
            -Name 'Guest Service Interface'
        Set-VMhost -EnableEnhancedSessionMode $true
        Write-Host 'VM configured'
    }
    'destroy' {
        Remove-VM -Name Bootstrapper -Force
        Remove-Item -Path 'C:\Code\Bootstrapper\VMdisk\Bootstrapper-System.vhdx' -Force
        Remove-Item -Path 'C:\Code\Bootstrapper\VMconfig\Bootstrapper' -Force -Recurse
    }
    'fetchdebian' {
        $downloadfolder=$tmpfolder
        $files = @(
            @{
                Uri = 'https://deb.debian.org/debian/dists/bullseye/main/installer-amd64/current/images/hd-media/vmlinuz'
                OutFile = "$($downloadfolder)\vmlinuz"
            },
            @{
                Uri = 'https://deb.debian.org/debian/dists/bullseye/main/installer-amd64/current/images/hd-media/initrd.gz'
                OutFile = "$($downloadfolder)\initrd.gz"
            },
            @{
                Uri = 'https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.7.0-amd64-netinst.iso'
                OutFile = "$($downloadfolder)\debian-11.7.0-amd64-netinst.iso"
            }
        )

        $jobs = @()

        foreach ($file in $files) {
            $jobs += Start-ThreadJob -Name $file.OutFile -ScriptBlock {
                $params = $using:file
                Invoke-WebRequest @params
            }
        }
        
        Write-Host "Downloads started..."
        Wait-Job -Job $jobs
        
        foreach ($job in $jobs) {
            Receive-Job -Job $job
        }                



        # if (!(test-path -path $tmpfolder)) {new-item -path $tmpfolder -itemtype directory}
        # Invoke-WebRequest -Uri 'https://deb.debian.org/debian/dists/bullseye/main/installer-amd64/current/images/hd-media/vmlinuz' `
        #     -OutFile "$($tmpfolder)\vmlinuz"
        # Invoke-WebRequest -Uri 'https://deb.debian.org/debian/dists/bullseye/main/installer-amd64/current/images/hd-media/initrd.gz' `
        #     -OutFile "$($tmpfolder)\initrd.gz"
        # Invoke-WebRequest -Uri 'https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.7.0-amd64-netinst.iso' `
        #     -OutFile "$($tmpfolder)\debian-11.7.0-amd64-netinst.iso"
    }
}
