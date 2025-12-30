Function Get-TokenGroups {
    <#
		.SYNOPSIS
			Enumerates the SIDs that are maintained in a user's access token issued at logon and translates the SIDs to group names.

		.DESCRIPTION
			The function gets the access token for the user that was issued at their logon. It reads the TOKEN_GROUPS from the access token and retrieves their SIDs from unmanaged memory. It then attempts to translate these SIDs to group names. The function includes all group memberships inherited from nested grouping.

		.INPUTS
			None

		.OUTPUTS
			System.String[]

		.EXAMPLE
			Get-TokenGroups

			Returns an array of group names and/or SIDs in the access token for the current user.

		.NOTES
			AUTHOR: Michael Haken
			LAST UPDATED: 10/24/2017
	#>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    Param(
    )

    Begin {        
    }

    Process {

        if (!([System.Management.Automation.PSTypeName]"BAMCIS.PowerShell.TokenManipulation.Token").Type) {
			Add-Type -TypeDefinition $script:TokenSignature
		}

        [UInt32]$TokenInformationLength = 0
        
        # This first call will get the token information length
        $ResultValue = [BAMCIS.PowerShell.TokenManipulation.Token]::GetTokenInformation(
                                                                                [System.Security.Principal.WindowsIdentity]::GetCurrent().Token,
                                                                                [BAMCIS.PowerShell.TokenManipulation.Token+TOKEN_INFORMATION_CLASS]::TokenGroups,
                                                                                [System.IntPtr]::Zero,
                                                                                $TokenInformationLength,
                                                                                [ref]$TokenInformationLength
                                                                            )

        if ($TokenInformationLength -gt 0)
        {
            # Create a pointer to hold the information in the token now that we have the length needed
            [IntPtr]$TokenInformation = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($TokenInformationLength)
            $ResultValue = [BAMCIS.PowerShell.TokenManipulation.Token]::GetTokenInformation(
                                                                                [System.Security.Principal.WindowsIdentity]::GetCurrent().Token,
                                                                                [BAMCIS.PowerShell.TokenManipulation.Token+TOKEN_INFORMATION_CLASS]::TokenGroups,
                                                                                $TokenInformation,
                                                                                $TokenInformationLength,
                                                                                [ref]$TokenInformationLength
                                                                            )

            if ($ResultValue -eq $true)
            {
                [BAMCIS.PowerShell.TokenManipulation.Token+TOKEN_GROUPS]$Groups = [System.Runtime.InteropServices.Marshal]::PtrToStructure($TokenInformation, [System.Type][BAMCIS.PowerShell.TokenManipulation.Token+TOKEN_GROUPS])
                [System.Int32]$Size = [System.Runtime.InteropServices.Marshal]::SizeOf([System.Type][BAMCIS.PowerShell.TokenManipulation.Token+SID_AND_ATTRIBUTES])

                try
                {
                    # Start at the TokenInformation pointer,
                    # The compiler aligns each of the fieds in the TOKEN_GROUP struct on the nearest n byte boundary where n is 4 on 32 bit and 8 on 64 bit 
                    # The size of an IntPtr is 8 on 64 bit and 4 on 32 bit
                    [System.Int64]$Base = $TokenInformation.ToInt64() + [System.IntPtr]::Size

                    [System.String[]]$GroupResults = @()

                    for ($i = 0; $i -lt $Groups.GroupCount; $i++)
                    {
                        [System.Int64]$Offset = $Base + ($i * $Size)

                        [BAMCIS.PowerShell.TokenManipulation.Token+SID_AND_ATTRIBUTES]$SidAndAttrsGroup = [System.Runtime.InteropServices.Marshal]::PtrToStructure([IntPtr]($Offset), [System.Type][BAMCIS.PowerShell.TokenManipulation.Token+SID_AND_ATTRIBUTES])
                        [System.String]$Sid = [System.String]::Empty
                        $ResultValue = [BAMCIS.PowerShell.TokenManipulation.Token]::ConvertSidToStringSid($SidAndAttrsGroup.Sid, [ref]$Sid)
                        
                        if ($ResultValue -eq $true)
                        {
                            try
                            {
                                $Group = (New-Object System.Security.Principal.SecurityIdentifier($Sid)).Translate([System.Security.Principal.NTAccount]) | Select-Object -ExpandProperty Value
							    $GroupResults += $Group
                            }
                            catch [Exception] 
                            {
                                $GroupResults += $Sid
                                Write-Log -ErrorRecord $_ -Level WARNING
                            }
                        }
                        else
                        {
                            Write-Log -Message "Failed to get SID for group $i : $((New-Object System.ComponentModel.Win32Exception([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())).Message)." -Level WARNING
                        }
                    }

                    Write-Output -InputObject $GroupResults
                }
                catch [Exception]
                {
                    Write-Log -ErrorRecord $_ -Level FATAL
                }
                finally
                {
                    [BAMCIS.PowerShell.TokenManipulation.Token]::CloseHandle($TokenInformation) | Out-Null
                }
            }
            else
            {
                [BAMCIS.PowerShell.TokenManipulation.Token]::CloseHandle($TokenInformation) | Out-Null
				Write-Log -Message (New-Object System.ComponentModel.Win32Exception([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())).Message -Level WARNING
            }
        }
    }

    End {
    }
}

