
# WMI Functions

function Create-FOOBARWMINamespace {
    [CmdletBinding()]
    param(
        $NamespaceName = 'FOOBAR'
    )

    $namespace = [wmiclass]'root:__Namespace'
    $instance = $namespace.CreateInstance()
    $instance.Name = $NamespaceName
    $instance.Put()

}


function Delete-FOOBARWMINamespace {
    [CmdletBinding()]
    param(
        $NamespacePath = 'root',
        $NamespaceName = 'FOOBAR'
    )
    Get-WmiObject "select * from __Namespace where name='$NamespaceName'" -Namespace $NamespacePath | Remove-WmiObject
}


function Create-FOOBARWmiClass {
    [CmdletBinding()]
    param(
        $ClassName = 'FOOBAR_People'
    )

    $newClass = New-Object System.Management.ManagementClass("root\FOOBAR", [string]::Empty, $null)
    $newClass["__CLASS"] = $ClassName
    $newClass.Properties.Add("Index", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties["Index"].Qualifiers.Add("key", $true)
    $newClass.Properties.Add("Name", [System.Management.CimType]::String, $false)
    $newClass.Properties.Add("Age", [System.Management.CimType]::UInt32, $false)
    $newClass.Properties.Add("Married", [System.Management.CimType]::Boolean, $false)
    $newClass.Put()

}

function Delete-FOOBARWMIClass {
    [CmdletBinding()]
    param(
        $ClassName = 'FOOBAR_People'
    )

    $wmi = Get-WmiObject -Namespace root\FOOBAR -Class $ClassName -List
    $wmi.Delete()

}


function Insert-IndexColumn {
    [CmdletBinding()]
    param(
        $InputObject,
        [string]$IndexColumnName='Index',
        [int]$StartNumber=1
    )
    $returnObject = $InputObject | select @{n=$IndexColumnName;e={0}}, *
    $ctr = $StartNumber
    foreach ($item in $returnObject) {
        Invoke-Expression "`$item.$IndexColumnName = $ctr"
        ++$ctr
    }
    return $returnObject
}    


function ExportCustomObject-WMIInstance {
   [CmdletBinding()]
    param(
        $CustomObject,
        [string]$NameSpaceName,
        [string]$ClassName
    )

    $propertyNames = ($CustomObject | Get-Member | where {$_.MemberType -eq 'NoteProperty'} | select Name).Name

    foreach ($item in $CustomObject) {
        $ht = @{}
        foreach ($prop in $propertyNames) {
            $ht[$prop] = Invoke-Expression "`$item.$prop"
        }
        Set-WmiInstance -Namespace $NameSpaceName -Class $ClassName -Arguments $ht
    }

}


#############################################################################################################

Create-FOOBARWMINamespace -ErrorAction Stop

$doesWMINameExist = $null
$doesWMINameExist = Get-WmiObject -Namespace root\FOOBAR -List -ErrorAction SilentlyContinue | where {$_.Name -eq 'FOOBAR_People'}
if (!($doesWMINameExist)) {
    Create-FOOBARWmiClass -ErrorAction Stop
}

# remove instances under class
Get-WmiObject -Namespace root\FOOBAR -Class FOOBAR_People | Remove-WmiObject -ErrorAction Stop

# creating a custom test object to be used for importing
$testobject = @()
$props = @{
    Name = 'Johnny';
    Age = 5;
    Married=$false;
}
$testobject += New-Object -TypeName psobject -Property $props
$props = @{
    Name = 'George';
    Age = 50;
    Married=$true;
}
$testobject += New-Object -TypeName psobject -Property $props
$props = @{
    Name = 'Mary';
    Age = 15;
    Married=$false;
}
$testobject += New-Object -TypeName psobject -Property $props
$props = @{
    Name = 'Anne';
    Age = 40;
    Married=$true;
}
$testobject += New-Object -TypeName psobject -Property $props

# so basically collect all your data into an object and then dump it to WMI
ExportCustomObject-WMIInstance -NameSpaceName $ns -ClassName $cl -CustomObject (Insert-IndexColumn -InputObject $testobject)

<#
Delete-FOOBARWMIClass
Delete-FOOBARWMINamespace
#>
