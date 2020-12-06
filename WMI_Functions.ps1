
# example namespace
$ns = 'testing'

# example wmiclass name
$class = 'MyTesting'

# example object to use as input
$testObj = @()
$testObj += [pscustomobject]@{Name='tuccimon';Position='Engineer';Country='Canada'}
$testObj += [pscustomobject]@{Name='random';Position='Ops';Country='India'}
$testObj += [pscustomobject]@{Name='microsoft';Position='vendor';Country='US'}



function Get-ObjectHash {
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [psobject]$InputObject,
        [string]$Algorithm='SHA256'
    )
    process {

        try {
            Get-FileHash -InputStream ([System.IO.MemoryStream]::New([System.Text.Encoding]::ASCII.GetBytes($InputObject))) -Algorithm $Algorithm | select Algorithm,Hash
        }
        catch {
            $null
        }
    }
}


function Test-WMINamespace {
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]$Namespace
    )
    $exists = Get-WmiObject -Namespace "root\$Namespace" -List -ErrorAction SilentlyContinue
    if ($exists) {
        return $true
    }
    else {
        return $false
    }
}

function Add-WMINamespace {
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]$Namespace,
        [switch]$PassThru=$false
    )

    $thisNamespace = [wmiclass]'root:__Namespace'
    $instance = $thisNamespace.CreateInstance()
    $instance.Name = $Namespace
    $null = $instance.Put()

    if ($PassThru) {
        return $instance
    }
}

function Remove-WMINamespace {
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]$Namespace
    )
    $exists = Get-WmiObject -Query "select * from __Namespace where name='$Namespace'" -Namespace 'root' -ErrorAction SilentlyContinue
    if ($exists) {
        Write-Verbose "Namespace at root\$Namespace found."
        $null = $exists | Remove-WmiObject
    }
    else {
        Write-Warning "Namespace at root\$Namespace not found."
    }
}

function Test-WMIClass {
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]$Namespace,
        [parameter(Mandatory=$true)]
        [string]$ClassName
    )
    $exists = Get-WmiObject -Namespace "root\$Namespace" -Class $ClassName -List -ErrorAction SilentlyContinue
    if ($exists) {
        return $true
    }
    else {
        return $false
    }
}

function Add-WMIClass {
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]$Namespace,
        [parameter(Mandatory=$true)]
        [string]$ClassName,
        [switch]$UseIndexProperty=$true,
        [switch]$PassThru=$false
    )

    $newClass = New-Object System.Management.ManagementClass("root\$Namespace", [string]::Empty, $null)
    $newClass["__CLASS"] = $ClassName
    if ($UseIndexProperty) {
        $null = $newClass.Properties.Add("Index", [System.Management.CimType]::UInt64, $false)
        $null = $newClass.Properties["Index"].Qualifiers.Add("key", $true)
    }
    try {
        $null = $newClass.Put()
        if ($PassThru) {
            return $newClass
        }
    }
    catch {
        $err = $_.Exception.Message
        # exception doesn't return a proper access denied type
        if ($err -like '*access denied*') {
            Write-Error "You require Administrator to create WMI Classes."
        }
        else {
            Write-Error "Error encountered while trying to create WMI Class '$ClassName' in namespace '$Namespace'. Error message is '$err'"
        }
    }
}

function Remove-WMIClass {
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]$Namespace,
        [parameter(Mandatory=$true)]
        [string]$ClassName
    )

    $wmi = Get-WmiObject -Namespace "root\$Namespace" -Class $ClassName -List -ErrorAction SilentlyContinue

    if ($wmi) {
        try {
            $null = $wmi.Delete()
        }
        catch {
            $err = $_.Exception.Message
            # exception doesn't return a proper access denied type
            if ($err -like '*access denied*') {
                Write-Error "You require Administrator to delete WMI Classes."
            }
            else {
                Write-Error "Error encountered while trying to delete WMI Class '$ClassName' in namespace '$Namespace'. Error message is '$err'"
            }
        }
    }
    else {
        Write-Warning "Class name '$ClassName' at root\$Namespace not found."
    }
}


function ExportCustomObject-WMIInstance {
# this function is missing a way of inserting the column into the class as well
    [cmdletbinding()]
    param(
        [pscustomobject]$CustomObject,
        [string]$Namespace,
        [string]$ClassName,
        [switch]$PassThru=$false
    )

    $propertyNames = ($CustomObject | Get-Member | where {$_.MemberType -eq 'NoteProperty'} | select Name).Name

    if ($propertyNames) {

        $objClass = Get-WmiObject -Namespace "root\$Namespace" -Class $ClassName -List -ErrorAction SilentlyContinue
        if ($objClass) {

            foreach ($prop in $propertyNames) {
                # add object properties as "columns" in WMI class
                $null = $objClass.Properties.Add($prop, [System.Management.CimType]::String, $false)
            }

            try {
                $null = $objClass.Put()

                # wmi class created with index column
                $index = 0
                foreach ($item in $CustomObject) {

                    $ht = @{}
                    ++$index
                    $ht['Index'] = $index

                    foreach ($prop in $propertyNames) {
                        $ht[$prop] = Invoke-Expression "`$item.$prop"
                    }
                    $null = Set-WmiInstance -Namespace "root\$Namespace" -Class $ClassName -Arguments $ht
                }

                if ($PassThru) {
                    return (Get-WmiObject -Namespace "root\$Namespace" -Class $ClassName -ErrorAction SilentlyContinue)
                }

            }
            catch {
                $err = $_.Exception.Message
                # exception doesn't return a proper access denied type
                if ($err -like '*access denied*') {
                    Write-Error "You require Administrator to modify WMI Classes."
                }
                else {
                    Write-Error "Error encountered while trying to modify WMI Class '$ClassName' in namespace '$Namespace'. Error message is '$err'"
                }
            }

        }
        else {
            Write-Error "WMI class '$ClassName' not found in name space 'root\$Namespace'."
        }

    }
    else {
        Write-Warning "No property names found in `$CustomObject."
    }
}




# convertto-wmiclass
<# converts an objects (taking in object properties, creating those and then adding each item in object to new wmi class)
this involves the following actions:
- checking to make sure that the namespace exists; -force = creates it
- if so, does the class exist; -force creates it
- create class with properties
- fill class

#>


### testing area

Test-WMINamespace -Namespace $ns -Verbose
Test-WMIClass -Namespace $ns -ClassName $class -Verbose

Remove-WMIClass -Namespace $ns -ClassName $class -Verbose
Remove-WMINamespace -Namespace $ns -Verbose

$newNS = Add-WMINamespace -Namespace $ns -PassThru -Verbose

$newClass = Add-WMIClass -Namespace $ns -ClassName $class -Verbose -PassThru

# class itself
Get-WmiObject -Namespace "root\$ns" -Class $class -List -Verbose


$newObj = ExportCustomObject-WMIInstance -CustomObject $testObj -Namespace $ns -ClassName $class -Verbose -PassThru


# class contents
Get-WmiObject -Namespace "root\$ns" -Class $class -Verbose


$Namespace = $ns
$Classname = $class
$CustomObject = $testObj
$PassThru = $true

