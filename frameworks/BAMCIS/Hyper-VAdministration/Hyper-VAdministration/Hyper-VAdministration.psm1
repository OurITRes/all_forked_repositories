
Function Invoke-KillVM {
	<#
		.SYNOPSIS
			Forces a VM to stop.

		.DESCRIPTION
			The Invoke-KillVM identifies the specific vmwp.exe process for the specified virtual machine and stops the process.
			
            The cmdlet must be run with elevated permissions.

		.PARAMETER VMName
			The name of the VM to stop.

		.PARAMETER VMId
			The Id of the VM to stop.

		.PARAMETER ComputerName
			The Hyper-V host running the virtual machine. This defaults to String.Empty and will execute on the local host.
			
		.PARAMETER Credential		
			The credentials to use to execute the cmdlet. The credentials must have administrator privileges on the specified host.

			If credentials are specified and the computer is the localhost, WinRM is used locally to execute the commands.

		.PARAMETER PassThru
			If specified, the process Id that was stopped is returned.

		.EXAMPLE
			Invoke-KillVM -VMName Server1

			Force stops the virtual machine on the local host with the name Server1.

		.EXAMPLE
			Invoke-KillVM -VMName Sever1 -ComputerName HyperVHost -Credential (Get-Credential)

			Force stops the Server1 virtual machine on the remote host, HyperVHost, and prompts for credentials to be used to complete the action.

		.INPUTS
			System.String

		.OUTPUTS
            System.String

		.NOTES
			AUTHOR: Michael Haken
			LAST UPDATE: 1/3/2017
	#>

	[CmdletBinding(DefaultParameterSetName = "VMName")]
	Param(
		[Parameter(ParameterSetName="VMName", Mandatory=$true, Position = 0, ValueFromPipeline = $true)]
		[System.String]$VMName,
		[Parameter(ParameterSetName="GUID", Mandatory=$true, Position = 0,  ValueFromPipeline = $true)]
		[System.String]$VMId,
		[Parameter()]
		[System.String]$ComputerName = [System.String]::Empty,
		[Parameter()]
		$Credential = [System.Management.Automation.PSCredential]::Empty,
		[Parameter()]
		[Switch]$PassThru
	)

	Begin {
		Import-Module -Name Hyper-V

		Function Kill-VM {
			[CmdletBinding()]
			Param(
				[Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
		        [System.Collections.Hashtable]$InputObject = @{Id = [System.String]::Empty; VMName = [System.String]::Empty},
                [Parameter(Position = 1)]
                [System.Management.Automation.ActionPreference]$VerbosePref = [System.Management.Automation.ActionPreference]::SilentlyContinue,
				[Parameter(Position = 2)]
				[Switch]$PassThru
			)

			Begin {
				
			}

			Process {
				$VerbosePreference = $VerbosePref

                if (![System.String]::IsNullOrEmpty($InputObject.VMName))
                {
                    Write-Verbose -Message "Getting VM by name."
                    [Microsoft.HyperV.PowerShell.VirtualMachine]$VM = Get-VM -Name $InputObject.VMName	
                }
                else 
                {
                    Write-Verbose -Message "Getting VM by Id."
                    [Microsoft.HyperV.PowerShell.VirtualMachine]$VM = Get-VM -Id $InputObject.Id
                }
				
				if ($VM -ne $null)
				{
					Write-Verbose -Message "Getting vm worker process for VM $($VM.Id)."

					#The WMI object has the command line arguments which look like
					#"C:\Windows\System32\vmwp.exe" C17E3A9D-62D6-4AF3-BF98-54371869FA54 0x208
					$ProcessId = Get-CimInstance -ClassName Win32_Process -Filter "name = 'vmwp.exe'" | Where-Object {$_.CommandLine -like "*$($VM.Id)*"} | Select-Object -ExpandProperty ProcessId

					if (![System.String]::IsNullOrEmpty($ProcessId)) 
					{
						Write-Verbose -Message "Stopping process $ProcessId."

						Stop-Process -Id $ProcessId -Force -Confirm:$false

						if ($PassThru)
						{
							Write-Output -InputObject $ProcessId
						}
					}
					else 
					{
						Write-Warning -Message "Could not find a process matching the VM Id: $($VM.Id)."
					}
				}	
				#Do not need an else statement, Get-VM will write a non-terminating error
			}

			End {

			}		
		}
	}

	Process {
		if ($Credential -eq $null)
		{
			$Credential = [System.Management.Automation.PSCredential]::Empty
		}

		$Local = [System.String]::IsNullOrEmpty($ComputerName) -or `
			$ComputerName -eq "." -or `
			$ComputerName.ToLower() -eq "localhost" -or `
			$ComputerName.ToLower() -eq $ENV:COMPUTERNAME.ToLower() -or `
			$ComputerName -eq "127.0.0.1"

		if ($Local -and $Credential -eq [System.Management.Automation.PSCredential]::Empty)
		{
			$Output = Kill-VM -InputObject @{VMName = $VMName; VMId = $VMId} -VerbosePref $VerbosePreference -PassThru:$PassThru
		}
		else 
		{
			$Output = Invoke-Command -ComputerName $ComputerName -ScriptBlock ${function:Kill-VM} -ArgumentList @(@{VMName = $VMName; VMId = $VMId}, $VerbosePreference, $PassThru) -Credential $Credential
		}

		if ($Output -ne $null) 
		{
			Write-Output -InputObject $Output
		}
	}

	End {

	}
}

Function Repair-VMPermissions {
	<#
		.SYNOPSIS
			Repairs the default permissions on virtual machine files.

		.DESCRIPTION
			The Repair-VMPermissions cmdlet adds the appropriate ACL entries on vsv, bin, and virtual hard disk files as well as folders for VMs of version 5.0 and under.
			VMs with a higher version no longer use these configuration files or need the ACL entries to operate. This issue is typically indicated when a virtual machine throws
			a "Failed to Power on with Error 'General access denied error' (0x80070005)".

		.PARAMETER VMName
			The name of the VM to repair permissions for.

		.PARAMETER Id
			The Id of the VM to repair permissions for.

		.PARAMETER Path
			The folder path containing all of the virtual machine configuration and virtual hard disk files. The folder must contain at the minimum a configuration file so the 
			GUID that makes up the file name can be used to ensure there is a matching VM and obtain its Id to create the ACL entries.

		.PARAMETER ComputerName
			The Hyper-V host running the virtual machine. This defaults to String.Empty and will execute on the local host.
			
		.PARAMETER Credential		
			The credentials to use to execute the cmdlet. The credentials must have administrator privileges on the specified host.

			If credentials are specified and the computer is the localhost, WinRM is used locally to execute the commands.

		.EXAMPLE
			Repair-VMPermissions -VMName Server1

			Repairs the permissions on the configuration and virtual hard disk files for the VM Server1.

		.EXAMPLE
			Repair-VMPermissions -VMName Sever1 -ComputerName HyperVHost -Credential (Get-Credential)

			Repairs the permissions on the configuration and virtual hard disk files for the VM Server1 virtual machine on the remote host, 
			HyperVHost, and prompts for credentials to be used to complete the action.

		.EXAMPLE
			Repair-VMPermissions -Path "c:\virtualmachines\server1"

			Repairs the permissions on the files and folders contained under the provided path and ensures that there is a configuration file
			that matches an existing virtual machine.

		.EXAMPLE 
			Repair-VMPermissions -ComputerName "HyperVHost" -Path "\\storagehost\vms\server1" -Credential (Get-Credential)

			Executes the repair with a vm hosted on the server, HyperVHost. The Hyper-V host server uses remote storage on "storagehost" to store the VM files. The provided
			credentials will need permissions to perform Get-VM on the remote Hyper-V host and Set-ACL on the remote storage host.

		.INPUTS
			System.String

		.OUTPUTS
            None

		.NOTES
			AUTHOR: Michael Haken
			LAST UPDATE: 1/3/2017
	#>

	[CmdletBinding(DefaultParameterSetName = "VMName")]
	Param(
		[Parameter(ParameterSetName="VMName", Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
		[System.String]$VMName,
		[Parameter(ParameterSetName="Id", Mandatory = $true, Position = 0)]
		[System.String]$Id,
		[Parameter(ParameterSetName="Path", Mandatory = $true, Position = 0)]
		[System.String]$Path,
		[Parameter(Position = 1)]
		[System.String]$ComputerName = [System.String]::Empty,
		[Parameter()]
		[PSCredential]$Credential = [PSCredential]::Empty
	)

	Begin {
        Function Get-VMDetails {
            [CmdletBinding()]
            Param(
                [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
		        [System.Collections.Hashtable]$InputObject = @{Id = [System.String]::Empty; VMName = [System.String]::Empty},
                [Parameter()]
                [System.Management.Automation.ActionPreference]$VerbosePref = [System.Management.Automation.ActionPreference]::SilentlyContinue
            )

            Begin {

            }

            Process {
                $VerbosePreference = $VerbosePref

                if (![System.String]::IsNullOrEmpty($InputObject.VMName))
                {
                    Write-Verbose -Message "Getting VM by name."
                    [Microsoft.HyperV.PowerShell.VirtualMachine]$VM = Get-VM -Name $InputObject.VMName	
                }
                else 
                {
                    Write-Verbose -Message "Getting VM by Id."
                    [Microsoft.HyperV.PowerShell.VirtualMachine]$VM = Get-VM -Id $InputObject.Id
                }	

                #Where-Object {$_.State -eq [Microsoft.HyperV.PowerShell.VMState]::OffCritical}

                if ($VM -ne $null)
                {
                    if ([System.Decimal]::Parse($VM.Version) -le 5.0)
                    {
				        $TempPaths = @()
				        $TempPaths += $VM.Path
				        $TempPaths += $VM.CheckpointFileLocation
				        $TempPaths += $VM.ConfigurationLocation
				        $TempPaths += $VM.SmartPagingFilePath
				        $TempPaths += $VM.SnapshotFileLocation

				        [System.String[]]$HDPaths = $VM.HardDrives | Select-Object -ExpandProperty Path

				        foreach ($HDPath in $HDPaths)
				        {
                            Write-Verbose -Message "Getting directory for VHD $HDPath."

				            $FileInfo = New-Object System.IO.FileInfo($HDPath)

					        if ($FileInfo.Directory -ne $null)
					        {
					            $TempPaths += $FileInfo.Directory.FullName
					        }
				        }

				        $TempPaths = $TempPaths | Select-Object -Unique	
                        $Paths = @()

                        foreach ($ItemPath in $TempPaths)
                        {
                            $Paths += $ItemPath
					        $Paths += Get-ChildItem -Path $ItemPath -Recurse -Include @("*.vhd", "*.vhdx", "*.avhd", "*.avhdx", "*.bin", "*.vsv") | Select-Object -ExpandProperty FullName
					        $Paths += Get-ChildItem -Path $ItemPath -Recurse -Directory | Select-Object -ExpandProperty FullName
                        }

                        Write-Output -InputObject ([PSCustomObject]@{Paths = $Paths; Id = $VM.Id})
                    }
                    else 
                    {
                        Write-Warning -Message "VM $($InputObject.VMName) version is greater than 5.0 ($($VM.Version)) no permissions to fix."
                    }
                }
                #Do not need an else statement, Get-VM will write an error and continue
            }

            End {

            }
        }  
        
        Function Get-VMPaths {
            [CmdletBinding()]
            Param(
                [Parameter(Mandatory=$true, Position = 0, ValueFromPipeline = $true)]
                [System.String]$Path,
                [Parameter()]
                [System.Management.Automation.ActionPreference]$VerbosePref = [System.Management.Automation.ActionPreference]::SilentlyContinue
            )

            Begin {

            }

            Process {
                $VerbosePreference = $VerbosePref

                $Ids = Get-VM | Select-Object -ExpandProperty Id
                [System.String[]]$Files = Get-ChildItem -Path $Path -Recurse -Include @("*.bin", "*.vsv") | Select-Object -ExpandProperty FullName

                $Id = [System.String]::Empty

                if ($Files.Length -gt 0)
                {
                    foreach ($VMId in $Ids)
				    {
					    $Temp = $Files | Where-Object {$_ -match $VMId}
					    if ($Temp.Count -gt 0)
					    {
						    $Id = $VMId
						    break
					    }
				    }

                    if (![System.String]::IsNullOrEmpty($Id))
                    {
                        Write-Verbose -Message "Found a matching vM with Id $Id."

                        $Paths = @()
                        $VHDs = Get-ChildItem -Path $Path -Recurse -Include @("*.vhd", "*.vhdx", "*.avhd", "*.avhdx") | Select-Object -ExpandProperty FullName

                        foreach ($VHDPath in $VHDs)
                        {
                            Write-Verbose -Message "Getting directory for VHD $HDPath."

                            $FileInfo = New-Object -TypeName System.IO.FileInfo($VHDPath)
                            if ($FileInfo.Directory -ne $null)
                            {
                                $Paths += $FileInfo.Directory.FullName
                            }
                        }

				        $Dirs = Get-ChildItem -Path $Path -Recurse -Directory | Select-Object -ExpandProperty FullName

				        $Paths += $Files
				        $Paths += $VHDs
				        $Paths += $Dirs
				        $Paths += $Path

                        Write-Output -InputObject ([PSCustomObject]@{Paths = $Paths; Id = $Id})
                    }
                    else 
                    {
                        Write-Verbose -Message "No bin or vsv file found that matched an existing VM." 
                    }
                }
                else
                {
                    Write-Verbose -Message "No bin or vsv files found in path, cannot identify VM Id, may be higher than Version 5.0."
                }
            }

            End {

            }
        }  
        
        Function Set-VMACLs {
            [CmdletBinding()]
            Param(
                [Parameter(Mandatory = $true, Position = 0)]
                [System.String[]]$Paths,
                [Parameter(Mandatory = $true, Position = 1)]
                [System.String]$Id,
                [Parameter()]
                [System.Management.Automation.ActionPreference]$VerbosePref = [System.Management.Automation.ActionPreference]::SilentlyContinue
            )

            Begin {

            }

            Process {
                $VerbosePreference = $VerbosePref

                $VMGroupSid = (New-Object -TypeName System.Security.Principal.NTAccount("NT VIRTUAL MACHINE\Virtual Machines")).Translate([System.Security.Principal.SecurityIdentifier])
			    $VMSid = (New-Object -TypeName System.Security.Principal.NTAccount("NT VIRTUAL MACHINE\$Id")).Translate([System.Security.Principal.SecurityIdentifier])

			    [System.Security.AccessControl.FileSystemAccessRule]$FolderRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule(
				    $VMGroupSid,
				    @([System.Security.AccessControl.FileSystemRights]::AppendData, [System.Security.AccessControl.FileSystemRights]::CreateFiles, [System.Security.AccessControl.FileSystemRights]::Read, [System.Security.AccessControl.FileSystemRights]::Synchronize),
				    [System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
				    [System.Security.AccessControl.PropagationFlags]::None,
				    [System.Security.AccessControl.AccessControlType]::Allow
			    )

			    [System.Security.AccessControl.FileSystemAccessRule]$FileAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule(
				    $VMSid,
				    @([System.Security.AccessControl.FileSystemRights]::FullControl),
				    [System.Security.AccessControl.InheritanceFlags]::None,
				    [System.Security.AccessControl.PropagationFlags]::None,
				    [System.Security.AccessControl.AccessControlType]::Allow
			    )

			    [System.Security.AccessControl.FileSystemAccessRule]$VHDAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule(
				    $VMSid,
				    @([System.Security.AccessControl.FileSystemRights]::Read, [System.Security.AccessControl.FileSystemRights]::Write, [System.Security.AccessControl.FileSystemRights]::Synchronize),
				    [System.Security.AccessControl.InheritanceFlags]::None,
				    [System.Security.AccessControl.PropagationFlags]::None,
				    [System.Security.AccessControl.AccessControlType]::Allow
			    )

			    foreach ($Path in $Paths)
			    {
				    $Acl = Get-Acl -Path $Path

				    if ($Path.EndsWith(".vsv") -or $Path.EndsWith(".bin"))
				    {	
					    $Acl.AddAccessRule($FileAccessRule)
				    }
				    elseif ($Path.EndsWith(".vhd") -or $Path.EndsWith(".vhdx") -or $Path.EndsWith(".avhd") -or $Path.EndsWith(".avhdx"))
				    {
					    $Acl.AddAccessRule($VHDAccessRule)
				    }
				    elseif ([System.IO.Directory]::Exists($Path))
				    {
					    $Acl.AddAccessRule($FolderRule)
				    }

                    Write-Host -Object "Setting ACL on $Path."

                    try {
				        Set-Acl -Path $Path -AclObject $Acl
                    }
                    catch [Exception] {
                        Write-Warning -Message "[ERROR] $($_.Exception.Message)"
                    }
			    }
            }

            End {

            }
        }  
	}

	Process {
		if ($Credential -eq $null)
		{
			$Credential = [PSCredential]::Empty
		}

		$Local = [System.String]::IsNullOrEmpty($ComputerName) -or `
			$ComputerName -eq "." -or `
			$ComputerName.ToLower() -eq "localhost" -or `
			$ComputerName.ToLower() -eq $ENV:COMPUTERNAME.ToLower() -or `
			$ComputerName -eq "127.0.0.1"

		$Paths = @()

		switch($PSCmdlet.ParameterSetName)
		{
			{$_ -in "VMName","Id" } {
				if ($Local) {
					$Result = Get-VMDetails -InputObject @{Id = $Id; VMName = $VMName} -VerbosePref $VerbosePreference
				}
				else {
                    $Result = Invoke-Command -ComputerName $ComputerName -ScriptBlock ${function:Get-VMDetails} -ArgumentList (@{Id = $Id; VMName = $VMName}, $VerbosePreference) -Credential $Credential
				}
                
                if ($Result -ne $null)
                {
                    $Id = $Result.Id
                    $Paths = $Result.Paths | Select-Object -Unique
                }

				break
			}			
			"Path" {
				if ($Local -and $Credential -eq [PSCredential]::Empty) 
				{
					$Result = Get-VMPaths -Path $Path -VerbosePref $VerbosePreference				
				}
				else 
				{
					$Result = Invoke-Command -ComputerName $ComputerName -ScriptBlock ${function:Get-VMPaths} -ArgumentList @($Path, $VerbosePreference) -Credential $Credential                    
				}

				if ($Result -ne $null)
				{
					$Paths += $Result.Paths
					$Id = $Result.Id
				}

				break
			}
			default {
				throw "Could not determine the parameter set."
			}
		}

        if ($Paths.Length -gt 0)
        {
		    if ($Local)
		    {
                Set-VMACLs -Paths $Paths -Id $Id -VerbosePref $VerbosePreference			    
		    }
		    else
		    {
                Invoke-Command -ComputerName $ComputerName -ScriptBlock ${function:Set-VMACLs} -ArgumentList @($Paths, $Id, $VerbosePreference) -Credential $Credential
		    }
        }
        else
        {
            Write-Warning -Message "No paths discovered."
        }
	}

	End {

	}
}