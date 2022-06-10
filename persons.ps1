Write-Verbose -Verbose "[Persons] import started"

$config = $configuration | ConvertFrom-Json
    
# Load CSV files
$csvDirectory = $config.csvPath
$csvDelimiter = $config.csvDelimiter

$persons = Import-CSV -Path "$csvDirectory\Tools4ever_Persons.csv" -Delimiter $csvDelimiter

$csvContracts = Import-CSV -Path "$csvDirectory\Tools4ever_Contracts.csv"  -Delimiter $csvDelimiter
$contracts = $csvContracts | Select-Object -Property *,@{Name = "functionExternalId"; Expression = { $_.WERKGEVERNR + "_" + $_.FUNCTIECODE } }
$contracts = $contracts | Sort-Object UID

$csvFunctions = Import-CSV -Path "$csvDirectory\Tools4ever_Functions.csv"  -Delimiter $csvDelimiter 
$functionList = $csvFunctions | Select-Object -Property *,@{Name = "externalId"; Expression = { $_.WERKGEVERNR + "_" + $_.FUNCTIECODE } } | Group-Object externalId -AsHashTable -AsString

$csvOrganizations = Import-CSV -Path "$csvDirectory\Tools4ever_Organizations.csv"  -Delimiter $csvDelimiter | Group-Object WERKGEVERNR -AsHashTable

#GJT(Kersten) -  Laag 2 en lager in motion OU ophalen tbv
$csvBusinessUnits = Import-CSV -Path "$csvDirectory\Tools4ever_OrganizationalUnits.csv"  -Delimiter $csvDelimiter
$businessUnitList = $csvBusinessUnits | Select-object -Property "HIERARCHIE_CD", "ORGOMS" | Where-Object { $_.HIERARCHIE_CD.length -le 11} | Sort-Object HIERARCHIE_CD -Unique | Group-Object HIERARCHIE_CD -AsHashTable -AsString

$csvManagers = Import-CSV -Path "$csvDirectory\Tools4ever_Manager1.csv" -Delimiter $csvDelimiter
#@GJT(Kersten) tijdelijk door ontbreken MAN_WERKGEVERNR deze onttrokken met $_.UID_MAN.Substring(0,5)
$managerList = $csvManagers | Select-Object -Property *,@{Name = "employeeExternalId"; Expression = { $_.MED_WERKGEVERNR + "_" + $_.MED_REGISTRATIENR } }, @{Name = "managerExternalId"; Expression = { $_.UID_MAN.Substring(0,5) + "_" + $_.MAN_REGISTRATIENR } } | Group-Object employeeExternalId -AsHashTable -AsString
#$managerList = $csvManagers | Group-Object employeeExternalId -AsHashTable -AsString

# add contracts, externalId and displayName properties to persons
$persons | Add-Member -MemberType NoteProperty -Name "Contracts" -Value $null -Force
$persons | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
$persons | Add-Member -MemberType NoteProperty -Name "DisplayName" -Value $null -Force

# add function and organization description to contracts (And Business Unit)
$contracts | Add-Member -MemberType NoteProperty -Name "FunctionName" -Value $null -Force
$contracts | Add-Member -MemberType NoteProperty -Name "OrganizationName" -Value $null -Force
$contracts | Add-Member -MemberType NoteProperty -Name "ManagerExternalId" -Value $null -Force

#GJT - add businessunit fields to contracts
$contracts | Add-Member -MemberType NoteProperty -Name "BusinessUnitName" -Value $null -Force
$contracts | Add-Member -MemberType NoteProperty -Name "BusinessUnitExternalId" -Value $null -Force

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

    $personManager = $managerList[$_.UID]
       
    if ($personManager.ManagerExternalId -is [system.array] ) {
        # RJ - Todo? - Wellicht sort toevoegen?
        $_.ManagerExternalId = $personManager[0].ManagerExternalId
        $string = [string]$personManager.ManagerExternalId
        if ($currentUID -ne $_.UID) {
            # RJ - Todo? - Deze check buiten de loop plaatsen, wordt nu voor elk contract een foutmelding gegeven
            Write-Verbose -Verbose "Multiple managers found for person $($_.UID): ($string). Keeping manager $($_.ManagerExternalId)"
        }
    } else {
        $_.ManagerExternalId = $personManager.ManagerExternalId
    }
    $currentUID = $_.UID
    
    #GJT - BusinessUnit (Laag 2 van OU's in Motion)
    if ($_.HIERARCHIE_CD.length -ge 11) {
        $personBusinessUnit = $businessUnitList[$_.HIERARCHIE_CD.substring(0,11)]
        if ($personBusinessUnit.count -eq 1) {
            $_.BusinessUnitName = $personBusinessUnit.ORGOMS
            $_.BusinessUnitExternalId  = $_.HIERARCHIE_CD.substring(0,11)
        }
    } else {
        #GJT - If niet gevonden in Laag2 (directie bv) dan laag 1
        $personBusinessUnit = $businessUnitList[$_.HIERARCHIE_CD.substring(0,6)]
        if ($personBusinessUnit.count -eq 1) {
            $_.BusinessUnitName = $personBusinessUnit.ORGOMS
            $_.BusinessUnitExternalId  = $_.HIERARCHIE_CD.substring(0,6)
        }
    }
}

# group contracts on UID
$contracts = $contracts | Group-Object -Property UID -AsHashTable
#write-verbose -verbose ($microsoftLicencesList | ConvertTo-Json)
# Add the enriched contracts to the person records
$persons | ForEach-Object {
    $_.ExternalId = $_.UID
    $_.DisplayName = $_.ROEPNM  + " " + $_.NAAMGEBRUIKVOORVOEGSEL  + " " + $_.NAAMGEBRUIKPERSOONNM  +" (" + $_.WERKGEVERNR + "_" + $_.REGISTRATIENR + ")"
    	
    $personContracts = $contracts[$_.UID]
    if ($null -ne $personContracts) {
        $_.Contracts = $personContracts
    }
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