Function Update-TokenGroupMembership {
	<#
		.SYNOPSIS
			The command refreshes the user's token and clears their current Kerberos tickets in order to pick up Active Directory group membership changes since their last logon.

		.DESCRIPTION
			The current group membership of the user is recorded. Then, the user's Kerberos tickets are purged. After that, the explorer.exe process is stopped and restarted, which refreshes the logon token for the user. The user will be required to enter a set of credentials and then required to enter their password to restart the explorer.exe process.

		.PARAMETER Credential
			The credentials of the current user. These are used to launch a new powershell process to get the updated token group membership. Without using credentials, the new process won't be started with the new token and won't reflect the updates in group membership.

		.PARAMETER UseSmartcard
			If the user only has a Smartcard and does not know their windows password, utilize this switch to enable prompting for Smartcard credentials when explorer.exe restarts. However, they will need to specify a credential object to start a new process to check the token changes.

		.INPUTS
			None

		.OUTPUTS
			None
			
		.EXAMPLE
			Update-TokenGroupMembership -Credential (Get-Credential)

			Updates the group membership for the current user.

		.EXAMPLE
			Update-TokenGroupMembership -UseSmartcard

			Updates the groups membership for the current user, but prompts for Smartcard credentials to restart explorer.exe. Because the Credential parameter was not specified, the changes in the group membership in the token are not displayed.

		.NOTES
			AUTHOR: Michael Haken
			LAST UPDATED: 11/14/2016

	#>
	[CmdletBinding()]
	[OutputType()]
	Param(
		[Parameter(Mandatory = $true)]
		[ValidateNotNull()]
		[System.Management.Automation.Credential()]
		[System.Management.Automation.PSCredential]$Credential = [System.Management.Automation.PSCredential]::Empty,

		[Parameter()]
		[Switch]$UseSmartcard
	)

	Begin {
	}

	Process
	{
		$CurrentGroups = @()
    
		[System.Security.Principal.WindowsIdentity]::GetCurrent().Groups.Translate([System.Security.Principal.NTAccount]) | Select-Object -ExpandProperty Value | ForEach-Object {
			if ($_ -ne $null -and $_ -ne "") {
				$CurrentGroups += $_
			}
		}	

		#The ampersand signifies to execute the following scriptblock and treat each value as a parameter
		& "$env:SYSTEMROOT\system32\klist.exe" purge | Out-Null
		& "$env:SYSTEMROOT\system32\klist.exe" tgt | Out-Null

		& "$env:SYSTEMROOT\system32\taskkill.exe" "/F" "/IM" "explorer.exe" | Out-Null

		if (!$UseSmartcard)
		{
			& "$env:SYSTEMROOT\system32\runas.exe" "/user:$env:USERDOMAIN\$env:USERNAME" "explorer.exe" 
		}
		else
		{
			& "$env:SYSTEMROOT\system32\runas.exe" "/user:$env:USERDOMAIN\$env:USERNAME" "/smartcard" "explorer.exe" 
		}

		if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {

			$Command = @"
		`$Groups = whoami /groups /FO CSV | ConvertFrom-Csv | Select-Object -ExpandProperty "Group Name"
		`$Groups2 = [System.Security.Principal.WindowsIdentity]::GetCurrent().Groups.Translate([System.Security.Principal.NTAccount]) | Select-Object -ExpandProperty Value
		`$Groups += `$Groups2
		`$Groups | Select-Object -Unique
"@

			#Encode the command because it does not like the Open and Close parentheses
	
			$Bytes = [System.Text.Encoding]::Unicode.GetBytes($Command)
			$EncodedCommand = [Convert]::ToBase64String($Bytes)

			#Because Start-Process does not capture the standard out as part of the object, it can only be redirected to a file
			#Use the .NET object in order to capture the standard out without writing to file

			$ProcessInfo = New-Object -TypeName System.Diagnostics.ProcessStartInfo
			$ProcessInfo.FileName = "$env:SYSTEMROOT\System32\windowspowershell\v1.0\powershell.exe"
			$ProcessInfo.CreateNoWindow = $true
			$ProcessInfo.Verb = "runas"
			$ProcessInfo.RedirectStandardError = $true
			$ProcessInfo.RedirectStandardOutput = $true
			$ProcessInfo.UseShellExecute = $false
			$ProcessInfo.LoadUserProfile = $false
			$ProcessInfo.Domain = $Credential.UserName.Substring(0, $Credential.UserName.IndexOf("\"))
			$ProcessInfo.UserName = $Credential.UserName.Substring($Credential.UserName.IndexOf("\") + 1)
			$ProcessInfo.Password = $Credential.Password
			$ProcessInfo.Arguments = "-EncodedCommand $EncodedCommand"
			$Process = New-Object -TypeName System.Diagnostics.Process
			$Process.StartInfo = $ProcessInfo
			$Process.Start() | Out-Null
			$Process.WaitForExit()

			if ($Process.ExitCode -eq 0)
			{
				$NewGroups = @()
				$Process.StandardOutput.ReadToEnd().Split("`r`n") | ForEach-Object {
					if ($_ -ne $null -and $_ -ne [System.String]::Empty) {
						$NewGroups += $_
					}
				}

				Write-Host ""

				foreach ($OldGroup in $CurrentGroups) {
					if (!$NewGroups.Contains($OldGroup) -and $OldGroup -ne "CONSOLE LOGON") {
						Write-Host "REMOVED : $OldGroup" -ForegroundColor Red
					}
				}

				Write-Host ""

				foreach ($NewGroup in $NewGroups) {
					if (!($CurrentGroups.Contains($NewGroup)) -and !$NewGroup.StartsWith("Mandatory Label\")) {
						Write-Host "ADDED : $NewGroup" -ForegroundColor Green
					}
				}
			}
			else
			{
				throw $Process.StandardError.ReadToEnd()
			}
		}
	}

	End {}
}

Function Get-ProcessToken {
	<#
		.SYNOPSIS
			Gets the token handle for a specified process.

		.DESCRIPTION
			The Get-ProcessToken cmdlet gets a token handle pointer for a specified process.
			
            The CmdLet must be run with elevated permissions.

		.PARAMETER ProcessName
			The name of the process to get a token handle for.

		.PARAMETER ProcessId
			The Id of the process to get a token handle for.

		.PARAMETER CloseHandle
			Specifies if the handle to the token should be closed. Do not close the handle if you want to duplicate the token in another process.		

		.EXAMPLE
			Get-ProcessToken -ProcessName lsass

			Gets the token handle for the lsass process.

		.INPUTS
			System.String, System.Int32

		.OUTPUTS
            System.IntPtr

		.NOTES
			AUTHOR: Michael Haken
			LAST UPDATE: 3/25/2016
	#>

	[CmdletBinding()]
	[OutputType([System.IntPtr])]
	Param(
		[Parameter()]
		[Switch]$CloseHandle
	)

	DynamicParam {
		# Create the dictionary 
        $RuntimeParameterDictionary = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameterDictionary

		$Set = Get-Process | Select-Object -Property Name, Id

		New-DynamicParameter -Name "ProcessName" -Alias "Name" -Mandatory -ParameterSets "Name" -Type ([System.String]) -Position 0 -ValueFromPipeline -ValidateSet ($Set | Select-Object -ExpandProperty Name) -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null

		New-DynamicParameter -Name "ProcessId" -Alias "Id" -Mandatory -ParameterSets "Id" -Type ([System.Int32]) -Position 0 -ValueFromPipeline -ValidateSet ($Set | Select-Object -ExpandProperty Id) -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
		
		return $RuntimeParameterDictionary
	}

	Begin {

		if (-not (Test-IsLocalAdmin))
		{
			throw "Run the cmdlet with elevated credentials."
		}

		if (!([System.Management.Automation.PSTypeName]"BAMCIS.PowerShell.TokenManipulation.Token").Type) {
			Add-Type -TypeDefinition $script:TokenSignature
		}
	}

	Process {
        [IntPtr]$DulicateTokenHandle = [IntPtr]::Zero
        [IntPtr]$ProcessTokenHandle = [IntPtr]::Zero

        try {
			switch ($PSCmdlet.ParameterSetName) {
				"Name" {
					$Process = Get-Process -Name $PSBoundParameters["ProcessName"]
					break
				}
				"Id" {
					$Process = Get-Process -Id $PSBoundParameters["ProcessId"]
					break
				}
				default {
					throw "Cannot determine parameter set."
				}
			}

		    $ReturnValue = [BAMCIS.PowerShell.TokenManipulation.Token]::OpenProcessToken($Process.Handle, ([BAMCIS.PowerShell.TokenManipulation.Token]::TOKEN_IMPERSONATE -BOR [BAMCIS.PowerShell.TokenManipulation.Token]::TOKEN_DUPLICATE), [ref]$ProcessTokenHandle)
		    $ReturnValue = [BAMCIS.PowerShell.TokenManipulation.Token]::DuplicateToken($ProcessTokenHandle, [BAMCIS.PowerShell.TokenManipulation.Token+SECURITY_IMPERSONATION_LEVEL]::SecurityImpersonation, [ref]$DulicateTokenHandle)
		
		    if($ReturnValue -eq $null -or $ReturnValue -eq $false) {
			    throw (New-Object -TypeName System.Exception([System.ComponentModel.Win32Exception][System.Runtime.InteropServices.marshal]::GetLastWin32Error()))
		    }
        }
        finally {
            [BAMCIS.PowerShell.TokenManipulation.Token]::CloseHandle($ProcessTokenHandle) | Out-Null

			if ($CloseHandle) {
				[BAMCIS.PowerShell.TokenManipulation.Token]::CloseHandle($DulicateTokenHandle) | Out-Null
			}
        }

		Write-Output -InputObject $DulicateTokenHandle
	}

	End {		
	}
}

Function Set-ProcessToken {
	<#
		.SYNOPSIS
			Replaces the process token for the current process thread with a token from another process.

		.DESCRIPTION
			The Set-ProcessToken cmdlet takes a token handle from another process and then sets the process thread to use that token. Then it closes the token handle. 

			The passed token handle must not be closed before it is passed.
			
            The CmdLet must be run with elevated permissions.

		.PARAMETER TokenHandle
			The Token Handle pointer that will replace the current process thread token.

		.PARAMETER ElevatePrivileges
			Adds the SeDebugPrivilege to the current process thread, which may be needed to replace the current process thread token.	

		.EXAMPLE
			Get-ProcessToken -ProcessName lsass | Set-ProcessToken 

			Gets the token handle for the lsass process and replaces the current process thread token.

		.INPUTS
			System.IntPtr

		.OUTPUTS
            None

		.NOTES
			AUTHOR: Michael Haken
			LAST UPDATE: 10/23/2017
	#>
	[CmdletBinding()]
	[OutputType()]
	Param(
		[Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
		[System.IntPtr]$TokenHandle,

		[Parameter()]
		[Switch]$ElevatePrivileges
	)

	Begin {
		if (-not (Test-IsLocalAdmin)) {
			throw "Run the cmdlet with elevated credentials."
		}
	}

	Process {
		if (!([System.Management.Automation.PSTypeName]"BAMCIS.PowerShell.TokenManipulation.Token").Type) {
			Add-Type -TypeDefinition $script:TokenSignature
		}

		if ($ElevatePrivileges) {
			Set-TokenPrivilege -Privileges SeDebugPrivilege -Enable
		}

		try {
			$ReturnValue = [BAMCIS.PowerShell.TokenManipulation.Token]::SetThreadToken([IntPtr]::Zero, $TokenHandle)

			if($ReturnValue -eq $null -or $ReturnValue -eq $false) {
			    throw (New-Object -TypeName System.Exception([System.ComponentModel.Win32Exception][System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))
		    }
		}
		finally {
			[BAMCIS.PowerShell.TokenManipulation.Token]::CloseHandle($TokenHandle) | Out-Null
		}

		Write-Log -Message "Successfully duplicated token to current process thread." -Level VERBOSE
	}

	End {		
	}
}

Function Reset-ProcessToken {
	<#
		.SYNOPSIS
			Reverts to the process thread token to the current user.

		.DESCRIPTION
			The Reset-ProcessToken cmdlet needs to be called to end any process impersonation called through DdeImpersonateClient, ImpersonateDdeClientWindow, ImpersonateLoggedOnUser, ImpersonateNamedPipeClient, ImpersonateSelf, ImpersonateAnonymousToken or SetThreadToken.
			
			Underlying the cmdlet is a P/Invoke call to RevertToSelf() in AdvApi32.dll.

            The CmdLet must be run with elevated permissions.

		.EXAMPLE
			Reset-ProcessToken

			Reverts the process thread to use the token of the current user.

		.INPUTS
			None

		.OUTPUTS
            None

		.NOTES
			AUTHOR: Michael Haken
			LAST UPDATE: 3/25/2016
	#>

	[CmdletBinding()]
	[OutputType()]
	Param()

	Begin {
		if (-not (Test-IsLocalAdmin)) {
			throw "Run the cmdlet with elevated credentials."
		}
	}

	Process {
		if (!([System.Management.Automation.PSTypeName]"BAMCIS.PowerShell.TokenManipulation.Token").Type) {
			Add-Type -TypeDefinition $script:TokenSignature
		}

		#RevertToSelf is equivalent to SetThreadToken([System.IntPtr]::Zero, [System.IntPtr]::Zero)
		$ReturnValue = [BAMCIS.PowerShell.TokenManipulation.Token]::RevertToSelf()

		if($ReturnValue -eq $null -or $ReturnValue -eq $false) {
			throw (New-Object -TypeName System.Exception([System.ComponentModel.Win32Exception][System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))
		}

		Write-Log -Message "Successfully executed RevertToSelf() and reset the process thread token." -Level VERBOSE
	}

	End {		
	}
}

Function Set-TokenPrivilege {
	<#
		.SYNOPSIS
			Enables or disables security privileges for the current user's process.

		.DESCRIPTION
			This cmdlet enables or disables available security privileges for the current user.

		.PARAMETER Privileges
			The privileges to enable or disable.

		.PARAMETER Enable
			Enables the privileges.

		.PARAMETER Disable
			Disables the privileges.

		.INPUTS
			None
		
		.OUTPUTS
			None

		.EXAMPLE 
			Set-TokenPrivilege -Privileges SeSecurityPrivilege -Enable

			Enables the SeSecurityPrivilege for the user running the cmdlet.

		.NOTES
			AUTHOR: Michael Haken
			LAST UPDATE: 10/23/2017
	#>
	[CmdletBinding()]
	[OutputType()]
	Param(
		## The privilege to adjust. This set is taken from
		## http://msdn.microsoft.com/en-us/library/bb530716(VS.85).aspx
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
		[ValidateSet(
			"SeAssignPrimaryTokenPrivilege", "SeAuditPrivilege", "SeBackupPrivilege",
			"SeChangeNotifyPrivilege", "SeCreateGlobalPrivilege", "SeCreatePagefilePrivilege",
			"SeCreatePermanentPrivilege", "SeCreateSymbolicLinkPrivilege", "SeCreateTokenPrivilege",
			"SeDebugPrivilege", "SeEnableDelegationPrivilege", "SeImpersonatePrivilege", "SeIncreaseBasePriorityPrivilege",
			"SeIncreaseQuotaPrivilege", "SeIncreaseWorkingSetPrivilege", "SeLoadDriverPrivilege",
			"SeLockMemoryPrivilege", "SeMachineAccountPrivilege", "SeManageVolumePrivilege",
			"SeProfileSingleProcessPrivilege", "SeRelabelPrivilege", "SeRemoteShutdownPrivilege",
			"SeRestorePrivilege", "SeSecurityPrivilege", "SeShutdownPrivilege", "SeSyncAgentPrivilege",
			"SeSystemEnvironmentPrivilege", "SeSystemProfilePrivilege", "SeSystemtimePrivilege",
			"SeTakeOwnershipPrivilege", "SeTcbPrivilege", "SeTimeZonePrivilege", "SeTrustedCredManAccessPrivilege",
			"SeUndockPrivilege", "SeUnsolicitedInputPrivilege"
		)]
		[System.String[]]$Privileges,

		[Parameter(ParameterSetName = "Enable", Mandatory = $true)]
		[Switch]$Enable,

		[Parameter(ParameterSetName = "Disable", Mandatory = $true)]
		[Switch]$Disable
	)

	Begin {
		if (-not (Test-IsLocalAdmin)) {
			throw "Run the cmdlet with elevated credentials."
		}

		if (-not ([System.Management.Automation.PSTypeName]"BAMCIS.PowerShell.TokenManipulation.Token").Type) {
            Add-Type -TypeDefinition $script:TokenSignature
        }
	}

	Process {
		foreach ($Privilege in $Privileges)
		{
			[BAMCIS.PowerShell.TokenManipulation.Token+TokPriv1Luid]$TokenPrivilege1Luid = New-Object BAMCIS.PowerShell.TokenManipulation.Token+TokPriv1Luid
			$TokenPrivilege1Luid.Count = 1
			$TokenPrivilege1Luid.Luid = 0

			if ($Enable)
			{
				$TokenPrivilege1Luid.Attr = [BAMCIS.PowerShell.TokenManipulation.Token]::SE_PRIVILEGE_ENABLED
			}
			else 
			{
				$TokenPrivilege1Luid.Attr = [BAMCIS.PowerShell.TokenManipulation.Token]::SE_PRIVILEGE_DISABLED
			}

			[System.IntPtr]$TokenHandle = [System.IntPtr]::Zero
            $Temp = $null

			$ReturnValue = [BAMCIS.PowerShell.TokenManipulation.Token]::LookupPrivilegeValue($null, $Privilege, [ref]$Temp)
            
            if ($ReturnValue -eq $true)
            {
                $TokenPrivilege1Luid.Luid = $Temp

			    $ReturnValue = [BAMCIS.PowerShell.TokenManipulation.Token]::OpenProcessToken([BAMCIS.PowerShell.TokenManipulation.Token]::GetCurrentProcess(), [BAMCIS.PowerShell.TokenManipulation.Token]::TOKEN_ADJUST_PRIVILEGES -BOR [BAMCIS.PowerShell.TokenManipulation.Token]::TOKEN_QUERY, [ref]$TokenHandle)
  
			    $DisableAllPrivileges = $false
			    $ReturnValue = [BAMCIS.PowerShell.TokenManipulation.Token]::AdjustTokenPrivileges($TokenHandle, $DisableAllPrivileges, [ref]$TokenPrivilege1Luid, [System.Runtime.InteropServices.Marshal]::SizeOf($TokenPrivilege1Luid), [IntPtr]::Zero, [IntPtr]::Zero)

			    if($ReturnValue -eq $null -or $ReturnValue -eq $false) 
			    {
				    throw (New-Object -TypeName System.Exception([System.ComponentModel.Win32Exception][System.Runtime.InteropServices.Marrshal]::GetLastWin32Error()))
			    }
            }
            else
            {
                throw (New-Object -TypeName System.Exception([System.ComponentModel.Win32Exception][System.Runtime.InteropServices.Marrshal]::GetLastWin32Error()))
            }
		}
	}

	End {
	}
}


$script:TokenSignature = @"
using System;
using System.Runtime.InteropServices;

namespace BAMCIS.PowerShell.TokenManipulation
{
    public class Token
    {
        public const int ANYSIZE_ARRAY = 1;

        public enum SECURITY_IMPERSONATION_LEVEL
        {
            SecurityAnonymous = 0,
            SecurityIdentification = 1,
            SecurityImpersonation = 2,
            SecurityDelegation = 3
        }

        public enum TOKEN_INFORMATION_CLASS
        {
            /// <summary>
            /// The buffer receives a TOKEN_USER structure that contains the user account of the token.
            /// </summary>
            TokenUser = 1,

            /// <summary>
            /// The buffer receives a TOKEN_GROUPS structure that contains the group accounts associated with the token.
            /// </summary>
            TokenGroups,

            /// <summary>
            /// The buffer receives a TOKEN_PRIVILEGES structure that contains the privileges of the token.
            /// </summary>
            TokenPrivileges,

            /// <summary>
            /// The buffer receives a TOKEN_OWNER structure that contains the default owner security identifier (SID) for newly created objects.
            /// </summary>
            TokenOwner,

            /// <summary>
            /// The buffer receives a TOKEN_PRIMARY_GROUP structure that contains the default primary group SID for newly created objects.
            /// </summary>
            TokenPrimaryGroup,

            /// <summary>
            /// The buffer receives a TOKEN_DEFAULT_DACL structure that contains the default DACL for newly created objects.
            /// </summary>
            TokenDefaultDacl,

            /// <summary>
            /// The buffer receives a TOKEN_SOURCE structure that contains the source of the token. TOKEN_QUERY_SOURCE access is needed to retrieve this information.
            /// </summary>
            TokenSource,

            /// <summary>
            /// The buffer receives a TOKEN_TYPE value that indicates whether the token is a primary or impersonation token.
            /// </summary>
            TokenType,

            /// <summary>
            /// The buffer receives a SECURITY_IMPERSONATION_LEVEL value that indicates the impersonation level of the token. If the access token is not an impersonation token, the function fails.
            /// </summary>
            TokenImpersonationLevel,

            /// <summary>
            /// The buffer receives a TOKEN_STATISTICS structure that contains various token statistics.
            /// </summary>
            TokenStatistics,

            /// <summary>
            /// The buffer receives a TOKEN_GROUPS structure that contains the list of restricting SIDs in a restricted token.
            /// </summary>
            TokenRestrictedSids,

            /// <summary>
            /// The buffer receives a DWORD value that indicates the Terminal Services session identifier that is associated with the token. 
            /// </summary>
            TokenSessionId,

            /// <summary>
            /// The buffer receives a TOKEN_GROUPS_AND_PRIVILEGES structure that contains the user SID, the group accounts, the restricted SIDs, and the authentication ID associated with the token.
            /// </summary>
            TokenGroupsAndPrivileges,

            /// <summary>
            /// Reserved.
            /// </summary>
            TokenSessionReference,

            /// <summary>
            /// The buffer receives a DWORD value that is nonzero if the token includes the SANDBOX_INERT flag.
            /// </summary>
            TokenSandBoxInert,

            /// <summary>
            /// Reserved.
            /// </summary>
            TokenAuditPolicy,

            /// <summary>
            /// The buffer receives a TOKEN_ORIGIN value. 
            /// </summary>
            TokenOrigin,

            /// <summary>
            /// The buffer receives a TOKEN_ELEVATION_TYPE value that specifies the elevation level of the token.
            /// </summary>
            TokenElevationType,

            /// <summary>
            /// The buffer receives a TOKEN_LINKED_TOKEN structure that contains a handle to another token that is linked to this token.
            /// </summary>
            TokenLinkedToken,

            /// <summary>
            /// The buffer receives a TOKEN_ELEVATION structure that specifies whether the token is elevated.
            /// </summary>
            TokenElevation,

            /// <summary>
            /// The buffer receives a DWORD value that is nonzero if the token has ever been filtered.
            /// </summary>
            TokenHasRestrictions,

            /// <summary>
            /// The buffer receives a TOKEN_ACCESS_INFORMATION structure that specifies security information contained in the token.
            /// </summary>
            TokenAccessInformation,

            /// <summary>
            /// The buffer receives a DWORD value that is nonzero if virtualization is allowed for the token.
            /// </summary>
            TokenVirtualizationAllowed,

            /// <summary>
            /// The buffer receives a DWORD value that is nonzero if virtualization is enabled for the token.
            /// </summary>
            TokenVirtualizationEnabled,

            /// <summary>
            /// The buffer receives a TOKEN_MANDATORY_LABEL structure that specifies the token's integrity level. 
            /// </summary>
            TokenIntegrityLevel,

            /// <summary>
            /// The buffer receives a DWORD value that is nonzero if the token has the UIAccess flag set.
            /// </summary>
            TokenUIAccess,

            /// <summary>
            /// The buffer receives a TOKEN_MANDATORY_POLICY structure that specifies the token's mandatory integrity policy.
            /// </summary>
            TokenMandatoryPolicy,

            /// <summary>
            /// The buffer receives the token's logon security identifier (SID).
            /// </summary>
            TokenLogonSid,

            /// <summary>
            /// The maximum value for this enumeration
            /// </summary>
            MaxTokenInfoClass
        }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        public struct TokPriv1Luid
        {
	        public int Count;
	        public long Luid;
	        public int Attr;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct TOKEN_USER 
        { 
            public SID_AND_ATTRIBUTES User; 
        }
        
        [StructLayout(LayoutKind.Sequential)]
        public struct TOKEN_GROUPS
        {
            public UInt32 GroupCount;

            [MarshalAs(UnmanagedType.ByValArray, SizeConst = ANYSIZE_ARRAY)]
            public SID_AND_ATTRIBUTES[] Groups;
        }; 

        [StructLayout(LayoutKind.Sequential)]
        public struct SID_AND_ATTRIBUTES 
        { 
            public IntPtr Sid; 
            public UInt32 Attributes; 
        } 

        [StructLayout(LayoutKind.Sequential)]
        public struct LUID
        {
	        public UInt32 LowPart;
	        public UInt32 HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct LUID_AND_ATTRIBUTES 
        {
	        public LUID Luid;
	        public UInt32 Attributes;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct TOKEN_PRIVILEGES 
        {
	        public UInt32 PrivilegeCount;

	        [MarshalAs(UnmanagedType.ByValArray, SizeConst=ANYSIZE_ARRAY)]
	        public LUID_AND_ATTRIBUTES[] Privileges;
        }

        public const int SE_PRIVILEGE_DISABLED = 0x00000000;
        public const int SE_PRIVILEGE_ENABLED = 0x00000002;
        public const UInt32 SE_GROUP_LOGON_ID = 0xC0000000;
        public const int TOKEN_QUERY = 0x00000008;
        public const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;

        public const UInt32 STANDARD_RIGHTS_REQUIRED = 0x000F0000;
        public const UInt32 STANDARD_RIGHTS_READ = 0x00020000;
        public const UInt32 TOKEN_ASSIGN_PRIMARY = 0x0001;
        public const UInt32 TOKEN_DUPLICATE = 0x0002;
        public const UInt32 TOKEN_IMPERSONATE = 0x0004;
        public const UInt32 TOKEN_QUERY_SOURCE = 0x0010;
        public const UInt32 TOKEN_ADJUST_GROUPS = 0x0040;
        public const UInt32 TOKEN_ADJUST_DEFAULT = 0x0080;
        public const UInt32 TOKEN_ADJUST_SESSIONID = 0x0100;
        public const UInt32 TOKEN_READ = (STANDARD_RIGHTS_READ | TOKEN_QUERY);
        public const UInt32 TOKEN_ALL_ACCESS = (STANDARD_RIGHTS_REQUIRED | TOKEN_ASSIGN_PRIMARY |
	        TOKEN_DUPLICATE | TOKEN_IMPERSONATE | TOKEN_QUERY | TOKEN_QUERY_SOURCE |
            TOKEN_ADJUST_PRIVILEGES | TOKEN_ADJUST_GROUPS | TOKEN_ADJUST_DEFAULT |
            TOKEN_ADJUST_SESSIONID);

        public const string SE_TIME_ZONE_NAMETEXT = "SeTimeZonePrivilege";
        

        [DllImport("advapi32.dll", SetLastError=true)]
		public static extern bool GetTokenInformation( 
		    IntPtr TokenHandle,
			TOKEN_INFORMATION_CLASS TokenInformationClass,
			IntPtr TokenInformation,
			UInt32 TokenInformationLength,
			out UInt32 ReturnLength
		);

        [DllImport("advapi32", SetLastError=true, CharSet=CharSet.Auto)]
		public static extern bool ConvertSidToStringSid(
		    IntPtr pSID,
			[In,Out,MarshalAs(UnmanagedType.LPTStr)] ref string pStringSid
	    );


        [DllImport("advapi32.dll", SetLastError=true)]
        public extern static bool DuplicateToken(
            IntPtr ExistingTokenHandle, 
            Int32 SECURITY_IMPERSONATION_LEVEL, 
            out IntPtr DuplicateTokenHandle
        );

        [DllImport("advapi32.dll", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetThreadToken(
	        IntPtr PHThread,
	        IntPtr Token
        );

        [DllImport("advapi32.dll", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool OpenProcessToken(
            IntPtr ProcessHandle, 
            UInt32 DesiredAccess, 
            out IntPtr TokenHandle
        );

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool LookupPrivilegeValue(
            string host, 
            string name, 
            ref long pluid
        );

        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        public static extern IntPtr GetCurrentProcess();

        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        public static extern bool AdjustTokenPrivileges(
            IntPtr htok, 
            bool disall, 
            ref TokPriv1Luid newst, 
            Int32 len, 
            IntPtr prev, 
            IntPtr relen
        );

        [DllImport( "kernel32.dll", CharSet = CharSet.Auto, SetLastError = true )]
        public static extern bool CloseHandle(IntPtr handle);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool RevertToSelf();  

        [DllImport("kernel32.dll")]
        static extern IntPtr LocalFree(IntPtr hMem);

		public static bool AddPrivilege(string privilege)
		{
			try
			{
				bool ReturnValue;
				TokPriv1Luid TokenPrivilege;
				IntPtr ProcessHandle = GetCurrentProcess();
				IntPtr TokenHandle = IntPtr.Zero;
			
				ReturnValue = OpenProcessToken(ProcessHandle, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out TokenHandle);
				TokenPrivilege.Count = 1;
				TokenPrivilege.Luid = 0;
				TokenPrivilege.Attr = SE_PRIVILEGE_ENABLED;
			
				ReturnValue = LookupPrivilegeValue(null, privilege, ref TokenPrivilege.Luid);
				ReturnValue = AdjustTokenPrivileges(TokenHandle, false, ref TokenPrivilege, 0, IntPtr.Zero, IntPtr.Zero);
				return ReturnValue;
		   }
		   catch (Exception ex)
		   {
				throw ex;
		   }
		}

		public static bool RemovePrivilege(string privilege)
		{
			try
			{
				bool ReturnValue;
				TokPriv1Luid TokenPrivilege;
				IntPtr ProcessHandle = GetCurrentProcess();
				IntPtr TokenHandle = IntPtr.Zero;
			
				ReturnValue = OpenProcessToken(ProcessHandle, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out TokenHandle);
				TokenPrivilege.Count = 1;
				TokenPrivilege.Luid = 0;
				TokenPrivilege.Attr = SE_PRIVILEGE_DISABLED;
			
				ReturnValue = LookupPrivilegeValue(null, privilege, ref TokenPrivilege.Luid);
				ReturnValue = AdjustTokenPrivileges(TokenHandle, false, ref TokenPrivilege, 0, IntPtr.Zero, IntPtr.Zero);
				return ReturnValue;
		   }
		   catch (Exception ex)
		   {
				throw ex;
		   }
		}
    }
}
"@