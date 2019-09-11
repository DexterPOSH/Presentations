# using Azure Network watcher to generate resource associations
# which will be used to build the Azure Network topolgy
$networkWatcher = Get-AzNetworkWatcher -Name NetworkWatcher_centralindia -ResourceGroup NetworkWatcherRG 
$ResourceGroups = Get-AzResourceGroup | 
Where-Object { $_.ResourceGroupName -in 'DEMO-RESOURCE-GROUP'} |
# Where-Object { $_.ResourceGroupName -in 'my-resource-group','DEMO-RESOURCE-GROUP', 'test-resource-group', 'DEMO2-RESOURCE-GROUP'  } |
ForEach-Object ResourceGroupName  
   
#region defaults
$rank = @{
    publicIPAddresses     = 0
    loadBalancers         = 1
    virtualNetworks       = 2 
    networkSecurityGroups = 3
    networkInterfaces     = 4
    virtualMachines       = 5
}

$UniqueIdentifier = 0
$Tier = 0

$Shapes = @{
    loadBalancers                            = 'diamond'
    publicIPAddresses                        = 'octagon'
    networkInterfaces                        = 'component'
    virtualMachines                          = 'box3d'
    'loadBalancers/backendAddressPools'      = 'rect'
    'loadBalancers/frontendIPConfigurations' = 'rect'
    'virtualNetworks'                        = 'oval'
    'networkSecurityGroups'                  = 'oval'
}

$Style = @{
    loadBalancers                            = 'filled'
    publicIPAddresses                        = 'filled'
    networkInterfaces                        = 'filled'
    virtualMachines                          = 'filled'
    'loadBalancers/backendAddressPools'      = 'filled'
    'loadBalancers/frontendIPConfigurations' = 'filled'
    'virtualNetworks'                        = 'dotted'
    'networkSecurityGroups'                  = 'filled'
}

$Color = @{
    loadBalancers                            = 'greenyellow'
    publicIPAddresses                        = 'gold'
    networkInterfaces                        = 'skyblue'
    'loadBalancers/frontendIPConfigurations' = 'lightsalmon'
    virtualMachines                          = 'darkolivegreen3'
    'loadBalancers/backendAddressPools'      = 'crimson'
    'virtualNetworks'                        = 'navy'
    'networkSecurityGroups'                  = 'azure'
}
#endregion defaults

