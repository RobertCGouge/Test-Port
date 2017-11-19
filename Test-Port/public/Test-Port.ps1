<#
        .Synopsis
        This cmdlet will test a given TCP port till the port is open

        .DESCRIPTION
        This cmdlet will continously test a given TCP port untill the cmdlet is halted or a connection to the given port is established.  This is useful for testing connectivity while configuring firewall rules.  This function also allows for the verbose switch to be used.

        .PARAMETER Computer
        This is the name of the computer you want to test connectivity to

        .PARAMETER IP
        This is the IP address of the computer you want to test connectivity to. Support both IPv4 and IPv6

        .PARAMETER Port
        This is the port on the remote Computer you want to test connectivity to

        .EXAMPLE
        PS C:\> Test-Port -Computer somePC -Port 80

        .EXAMPLE
        PS C:\> Test-Port -IP someIPv4 -Port 80
        
        .EXAMPLE
        PS C:\> Test-Port -IP someIPv6 -Port 80

        .EXAMPLE
        PS C:\> Test-Port -Computer somePC -Port 80 -Verbose

        .EXAMPLE
        PS C:\> Test-Port -IP someIPv4 -Port 80 -Verbose

        .EXAMPLE
        PS C:\> Test-Port -IP someIPv6 -Port 80 -Verbose
        
        .OUTPUTS
        This script has no outputs.

        .LINK
        http://powerworks.readthedocs.io/en/latest/functions/Test-Port

        .LINK
        https://github.com/RobertCGouge/PowerWorks/blob/master/PowerWorks/Public/Test-Port.ps1            
#>
function Test-Port
{
    [CmdletBinding(HelpURI = 'http://powerworks.readthedocs.io/en/latest/functions/Test-Port')]
    [Alias()]
    Param
    (
        [Parameter(Mandatory = $true,
            Position = 0,
            ParameterSetName = 'ComputerName',
            HelpMessage = 'This is the name of the computer you want to test connectivity to')]
        [ValidateScript( {
                if ([bool]($_ -as [ipaddress]))
                {
                    throw "$_ is an IP address, please try again with -IP"
                }
                else
                {
                    if ([bool](Resolve-DnsName -Name asdthasdt))
                    {
                        $true
                    }
                    else
                    {
                        throw "$_ could not be resolved, please try another computer name."
                    }
                }
            })]
        $Computer,
        [Parameter(Mandatory = $true,
            Position = 0,
            ParameterSetName = 'IPAddress',
            HelpMessage = 'This is the IP address of the computer you want to test connectivity to')]
        [ValidateScript( {
                if ([bool]($_ -as [ipaddress]))
                {
                    $true
                }
                else
                {
                    throw "$_ is not a valid IP Address"
                }
            })]
        [ipaddress]
        $IP,
        [Parameter(Mandatory = $true,
            Position = 1,
            ParameterSetName = 'ComputerName',
            HelpMessage = 'This is the port on the remote Computer you want to test connectivity to')]
        [Parameter(Mandatory = $true,
            ParameterSetName = 'IPAddress')]
        [ValidateRange(1, 65535)]
        [int]
        $Port
    )

    Begin
    {
        if ($null -ne $Computer)
        {
            Write-Verbose -Message "Attempting to connect to port: $Port at computer: $Computer"
        }
        if ($null -ne $IP)
        {
            Write-Verbose -Message "Attempting to connect to port: $Port at IP Address: $IP"
        }
    }
    Process
    {
        if ($null -ne $Computer)
        {
            do
            {
                Start-Sleep -Seconds 5
                Write-Verbose -Message "Unable to connect to Port: $Port on Computer: $Computer. `r`n Sleeping for 5 seconds"
            } until (Test-NetConnection -ComputerName $Computer -Port $Port)
            Write-Verbose -Message "Successfuly connected to Port: $Port on Computer: $Computer"
        }
        if ($null -ne $IP)
        {
            do
            {
                Start-Sleep -Seconds 5
                Write-Verbose -Message "Unable to connect to Port: $Port on IP: $IP. `r`n Sleeping for 5 seconds"
            } until (Test-NetConnection -ComputerName $IP -Port $Port)
            Write-Verbose -Message "Successfuly connected to Port: $Port on IP: $IP"
        }
        
    }
    End
    {
    }
}