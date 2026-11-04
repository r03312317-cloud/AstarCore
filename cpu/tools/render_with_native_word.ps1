param([Parameter(Mandatory=$true)][string]$DocumentPath,[Parameter(Mandatory=$true)][string]$PdfPath)
$ErrorActionPreference='Stop'
$fullDocumentPath=[IO.Path]::GetFullPath($DocumentPath)
$fullPdfPath=[IO.Path]::GetFullPath($PdfPath)
if(-not (Test-Path -LiteralPath $fullDocumentPath)){throw 'Input document missing'}
New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($fullPdfPath)) -Force | Out-Null
$existingWordPids=@(Get-Process WINWORD -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$reportWord=New-Object -ComObject Word.Application
$newWordPids=@(Get-Process WINWORD -ErrorAction SilentlyContinue | Where-Object { $existingWordPids -notcontains $_.Id } | Select-Object -ExpandProperty Id)
if($newWordPids.Count -ne 1){[Runtime.InteropServices.Marshal]::FinalReleaseComObject($reportWord) | Out-Null;throw 'Cannot uniquely identify a new isolated Word process'}
$reportWordProcessId=$newWordPids[0]
Write-Output "Native report renderer Word PID $reportWordProcessId"
$reportWord.Visible=$false
$reportWord.DisplayAlerts=0
$reportWord.AutomationSecurity=3
$reportDocument=$null
try {
 $reportDocument=$reportWord.Documents.Open($fullDocumentPath,$false,$true,$false)
 $reportDocument.Repaginate()
 $pageCount=$reportDocument.ComputeStatistics(2)
 $reportDocument.ExportAsFixedFormat($fullPdfPath,17)
 Write-Output "Pages $pageCount"
 Write-Output "PDF $fullPdfPath"
} finally {
 if($null -ne $reportDocument){$reportDocument.Close($false);[Runtime.InteropServices.Marshal]::FinalReleaseComObject($reportDocument) | Out-Null}
 $reportWord.Quit($false)
 [Runtime.InteropServices.Marshal]::FinalReleaseComObject($reportWord) | Out-Null
}
