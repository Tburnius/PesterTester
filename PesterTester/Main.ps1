

function Import-PSModule {

    param(
        $moduleName,
        $repoUri
    )

    $repo = Get-PSRepository | Where-Object {$_.SourceLocation -eq $repoUri}

    if(-not $repo) {
        try {
            Register-PSRepository -SourceLocation $repoUri -InstallationPolicy Trusted
        } catch {
            Write-Warning "Unable to register PSRepository"
        }
    } else {
        Set-PSRepository -Name $repo.Name -SourceLocation $repo.SourceLocation -InstallationPolicy Trusted
    }

    $module = Get-Module -ListAvailable -Name $moduleName

    if(-not $module) {
        try {
            Install-Module -Name $moduleName
        } catch {
            Write-Warning "Unable to install $($moduleName)"
        }
    } else {
        try {
            Update-Module -Name $moduleName
        } catch {
            Write-Warning "Unable to update $moduleName"
        }
    }

    Import-Module -Name $moduleName -Scope Local
}

Trace-VSTSEnteringInvocation $MyInvocation
try {
    [string] $testPath = Get-VstsInput -name testPath -Require
    [string] $testOutPath = Get-VstsInput -name testOutPath -Require
    [string] $codeCoverage = Get-VstsInput -name codeCoverage 
    [Int] $minimumCoverage = Get-VstsInput -name minimumCoverage -AsInt

    $testPath = $testPath -replace '\s+', ''
    $testOutPath = $testOutPath -replace '\s+', ''
    $codeCoverage = $codeCoverage -replace '\s+', ''


    try{
        Import-PSModule -moduleName "Pester" -repoUri "https://www.powershellgallery.com/api/v2"
    } catch {
        $modulePath = (Resolve-Path "$PSScriptRoot\ps_modules\Pester-Master\Pester.psm1").Path
        Import-Module $modulePath -Force -Scope Local
    }

    if($testOutPath -and $codeCoverage){
        $result = Invoke-Pester -OutputFile $testOutPath -OutputFormat NUnitXml -Script @{ Path="$testPath"} -CodeCoverage $codeCoverage -PassThru
    } elseif ($testOutPath) {
        $result = Invoke-Pester -OutputFile $testOutPath -OutputFormat NUnitXml -Script @{ Path="$testPath"} -PassThru
    } elseif ($codeCoverage) {
        $result = Invoke-Pester -Script @{ Path="$testPath"} -CodeCoverage $codeCoverage -PassThru
    } else {
        $result = Invoke-Pester -Script @{ Path="$testPath"} -PassThru
    }

    if($result.FailedCount -gt 0) {throw "At least one test is failing"}

    if($codeCoverage) {
        if(($result.codeCoverage.NumberOfCommandsExecuted -gt 0) -and ($result.codeCoverage.NumberOfCommandsAnalyzed -gt 0)) {
            if(($($result.codeCoverage.NumberOfCommandsExecuted / $result.codeCoverage.NumberOfCommandsAnalyzed) * 100) -lt $minimumCoverage) {
                throw "Not enough code coverage on unit tests"
            }
        } else {
            Write-Warning "Could Not Analyze Code Coverage"
        }
    }

    Write-Host $result.ExitCode

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}