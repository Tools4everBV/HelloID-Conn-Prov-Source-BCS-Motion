Write-Verbose -Verbose "[Departments] Import started"
$config = $configuration | ConvertFrom-Json
$csvDirectory = $config.csvPath
$csvDlimiter = $config.csvDelimiter

$csvDepartmentList = Import-CSV -Path "$csvDirectory\Tools4ever_OrganizationalUnits.csv" -Delimiter $csvDlimiter

#$csvManagerList = Import-CSV -Path "$csvDirectory\Tools4ever_Team_manager.csv" -Delimiter $csvDlimiter

#$managerList = $csvManagerList | Select-Object -Property *,@{Name = "DepartmentExternalId"; Expression = { $_.'Werkgevenr organisatie' + $_.TEAMCODE } },@{Name = "ManagerExternalId"; Expression = { $_.'Werkgevernummer Manager' + "_" + $_.'Personeelsnummer manager' } }| Group-Object DepartmentExternalId -AsHashTable -AsString

$departments = [System.Collections.Generic.List[PscustomObject]]::new() 
Foreach ($csvDepartment  in $csvDepartmentList) {
    
    # Get parent department id
    if ($csvDepartment.HIERARCHIE_CD.EndsWith($csvDepartment.ORGCD + '.')) {
        $parentExternalId = $csvDepartment.HIERARCHIE_CD.replace($csvDepartment.ORGCD + '.','')
    }

    # Get manager department id
    #$managerDepartmentExternalId = $csvDepartment.WERKGEVERNR + $csvDepartment.HIERARCHIE_CD
    #$manager = $managerList[$managerDepartmentExternalId]
    #if ($manager.ManagerExternalId -is [system.array] ) {
    #    $ManagerExternalId = $manager[0].ManagerExternalId
    #    $string = [string]$manager.ManagerExternalId
    #    Write-Verbose -Verbose "[Departments] Multiple managers found for OE $($managerDepartmentExternalId): ($string). Keeping manager $ManagerExternalId."
    #} else {
    #    $ManagerExternalId = $manager.ManagerExternalId
    #}
    
    $department = [PScustomObject]@{
        ExternalId = $csvDepartment.WERKGEVERNR + $csvDepartment.HIERARCHIE_CD
        DisplayName = $csvDepartment.ORGOMS
        Name = $csvDepartment.ORGOMS
        ParentExternalId = $csvDepartment.WERKGEVERNR + $parentExternalId 
        #ManagerExternalId = $ManagerExternalId # $manager.WERKGEVERNR + $manager.MAN_REGISTRATIENR 
    }
    [void]$departments.add($department)
}
$departments = $departments | Sort-Object ExternalId # -Unique

$json = $departments | ConvertTo-Json -Depth 3
Write-Verbose -Verbose "[Departments] Exporting data to HelloID"
write-Output $json
Write-Verbose -Verbose "[Departments] Exported data to HelloID"