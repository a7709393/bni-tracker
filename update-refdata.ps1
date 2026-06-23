# Manual sync: scrape latest data from the traffic-light dashboard -> write to Firebase refdata
# Usage: powershell -ExecutionPolicy Bypass -File update-refdata.ps1
$ProgressPreference='SilentlyContinue'
$base='https://service-2026-937515995986.us-west1.run.app'
$fb='https://bni-tracker-b3ef8-default-rtdb.firebaseio.com'

# 1) find current bundle url (hash changes on each deploy)
$idx=(New-Object System.Net.WebClient).DownloadString("$base/")
$m=[regex]::Match($idx,'/assets/index-[^"]+\.js')
if(-not $m.Success){ Write-Error 'bundle not found'; exit 1 }
$bundleUrl=$base+$m.Value

# 2) download bundle as UTF-8
$bytes=(New-Object System.Net.WebClient).DownloadData($bundleUrl)
$js=[System.Text.Encoding]::UTF8.GetString($bytes)

# 3) parse members
function getn($s,$k){ $mm=[regex]::Match($s,[regex]::Escape($k)+':(-?[0-9.eE+]+)'); if($mm.Success){ return [double]$mm.Groups[1].Value }; return 0 }
$rd=@{}
$rx=[regex]'\{id:\d+,name:"([^"]+)",scores:\{([^}]*)\}\}'
foreach($mm in $rx.Matches($js)){
  $name=$mm.Groups[1].Value; $sc=$mm.Groups[2].Value
  $rd[$name]=[ordered]@{
    light = [int](getn $sc 'trafficLightScore')
    ref   = [int](-1*(getn $sc 'rolling6Months_referralDeficitWeekly'))
    o2o   = [int](-1*(getn $sc 'rolling6Months_oneToOneDeficitBiweekly'))
    guest = [int](-1*(getn $sc 'rolling6Months_guestDeficit'))
    train = [int](-1*(getn $sc 'rolling6Months_trainingDeficit'))
    biz   = [double](-1*(getn $sc 'rolling6Months_businessValueDeficit'))
  }
}
"members extracted = " + $rd.Count

# 4) write to Firebase (PUT replaces the refdata node)
$payload=@{ members=$rd; meta=@{ updatedAt=(Get-Date).ToString('yyyy/MM/dd HH:mm'); bundle=$m.Value } } | ConvertTo-Json -Depth 6
$resp=Invoke-WebRequest -Uri "$fb/refdata.json" -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 30
"Firebase PUT HTTP = " + $resp.StatusCode

# 5) dump full extracted table for verification
$rd.GetEnumerator() | Sort-Object {$_.Value.light} -Descending | ForEach-Object {
  "{0,-8} light={1,3}  ref={2} o2o={3} guest={4} train={5} biz={6}" -f $_.Key,$_.Value.light,$_.Value.ref,$_.Value.o2o,$_.Value.guest,$_.Value.train,$_.Value.biz
}