#region graph-generation
Write-Host "[+] Starting topology graph generation`n`t- Target Resource Groups: [$ResourceGroups]`n`t- Network Watcher: [$($networkWatcher.Name)]" -ForegroundColor DarkCyan
Graph 'AzureTopology' @{overlap = 'false'; splines = 'true' ;rankdir='TB'} {
    foreach ($ResourceGroup in $ResourceGroups) {
        Write-Host "`t[+] Working on `"Graph$UniqueIdentifier`" for ResourceGroup: `"$ResourceGroup`"" -ForegroundColor Yellow
        SubGraph "$($ResourceGroup.Replace('-', ''))" @{label = $ResourceGroup; labelloc = 'b' } {
            Write-Host "`t`t[+] Fetching Network topology of ResourceGroup: `"$ResourceGroup`"" -ForegroundColor Green
            $Topology = Get-AzNetworkWatcherTopology -NetworkWatcher $networkWatcher -TargetResourceGroupName $ResourceGroup -Verbose
            
            #region parsing-topology-and-finding-associations

            # parse topology to find nodes and their associations and rank them.
            Write-Host "`t`t[+] Parsing Network topology objects to find associations" -ForegroundColor Green
            $data = @()
            $data += $Topology.Resources | 
            Select-Object @{n = 'from'; e = { $_.name } }, 
            @{n = 'FromCategory'; e = { $_.id.Split('/', 8)[-1] } },
            Associations, 
            @{n = 'To'; e = { ($_.AssociationText | ConvertFrom-Json) | Select-Object name, AssociationType, resourceID } } |
            ForEach-Object {
                if ($_.to) {
                    Foreach ($to in $_.to) {
                        $i = 1
                        $fromcateg = $_.FromCategory.split('/', 4).ForEach( { if ($i % 2) { $_ }; $i = $i + 1 }) -join '/'
                        [PSCustomObject]@{
                            fromcateg   = $fromCateg
                            from        = $_.from
                            to          = $to.name
                            association = $to.associationType
                            toCateg     = (($to.resourceID -split 'providers/')[1] -split '/')[1]
                            rank        = $rank["$($FromCateg.split('/')[0])"]
                        }
                    }
                }
                else {
                    $i = 1
                    $fromcateg = $_.FromCategory.split('/', 4).ForEach( { if ($i % 2) { $_ }; $i = $i + 1 }) -join '/'
                    [PSCustomObject]@{
                        fromcateg   = $fromCateg
                        from        = $_.from
                        to          = ''
                        association = ''
                        toCateg     = ''
                        rank        = $rank["$($FromCateg.split('/')[0])"]
                    }
                }
            } | 
            Sort-Object Rank
            #endregion parsing-topology-and-finding-associations
            
            #region plotting-edges-to-nodes
            $data | 
            Where-Object to | 
            ForEach-Object {
                if ($_.Association -eq 'Contains') {
                    Edge -From "$UniqueIdentifier$($_.from)" `
                         -to "$UniqueIdentifier$($_.to)" `
                         -Attributes @{
                             arrowhead = 'box';
                             style = 'dotted';
                             label = 'Contains'
                            }
                }
                else {
                    Edge -From "$UniqueIdentifier$($_.from)" `
                         -to "$UniqueIdentifier$($_.to)" 
                }
            }
            #endregion plotting-edges-to-nodes

            #region plotting-all-publicIP-nodes
            $pubip = @()
            $pubip += $data | 
                        Where-Object { 
                            $_.fromcateg -like 'publicIPAddresses'
                        } | 
            Select-Object *, @{n = 'Category'; e = { 'fromcateg' } }

            if ($pubip) {
                $pubip | ForEach-Object {
                    if ($_.Category -eq 'fromcateg') {
                        $from = $_.from
                        node "$UniqueIdentifier$from" -Attributes @{
                            Label = "$from";
                            shape = "$($Shapes[$($_.fromcateg)])";
                            style = "$($style[$($_.fromcateg)])" ;
                            fillcolor = "$($color[$($_.fromcateg)])"
                        }
                    }
                    else {
                        $to = $_.to
                        node "$UniqueIdentifier$to" -Attributes @{
                            Label = "$to";
                            shape = "$($Shapes[$($_.tocateg)])";
                            style = "$($style[$($_.tocateg)])" ;
                            fillcolor = "$($color[$($_.tocateg)])"
                        }
                    }
                }
            }
            #endregion plotting-all-publicIP-nodes
            
            #region plotting-all-loadbalancer-nodes
            $lb = @()
            $lb += $data | 
                Where-Object { $_.fromcateg -like 'loadbalancers' } |
                Select-Object *, @{n = 'Category'; e = { 'fromcateg' } }
            $lb += $data | 
                Where-Object { $_.tocateg -like 'loadbalancers' } |
                Select-Object *, @{n = 'Category'; e = { 'tocateg' } }
            if ($lb) {
                $tier++
                SubGraph "${UniqueIdentifier}loadbalancer" @{
                    style = 'dashed';
                    label = "tier-$Tier";
                    labelloc = 'tl' 
                } {
                    $lb | ForEach-Object {
                        if ($_.Category -eq 'fromcateg') {
                            $from = $_.from
                            node "$UniqueIdentifier$from" `
                                -Attributes @{
                                    Label = "$from";
                                    shape = "$($Shapes[$($_.fromcateg)])";
                                    style = "$($style[$($_.fromcateg)])";
                                    fillcolor = "$($color[$($_.fromcateg)])"
                                }
                        }
                        else {
                            $to = $_.to
                            node "$UniqueIdentifier$to" `
                                -Attributes @{
                                    Label = "$to"; 
                                    shape = "$($Shapes[$($_.tocateg)])";
                                    style = "$($style[$($_.tocateg)])" ;
                                    fillcolor = "$($color[$($_.tocateg)])"
                                }
                        }
                    }
                }
            }
            #endregion plotting-all-loadbalancer-nodes

            #region plotting-all-VM-nodes
            $vm = @()
            $ShouldMatch = 'networkInterfaces', 'virtualMachines'
            $vm += $data | 
                Where-Object { $_.fromcateg -in $ShouldMatch } |
                Select-Object *, @{n = 'Category'; e = { 'fromcateg' } }

            if ($vm) {
                $tier++
                SubGraph "${UniqueIdentifier}virtualmachine" @{style = 'dashed'; label = "tier-$Tier"; labelloc = 'tl' } {
                    $vm | ForEach-Object {
                        if ($_.Category -eq 'fromcateg') {
                            $from = $_.from
                            # Write-host "From:$from , FromCateg:$($_.fromcateg)" -ForegroundColor Yellow
                            node "$UniqueIdentifier$from" -Attributes @{Label = "$from"; shape = "$($Shapes[$($_.fromcateg)])"; style = "$($style[$($_.fromcateg)])" ; fillcolor = "$($color[$($_.fromcateg)])" }
                        }
                        else {
                            $to = $_.to
                            # Write-host "to:$to , toCateg:$($_.tocateg)" -ForegroundColor Yellow
                            node "$UniqueIdentifier$to" -Attributes @{Label = "$to"; shape = "$($Shapes[$($_.tocateg)])"; style = "$($style[$($_.tocateg)])" ; fillcolor = "$($color[$($_.tocateg)])" }
                        }
                    }
                }
            }
            #endregion plotting-all-VM-nodes

            #region plotting-all-remaining-nodes
            $remaining = @()
            $ShouldMatch = 'publicIPAddresses', 'loadBalancers', 'networkInterfaces', 'virtualMachines'
            $remaining += $data | Where-Object { $_.fromcateg -notin $ShouldMatch } |
            Select-Object *, @{n = 'Category'; e = { 'fromcateg' } }
            $remaining += $data | Where-Object { $_.tocateg -notin $ShouldMatch } |
            Select-Object *, @{n = 'Category'; e = { 'tocateg' } }
 
            if ($remaining) {
                $remaining | ForEach-Object {
                    if ($_.Category -eq 'fromcateg') {
                        $from = $_.from
                        # Write-host "From:$from , FromCateg:$($_.fromcateg)" -ForegroundColor Yellow
                        node "$UniqueIdentifier$from" -Attributes @{Label = "$from"; shape = "$($Shapes[$($_.fromcateg)])"; style = "$($style[$($_.fromcateg)])" ; fillcolor = "$($color[$($_.fromcateg)])" }
                    }
                    else {
                        $to = $_.to
                        if (![string]::IsNullOrEmpty($to)) {
                            # Write-host "to:$to , toCateg:$($_.tocateg)" -ForegroundColor Yellow
                            node "$UniqueIdentifier$to" -Attributes @{Label = "$to"; shape = "$($Shapes[$($_.tocateg)])"; style = "$($style[$($_.tocateg)])" ; fillcolor = "$($color[$($_.tocateg)])" }
                        }
                    }
                }
            }
            #endregion plotting-all-remaining-nodes

        }
        $UniqueIdentifier = $UniqueIdentifier + 1
    } 
} | Export-PSGraph
#endregion graph-generation
