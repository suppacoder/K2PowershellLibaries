[CmdletBinding()]
Param($Environment=$null, 
[bool]$RestartK2Server=$null , 
$DoNotStop=$false, 
$RootFilePath="$null", 
$ManifestFileName="$null", 
$ManifestFileRootNode="EnvironmentMetaData",
$ServiceBrokerMsbuildSubDirectory="..\K2Field.Utilities.ServiceObjectBuilder\MSBuild Folder",
$ConsoleMode=$false
)
Write-Debug "Deploy Service Brokers"
$CURRENTDIR=pwd
trap {write-host "error"+ $error[0].ToString() + $error[0].InvocationInfo.PositionMessage  -Foregroundcolor Red; cd "$CURRENTDIR"; read-host 'There has been an error'; break}

###$ErrorActionPreference ="Stop"
$ManifestFile="$RootFilePath$ManifestFileName"
Write-Verbose "** Finding manifest file @ $ManifestFile"


If (test-path $ManifestFile) 
{   
    Write-Verbose "** Manifest file found"
        
    $xml = [xml](get-content $ManifestFile)
    If($Environment -eq $null)
    {
        
        Write-Verbose "** No Environment passed in"
        "Environment not passed in, ask the user"
        
        $Environment=Get-EnvironmentFromUser($xml)
    }
    else
    {
        Write-Verbose "**Environment passed in = '$Environment'"
        
    }
        
    $K2SERVER= $xml.$ManifestFileRootNode.Environments.$Environment.K2Host
    $K2HOSTSERVERPORT= $xml.$ManifestFileRootNode.Environments.$Environment.K2HostPort
    
    write-verbose "** copying msbuild files to $Global_MsbuildPath"
    Copy-Item "$RootFilePath$ServiceBrokerMsbuildSubDirectory\*" $Global_MsbuildPath -recurse -force
    write-verbose "** finished copying msbuild files"
    
    If($RestartK2Server -eq $null)
    {
        $RestartK2Server=$true
        [bool]$prompt=$true
    }
    else
    {
        [bool]$prompt=$false
    }
    if ($RestartK2Server)
    {
		write-debug "Restart-K2Server -WaitUntilRestart $true -Prompt $prompt -ConsoleMode $ConsoleMode"
        Restart-K2Server -WaitUntilRestart $true -Prompt $prompt -ConsoleMode $ConsoleMode
    }
		    
    $delimiter="|"

    @($xml.SelectSingleNode("//ServiceTypes").ChildNodes) | ForEach-Object {
         write-verbose "Reading Service Type details:"
		 
         write-debug "deploy:$($_.deploy)  sysname:$($_.systemName)    $($_.guid)    dname:$($_.displayName)   InnerText:$($_.InnerText)  assembly:$($_.assemliesSourcePath)"
         If([System.Convert]::ToBoolean($_.deploy))
         {
			$CopySource=$_.assemliesSourcePath;
			$CopySource="$RootFilePath$CopySource"
			if ($_.assembliesSourcePath -ne "")
			{
				
				write-verbose "copy the source from $CopySource"
			}
			else
			{

				write-verbose "DO NOT copy the source from $CopySource"
			}
            Write-verbose "** Deploying Service Type $_.displayName to $K2SERVER port $K2HOSTSERVERPORT"
			write-debug "Publish-K2ServiceType $Global_FrameworkPath35 $RootFilePath$ServiceBrokerMsbuildSubDirectory\RegisterServiceType.msbuild $K2SERVER $K2HOSTSERVERPORT $($_.guid) $($_.systemName) $($_.displayName) $($_.description) $($_.className) $CopySource $($_.assembliesTargetPath) $($_.serviceTypeAssemblyName)"
            Publish-K2ServiceType $Global_FrameworkPath35 "$RootFilePath$ServiceBrokerMsbuildSubDirectory\RegisterServiceType.msbuild" $K2SERVER $K2HOSTSERVERPORT $_.guid $_.systemName $_.displayName $_.description $_.className "$CopySource" $_.assembliesTargetPath $_.serviceTypeAssemblyName
         }
         else
         {
            Write-verbose "** Skipping Service Type "  $_.displayName  " as it is configured not to deploy" -Foregroundcolor Yellow
         }
         $ServiceTypeGUID=$_.guid
         
         $_.SelectNodes("ServiceInstance") | 
         foreach { 
            #For every service instance Get the config name values pairs
            $ServiceInstanceKeyValues="";
            $ServiceInstanceKeyRequiredList="";
            $ServiceInstanceKeyNames="";
            
            If([System.Convert]::ToBoolean($_.deploy))
            {
                write-debug "** Getting Config values for  $($_.systemName)"
                
                $_.SelectSingleNode("Environment[@name='$Environment']").Config| 
                 foreach { 
                    write-debug "Config: $($_)"
                    write-debug "Config Value:  $($_.value)"
                    $ServiceInstanceKeyValue=$_.value
                    $ServiceInstanceKeyRequired=$_.keyRequired
                    $ServiceInstanceKeyName=$_.name
                    write-debug "** Found Config values for $ServiceInstanceKeyName"
                    write-debug "value is $ServiceInstanceKeyValue"
                    $ServiceInstanceKeyValues="$ServiceInstanceKeyValues$delimiter$ServiceInstanceKeyValue";
                    $ServiceInstanceKeyRequiredList="$ServiceInstanceKeyRequiredList$delimiter$ServiceInstanceKeyRequired";
                    $ServiceInstanceKeyNames="$ServiceInstanceKeyNames$delimiter$ServiceInstanceKeyName";
                    
                 }#end loop config namevalues
                 
                 $ServiceInstanceKeyValues=$ServiceInstanceKeyValues.Replace("{BlackPearlDir}", "$Global_K2BlackPearlDir")
                 $ServiceInstanceKeyValues=$ServiceInstanceKeyValues.TrimStart($delimiter);
                 $ServiceInstanceKeyRequiredList=$ServiceInstanceKeyRequiredList.TrimStart($delimiter);
                 $ServiceInstanceKeyNames=$ServiceInstanceKeyNames.TrimStart($delimiter);
                 write-debug "$ServiceInstanceKeyRequiredList"
                 write-debug "$ServiceInstanceKeyNames"
                 
                 Write-Verbose "* Deploying Service Instance  $($_.displayName)"
                 ###Param(                        $K2SERVER $K2HOSTSERVERPORT  $SERVICETYPEGUID, $SERVICEINSTANCEGUID,$SERVICEINSTANCESYSTEMNAME,$SERVICEINSTANCEDISPLAYNAME,$SERVICEINSTANCEDESCRIPTION, $CONFIGIMPERSONATE,$CONFIGKEYNAMES,$CONFIGKEYVALUES,                               $CONFIGKEYSREQUIRED)
                 write-debug "Publish-K2ServiceInstance    $FrameworkPath "$RootFilePath$ServiceBrokerMsbuildSubDirectory\RegisterServiceInstance.msbuild" $K2SERVER $K2HOSTSERVERPORT $ServiceTypeGUID  $($_.guid)                  $($_.systemName)         $($_.displayName)               $($_.description)               true $ServiceInstanceKeyNames $ServiceInstanceKeyValues $ServiceInstanceKeyRequiredList $delimiter"
                 Publish-K2ServiceInstance    $FrameworkPath "$RootFilePath$ServiceBrokerMsbuildSubDirectory\RegisterServiceInstance.msbuild" $K2SERVER $K2HOSTSERVERPORT $ServiceTypeGUID      $_.guid                  $_.systemName         $_.displayName               $_.description               $_.impersonate $ServiceInstanceKeyNames $ServiceInstanceKeyValues $ServiceInstanceKeyRequiredList $delimiter
             }
             else
             {
                write-verbose "** Skipping Service Instance $($_.systemName) as it is configured not to deploy"
             }   #If Deploy
         }   #endloop Service Instance
    }   #endloop Service Type
}
else
{
    Throw "You must have a ServiceBroker Manifest XML file at $ManifestFile"
}


If($DoNotStop){Write-Host "======Finished======"} else {Read-Host "======Finished======"}