<#PSScriptInfo
.GUID
	d572020a-7583-4867-a845-bb9737b1ecd9
.VERSION 
	1.0.0.3
.AUTHOR 
	Michael Haken
.COMPANYNAME 
	BAMCIS
.COPYRIGHT 
	(c) 2016 BAMCIS. All rights reserved.
.TAGS 
	WMI ScheduledTasks TaskScheduler
.LICENSEURI 
	https://raw.githubusercontent.com/bamcisnetworks/Win32ScheduledTask/master/LICENSE
.PROJECTURI
	https://github.com/bamcisnetworks/Win32ScheduledTask
.ICONURI 
.EXTERNALMODULEDEPENDENCIES 
.REQUIREDSCRIPTS 
.EXTERNALSCRIPTDEPENDENCIES 
.RELEASENOTES
	Fixed the CIM class check for installation success.
#>

<#
	.SYNOPSIS
		Creates the Win32_ScheduledTask WMI class on the local computer or a remote computer.

	.DESCRIPTION
		The cmdlet creates a custom WMI class for enumerating scheduled task information. It creates a temporary mof file on the SystemDrive and calls mofcomp.exe to add the WMI class.

	.PARAMETER ComputerName
		The computer to create the custom WMI classes on. This defaults to [System.String]::Empty, which will execute on the local host. If the target is a remote computer, Invoke-Command is used to execute the underlying function.

	.PARAMETER TempFilePath
		Where the temporary mof file is stored, this defaults to %SYSTEMDRIVE%\ScheduledTasks.mof.

	.PARAMETER Credential
		The credential to use to execute the script.

		If credentials are specified and the computer is the localhost, WinRM is used locally to execute the commands.

    .EXAMPLE
		Set-Win32ScheduledTasks

		Creates the custom WMI class on the local computer.

	.EXAMPLE
		Set-Win32ScheduledTasks -ComputerName server1.contoso.com -Credential (Get-Credential)

		Creates the custom WMI class on server1.contoso.com.

	.INPUTS
		None

	.OUTPUTS
		None

	.NOTES
		AUTHOR: Michael Haken
		LAST UPDATE: 1/15/2017
#>

Param
(
    [Parameter(Position = 0)]
    [System.String]$ComputerName = [System.String]::Empty,

	[Parameter(Position= 1)]
	[System.String]$TempFilePath = "$env:SYSTEMDRIVE\ScheduledTasks_$([System.Guid]::NewGuid()).mof",

    [Parameter()]
	[ValidateNotNull()]
    [System.Management.Automation.Credential()]
    [System.Management.Automation.PSCredential]$Credential = [System.Management.Automation.PSCredential]::Empty
)

