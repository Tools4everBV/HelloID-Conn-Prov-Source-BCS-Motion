Write-Verbose -Verbose "[Persons] import started"

$config = $configuration | ConvertFrom-Json
    
# Load CSV files
$csvDirectory = $config.csvPath
$csvDelimiter = $config.csvDelimiter

$persons = Import-CSV -Path "$csvDirectory\Tools4ever_Persons.csv" -Delimiter $csvDelimiter

$csvContracts = Import-CSV -Path "$csvDirectory\Tools4ever_Contracts.csv"  -Delimiter $csvDelimiter
$contracts = $csvContracts | Select-Object -Property *,@{Name = "functionExternalId"; Expression = { $_.WERKGEVERNR + "_" + $_.FUNCTIECODE } }
$contracts = $contracts | Sort-Object REGISTRATIENR

$csvFunctions = Import-CSV -Path "$csvDirectory\Tools4ever_Functions.csv"  -Delimiter $csvDelimiter 
$functionList = $csvFunctions | Select-Object -Property *,@{Name = "externalId"; Expression = { $_.WERKGEVERNR + "_" + $_.FUNCTIECODE } } | Group-Object externalId -AsHashTable -AsString

$csvOrganizations = Import-CSV -Path "$csvDirectory\Tools4ever_Organizations.csv"  -Delimiter $csvDelimiter | Group-Object WERKGEVERNR -AsHashTable

$csvManagers = Import-CSV -Path "$csvDirectory\Tools4ever_Managers1.csv" -Delimiter $csvDelimiter
$managerList = $csvManagers | Select-Object -Property *,@{Name = "employeeExternalId"; Expression = { $_.WERKGEVERNR + "_" + $_.MED_REGISTRATIENR } }, @{Name = "managerExternalId"; Expression = { $_.WERKGEVERNR + "_" + $_.MAN_REGISTRATIENR } } | Group-Object employeeExternalId -AsHashTable -AsString

# add contracts, externalId and displayName properties to persons
$persons | Add-Member -MemberType NoteProperty -Name "Contracts" -Value $null -Force
$persons | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
$persons | Add-Member -MemberType NoteProperty -Name "DisplayName" -Value $null -Force

# add function and organization description to contracts
$contracts | Add-Member -MemberType NoteProperty -Name "FunctionName" -Value $null -Force
$contracts | Add-Member -MemberType NoteProperty -Name "OrganizationName" -Value $null -Force
$contracts | Add-Member -MemberType NoteProperty -Name "ManagerExternalId" -Value $null -Force

# Enrich contracts with function and organization data
$contracts | ForEach-Object {

    # Function
    $personFunction = $functionList[$_.functionExternalId]
    if ($personFunction.count -eq 1) {
        $_.FunctionName = $personFunction.FUNCTIENM
    }

    # Organization
    $personOrganization = $csvOrganizations[$_.WERKGEVERNR]
    if ($personOrganization.count -eq 1) {
        $_.OrganizationName = $personOrganization.WERKGEVERNM
    }

    # Manager

    $personManager = $managerList[$_.REGISTRATIENR]
       
    if ($personManager.ManagerExternalId -is [system.array] ) {
        $_.ManagerExternalId = $personManager[0].ManagerExternalId
        $string = [string]$personManager.ManagerExternalId
        if ($currentUID -ne $_.REGISTRATIENR) {
            Write-Verbose -Verbose "Multiple managers found for person $($_.REGISTRATIENR): ($string). Keeping manager $($_.ManagerExternalId)"
        }
    } else {
        $_.ManagerExternalId = $personManager.ManagerExternalId
    }
    $currentUID = $_.REGISTRATIENR
}

# group contracts on REGISTRATIENR
$contracts = $contracts | Group-Object -Property REGISTRATIENR -AsHashTable

# Add the enriched contracts to the person records
$persons | ForEach-Object {
    $_.ExternalId = $_.REGISTRATIENR
    $_.DisplayName = $_.ROEPNM  + " " + $_.NAAMGEBRUIKVOORVOEGSEL  + " " + $_.NAAMGEBRUIKPERSOONNM  +" (" + $_.WERKGEVERNR + "_" + $_.REGISTRATIENR + ")"
    	
    $personContracts = $contracts[$_.REGISTRATIENR]
    if ($null -ne $personContracts) {
        $_.Contracts = $personContracts
    }
}

if($config.ExcludePersonsWithoutContract)
{
    $persons = $persons | Where-Object -Property Contracts -ne $null
}

# Make sure persons are unique
$persons = $persons | Sort-Object ExternalId -Unique

Write-Verbose -Verbose "[Persons] Import completed"

Write-Verbose -Verbose "[Persons] Exporting data to HelloID"

# Output the json
foreach ($person in $persons) {
    $json = $person | ConvertTo-Json -Depth 3
    Write-Output $json
}

Write-Verbose -Verbose "[Persons] Exported data to HelloID"