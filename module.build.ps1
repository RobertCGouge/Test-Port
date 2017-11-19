$script:ModuleName = 'Test-Port'

$script:Source = Join-Path $BuildRoot $ModuleName
$script:Output = Join-Path $BuildRoot output
$script:Destination = Join-Path $Output $ModuleName
$script:ModulePath = "$Destination\$ModuleName.psm1"
$script:ManifestPath = "$Destination\$ModuleName.psd1"
$script:Imports = ( 'private', 'public', 'classes' )
$script:TestFile = "$PSScriptRoot\output\TestResults_PS$PSVersion`_$TimeStamp.xml"
$script:projectRoot = $PSScriptRoot
$script:ReleaseNotes = "$ProjectRoot\RELEASE.md"
$script:ChangeLog = "$ProjectRoot\docs\ChangeLog.md"

Task Default Build, Pester, UpdateSource, Publish
Task Build CopyToOutput, BuildPSM1, BuildPSD1, BuildDocs
Task Pester Build, ImportModule, UnitTests, FullTests

Task Clean {
    Write-Host 'Running Task Clean'
    $null = Remove-Item $Output -Recurse -ErrorAction Ignore
    $null = New-Item  -Type Directory -Path $Destination
}

Task BuildDocs {
    $lines
    
    "Loading Module from $ENV:BHPSModuleManifest"
    Remove-Module $ENV:BHProjectName -Force -ea SilentlyContinue
    # platyPS + AppVeyor requires the module to be loaded in Global scope
    Import-Module $ENV:BHPSModuleManifest -force -Global
    
    #Build YAMLText starting with the header
    $YMLtext = (Get-Content "$ProjectRoot\header-mkdocs.yml") -join "`n"
    $YMLtext = "$YMLtext`n"
    $parameters = @{
        Path        = $ReleaseNotes
        ErrorAction = 'SilentlyContinue'
    }
    $ReleaseText = (Get-Content @parameters) -join "`n"
    if ($ReleaseText)
    {
        $ReleaseText | Set-Content "$ProjectRoot\docs\RELEASE.md"
        $YMLText = "$YMLtext  - Realse Notes: RELEASE.md`n"
    }
    if ((Test-Path -Path $ChangeLog))
    {
        $YMLText = "$YMLtext  - Change Log: ChangeLog.md`n"
    }
    $YMLText = "$YMLtext  - Functions:`n"
    # Drain the swamp
    $parameters = @{
        Recurse     = $true
        Force       = $true
        Path        = "$ProjectRoot\docs\functions"
        ErrorAction = 'SilentlyContinue'
    }
    $null = Remove-Item @parameters
    $Params = @{
        Path        = "$ProjectRoot\docs\functions"
        type        = 'directory'
        ErrorAction = 'SilentlyContinue'
    }
    $null = New-Item @Params
    $Params = @{
        Module       = $ENV:BHProjectName
        Force        = $true
        OutputFolder = "$ProjectRoot\docs\functions"
        NoMetadata   = $true
    }
    New-MarkdownHelp @Params | foreach-object {
        $Function = $_.Name -replace '\.md', ''
        $Part = "    - {0}: functions/{1}" -f $Function, $_.Name
        $YMLText = "{0}{1}`n" -f $YMLText, $Part
        $Part
    }
    $YMLtext | Set-Content -Path "$ProjectRoot\mkdocs.yml"
}

Task UnitTests {
    $TestResults = Invoke-Pester -Path Tests\*unit* -PassThru -Tag Build -ExcludeTag Slow
    if ($TestResults.FailedCount -gt 0)
    {
        Write-Error "Failed [$($TestResults.FailedCount)] Pester tests"
    }
}

Task FullTests {
    $TestResults = Invoke-Pester -Path Tests -PassThru -OutputFormat NUnitXml -OutputFile $testFile -Tag Build
    if ($TestResults.FailedCount -gt 0)
    {
        Write-Error "Failed [$($TestResults.FailedCount)] Pester tests"
    }
}

Task Specification {
    
    $TestResults = Invoke-Gherkin $PSScriptRoot\Spec -PassThru
    if ($TestResults.FailedCount -gt 0)
    {
        Write-Error "[$($TestResults.FailedCount)] specification are incomplete"
    }
}