Function Set-WMIClass 
{
	<#
		.SYNOPSIS
			Creates the Win32_ScheduledTasks WMI class.

		.DESCRIPTION
			The cmdlet creates a custom WMI class for enumerating scheduled task information. It creates a temporary mof file on the SystemDrive and calls mofcomp.exe to add the WMI class.

		.PARAMETER TempFilePath
			Where the temporary mof file is stored, this defaults to %SYSTEMDRIVE%\ScheduledTasks_$([System.Guid]::NewGuid()).mof.

        .EXAMPLE
			Set-WMIClass

			Creates the custom class

		.EXAMPLE
			Set-WMIClass -TempFilePath c:\file.mof

			Creates the custom WMI class and stores the temporary mof file at c:\file.mof.

		.INPUTS
			None

		.OUTPUTS
			None

		.NOTES
			AUTHOR: Michael Haken
			LAST UPDATE: 1/15/2017
	#>
	[CmdletBinding()]
	Param(
		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[System.String]$TempFilePath = "$env:SYSTEMDRIVE\ScheduledTasks_$([System.Guid]::NewGuid()).mof"
	)

    Begin
    {
        if (!([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
        {
			throw "Script must be run with administrator privileges."
		}
        
        $WMIClass = "win32_ScheduledTasks"
    
        $Contents = @"
#pragma namespace("\\\\.\\root\\cimv2")
#PRAGMA AUTORECOVER

[dynamic, provider("RegProv"),
ProviderClsid("{fe9af5c0-d3b6-11ce-a5b6-00aa00680c3f}"),ClassContext("local|HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Schedule\\TaskCache\\Tasks")]
class $WMIClass
{
    [key] string KeyName;
    [read, propertycontext("Actions")] uint8 Actions[];
    [read, propertycontext("Author")] string Author;
    [read, propertycontext("Data")] string Data; 
    [read, propertycontext("Date")] string Date; 
    [read, propertycontext("Description")] string Description;
    [read, propertycontext("DynamicInfo")] uint8 DynamicInfo[];
    [read, propertycontext("Hash")] uint8 Hash[];
    [read, propertycontext("Path")] string Path;
    [read, propertycontext("Schema")] uint32 Schema; 
    [read, propertycontext("SecurityDescriptor")] string SecurityDescriptor;
    [read, propertycontext("Source")] string Source;
    [read, propertycontext("Triggers")] uint8 Triggers[];
    [read, propertycontext("URI")] string URI; 
    [read, propertycontext("Version")] string Version; 

};
"@
    }

    Process
    {
		if ([System.String]::IsNullOrEmpty($TempFilePath)) {
			$TempFilePath = "$env:SYSTEMDRIVE\ScheduledTasks_$([System.Guid]::NewGuid()).mof"
		}

        Set-Content -Path $TempFilePath -Value $Contents | Out-Null

        $ScheduledTask = Get-CimClass -ClassName $WMIClass -Namespace "root/cimv2" -ErrorAction SilentlyContinue

		$InstallType = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name InstallationType | Select-Object -ExpandProperty InstallationType

		if ($ScheduledTask -ne $null)
        {
			if ($InstallType -eq "Nano Server") 
			{
				Start-Process -FilePath "$($env:SystemRoot)\system32\wbem\wmic.exe" -ArgumentList @("class $WMIClass delete") -Wait | Out-Null
			}
			else 
			{
				Start-Process -FilePath "$($env:SystemRoot)\system32\wbem\wmic.exe" -ArgumentList @("class $WMIClass delete") -WindowStyle Hidden -Wait | Out-Null
			}
		}

		if ($InstallType -eq "Nano Server") 
		{
			Start-Process -FilePath ($env:SystemRoot + "\system32\wbem\mofcomp.exe") -ArgumentList @($TempFilePath) -Wait | Out-Null
		}
		else
		{
			Start-Process -FilePath ($env:SystemRoot + "\system32\wbem\mofcomp.exe") -ArgumentList @($TempFilePath) -WindowStyle Hidden -Wait | Out-Null
		}

		$Counter = 0

		while ($Counter -lt 30) 
		{
			try 
			{
				Remove-Item -Path $TempFilePath -ErrorAction Stop -Force | Out-Null
				break
			}
			catch [Exception] 
			{
				$Counter++

				if ($Counter -ge 30) 
				{
					Write-Warning -Message "Timeout waiting to delete the temporary mof file, delete manually."
					break
				}

				Start-Sleep -Seconds 1
			}
		}

        $ScheduledTask = Get-CimClass -ClassName $WMIClass -Namespace "root/cimv2" -ErrorAction SilentlyContinue

        if ($ScheduledTask -ne $null)
        {
            Write-Host "Creating the WMI class was successful." -ForegroundColor Green
        }
        else
        {
            Write-Host "There was an error creating the class." -ForegroundColor Red
        }
    }
	
	End {
	}   
}

[bool]$Local = [System.String]::IsNullOrEmpty($ComputerName) -or `
	$ComputerName -eq "." -or `
	$ComputerName.ToLower() -eq "localhost" -or `
	$ComputerName.ToLower() -eq $ENV:COMPUTERNAME.ToLower() -or `
	$ComputerName -eq "127.0.0.1"

if ($Local -and $Credential -eq [PSCredential]::Empty)
{
	Set-WMIClass -TempFilePath $TempFilePath
}
else 
{
	Invoke-Command -ComputerName $ComputerName -ScriptBlock ${function:Set-WMIClass} -ArgumentList @($TempFilePath) -Credential $Credential
}