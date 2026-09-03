[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Path
)

$ErrorActionPreference = 'Stop'
$Failed = $false

foreach ($Candidate in $Path) {
    $Resolved = (Resolve-Path -LiteralPath $Candidate).Path
    $Tokens = $null
    $ParseErrors = $null

    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $Resolved,
        [ref] $Tokens,
        [ref] $ParseErrors
    )

    if ($ParseErrors.Count -eq 0) {
        Write-Host "[PASS] PowerShell parser: $Candidate"
        continue
    }

    $Failed = $true
    foreach ($ParseError in $ParseErrors) {
        $Line = $ParseError.Extent.StartLineNumber
        $Column = $ParseError.Extent.StartColumnNumber
        [Console]::Error.WriteLine(
            "[FAIL] PowerShell parser: {0}:{1}:{2}: {3}",
            $Candidate,
            $Line,
            $Column,
            $ParseError.Message
        )

        $SourceLine = Get-Content -LiteralPath $Resolved | Select-Object -Index ($Line - 1)
        if ($null -ne $SourceLine) {
            [Console]::Error.WriteLine("       {0}", $SourceLine)
            if ($Column -gt 0) {
                [Console]::Error.WriteLine("       {0}^", (' ' * ($Column - 1)))
            }
        }
    }
}

if ($Failed) {
    exit 1
}