Task CopyToOutput {

    Write-Output "  Create Directory [$Destination]"
    $null = New-Item -Type Directory -Path $Destination -ErrorAction Ignore

    Get-ChildItem $source -File | 
        where name -NotMatch "$ModuleName\.ps[dm]1" | 
        Copy-Item -Destination $Destination -Force -PassThru | 
        ForEach-Object { "  Create [.{0}]" -f $_.fullname.replace($PSScriptRoot, '')}

    Get-ChildItem $source -Directory | 
        where name -NotIn $imports | 
        Copy-Item -Destination $Destination -Recurse -Force -PassThru | 
        ForEach-Object { "  Create [.{0}]" -f $_.fullname.replace($PSScriptRoot, '')}
}

Task BuildPSM1 -Inputs (Get-Item "$source\*\*.ps1") -Outputs $ModulePath {

    [System.Text.StringBuilder]$stringbuilder = [System.Text.StringBuilder]::new()    
    foreach ($folder in $imports )
    {
        [void]$stringbuilder.AppendLine( "Write-Verbose 'Importing from [$Source\$folder]'" )
        if (Test-Path "$source\$folder")
        {
            $fileList = Get-ChildItem "$source\$folder\*.ps1" | Where Name -NotLike '*.Tests.ps1'
            foreach ($file in $fileList)
            {
                $shortName = $file.fullname.replace($PSScriptRoot, '')
                Write-Output "  Importing [.$shortName]"
                [void]$stringbuilder.AppendLine( "# .$shortName" ) 
                [void]$stringbuilder.AppendLine( [System.IO.File]::ReadAllText($file.fullname) )
            }
        }
    }
    
    Write-Output "  Creating module [$ModulePath]"
    Set-Content -Path  $ModulePath -Value $stringbuilder.ToString() 
}

Task NextPSGalleryVersion -if (-Not ( Test-Path "$output\version.xml" ) ) -Before BuildPSD1 {
    $galleryVersion = Get-NextPSGalleryVersion -Name $ModuleName
    $galleryVersion | Export-Clixml -Path "$output\version.xml"
}

Task BuildPSD1 -inputs (Get-ChildItem $Source -Recurse -File) -Outputs $ManifestPath {
    
    Write-Output "  Update [$ManifestPath]"
    Copy-Item "$source\$ModuleName.psd1" -Destination $ManifestPath
 
 
    $functions = Get-ChildItem "$ModuleName\Public\*.ps1" | Where-Object { $_.name -notmatch 'Tests'} | Select-Object -ExpandProperty basename      
    Set-ModuleFunctions -Name $ManifestPath -FunctionsToExport $functions
 
    Write-Output "  Detecting semantic versioning"
 
    Import-Module ".\$ModuleName"
    $commandList = Get-Command -Module $ModuleName
    Remove-Module $ModuleName
 
    Write-Output "    Calculating fingerprint"
    $fingerprint = foreach ($command in $commandList )
    {
        foreach ($parameter in $command.parameters.keys)
        {
            '{0}:{1}' -f $command.name, $command.parameters[$parameter].Name
            $command.parameters[$parameter].aliases | Foreach-Object { '{0}:{1}' -f $command.name, $_}
        }
    }
     
    if (Test-Path .\fingerprint)
    {
        $oldFingerprint = Get-Content .\fingerprint
    }
     
    $bumpVersionType = 'Patch'
    '    Detecting new features'
    $fingerprint | Where {$_ -notin $oldFingerprint } | % {$bumpVersionType = 'Minor'; "      $_"}    
    '    Detecting breaking changes'
    $oldFingerprint | Where {$_ -notin $fingerprint } | % {$bumpVersionType = 'Major'; "      $_"}
 
    Set-Content -Path .\fingerprint -Value $fingerprint
 
    # Bump the module version
    $version = [version] (Get-Metadata -Path $manifestPath -PropertyName 'ModuleVersion')

    if ( $version -lt ([version]'1.0.0') )
    {
        '    Still in beta, don''t bump major version'
        if ( $bumpVersionType -eq 'Major'  )
        {
            $bumpVersionType = 'Minor'
        }
        else 
        {
            $bumpVersionType = 'Patch'
        }       
    }

    $galleryVersion = Import-Clixml -Path "$output\version.xml"
    if ( $version -lt $galleryVersion )
    {
        $version = $galleryVersion
    }
    Write-Output "  Stepping [$bumpVersionType] version [$version]"
    $version = [version] (Step-Version $version -Type $bumpVersionType)
    Write-Output "  Using version: $version"
     
    Update-Metadata -Path $ManifestPath -PropertyName ModuleVersion -Value $version
} 

Task UpdateSource {
    Copy-Item $ManifestPath -Destination "$source\$ModuleName.psd1"
}

Task ImportModule {
    if ( -Not ( Test-Path $ManifestPath ) )
    {
        Write-Output "  Modue [$ModuleName] is not built, cannot find [$ManifestPath]"
        Write-Error "Could not find module manifest [$ManifestPath]. You may need to build the module first"
    }
    else
    {
        if (Get-Module $ModuleName)
        {
            Write-Output "  Unloading Module [$ModuleName] from previous import"
            Remove-Module $ModuleName
        }
        Write-Output "  Importing Module [$ModuleName] from [$ManifestPath]"
        Import-Module $ManifestPath -Force
    }
}

Task Publish {
    # Gate deployment
    if (
        $ENV:BHBuildSystem -ne 'Unknown' -and 
        $ENV:BHBranchName -eq "master" -and 
        $ENV:BHCommitMessage -match '!deploy'
    )
    {
        $Params = @{
            Path  = $BuildRoot
            Force = $true
        }

        Invoke-PSDeploy @Verbose @Params
    }
    else
    {
        "Skipping deployment: To deploy, ensure that...`n" + 
        "`t* You are in a known build system (Current: $ENV:BHBuildSystem)`n" + 
        "`t* You are committing to the master branch (Current: $ENV:BHBranchName) `n" + 
        "`t* Your commit message includes !deploy (Current: $ENV:BHCommitMessage)"
    }
}
Task PostDeploy -Depends Publish {
    $lines
    if ($ENV:APPVEYOR_REPO_PROVIDER -notlike 'github')
    {
        "Repo provider '$ENV:APPVEYOR_REPO_PROVIDER'. Skipping PostDeploy"
        return
    }
    If ($ENV:BHBuildSystem -eq 'AppVeyor')
    {
        "git config --global credential.helper store"
        cmd /c "git config --global credential.helper store 2>&1"
            
        Add-Content "$env:USERPROFILE\.git-credentials" "https://$($env:access_token):x-oauth-basic@github.com`n"
            
        "git config --global user.email"
        cmd /c "git config --global user.email ""$($ENV:BHProjectName)-$($ENV:BHBranchName)-$($ENV:BHBuildSystem)@markekraus.com"" 2>&1"
            
        "git config --global user.name"
        cmd /c "git config --global user.name ""AppVeyor"" 2>&1"
            
        "git config --global core.autocrlf true"
        cmd /c "git config --global core.autocrlf true 2>&1"
    }
        
    "git checkout $ENV:BHBranchName"
    cmd /c "git checkout $ENV:BHBranchName 2>&1"
        
    "git add -A"
    cmd /c "git add -A 2>&1"
        
    "git commit -m"
    cmd /c "git commit -m ""AppVeyor post-build commit[ci skip]"" 2>&1"
        
    "git status"
    cmd /c "git status 2>&1"
        
    "git push origin $ENV:BHBranchName"
    cmd /c "git push origin $ENV:BHBranchName 2>&1"
    # if this is a deploy on master, create GitHub release
    if (
        $ENV:BHBuildSystem -ne 'Unknown' -and
        $ENV:BHBranchName -eq "master" -and
        $ENV:BHCommitMessage -match 'deploy'
    )
    {
        "Publishing Release 'v$BuildVersion' to Github"
        $parameters = @{
            Path        = $ReleaseNotes
            ErrorAction = 'SilentlyContinue'
        }
        $ReleaseText = (Get-Content @parameters) -join "`r`n"
        if (-not $ReleaseText)
        {
            $ReleaseText = "Release version $BuildVersion ($BuildDate)"
        }
        $Body = @{
            "tag_name"         = "v$BuildVersion"
            "target_commitish" = "master"
            "name"             = "v$BuildVersion"
            "body"             = $ReleaseText
            "draft"            = $false
            "prerelease"       = $false
        } | ConvertTo-Json
        $releaseParams = @{
            Uri         = "https://api.github.com/repos/{0}/releases" -f $ENV:APPVEYOR_REPO_NAME
            Method      = 'POST'
            Headers     = @{
                Authorization = 'Basic ' + [Convert]::ToBase64String(
                    [Text.Encoding]::ASCII.GetBytes($env:access_token + ":x-oauth-basic"));
            }
            ContentType = 'application/json'
            Body        = $Body
        }
        $Response = Invoke-RestMethod @releaseParams
        $Response | Format-List *
    }
}
